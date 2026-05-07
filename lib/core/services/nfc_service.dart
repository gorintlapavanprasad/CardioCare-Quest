// NfcService — wraps `nfc_manager` for the project's specific needs:
// reading a participant's Unique ID off an NFC tag at login time.
//
// Tags are flashed by the research team as a single NDEF Text record
// containing the Unique ID (e.g. "P-001"). This service exposes:
//   • [isAvailable] — does the device hardware + OS support reading?
//   • [startScan]   — begin a session, resolve with the parsed ID
//                     on the first read (or null if cancelled /
//                     unparseable).
//   • [stopScan]    — cancel an in-flight scan when leaving the
//                     login screen.
//
// Platform behaviour:
//   • Android — scan can run silently while the screen is foregrounded;
//     no system UI required (the OS plays the standard tap chime).
//   • iOS    — Apple's Core NFC requires an explicit user action to
//     start scanning; the system "Ready to Scan" sheet appears
//     immediately. Hence the login screen exposes a button for both
//     platforms (one tap → start scan).
//   • iPads / NFC-less Androids — `isAvailable()` returns false, the
//     login screen hides the NFC affordance and only manual ID entry
//     is shown.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';

class NfcService {
  bool _scanning = false;

  /// True when the device has NFC hardware enabled. Returns false on
  /// iPads, on Androids without an NFC chip, and when NFC is switched
  /// off in system settings. Callers should hide / disable any NFC
  /// UI when this returns false.
  Future<bool> isAvailable() async {
    try {
      return await NfcManager.instance.isAvailable();
    } catch (e) {
      debugPrint('NfcService: isAvailable() failed — $e');
      return false;
    }
  }

  bool get isScanning => _scanning;

  /// Begin an NFC scan session. Resolves with the parsed participant
  /// ID on the first tag read, or `null` if cancelled / timed out /
  /// the tag couldn't be parsed.
  ///
  /// On iOS this triggers the system "Ready to Scan" modal. On Android
  /// the scan runs silently — the OS plays the standard tap chime when
  /// a tag is detected. [alertMessage] is the iOS-only modal copy.
  Future<String?> startScan({
    String alertMessage = 'Hold your NFC card to the back of the phone.',
  }) async {
    if (_scanning) {
      debugPrint('NfcService: scan already in progress');
      return null;
    }
    final completer = Completer<String?>();
    _scanning = true;

    try {
      await NfcManager.instance.startSession(
        alertMessage: alertMessage,
        onDiscovered: (NfcTag tag) async {
          final id = _extractParticipantId(tag);
          try {
            await NfcManager.instance.stopSession(
              alertMessage: id != null ? 'Logged in.' : null,
              errorMessage: id == null ? 'Tag not recognised.' : null,
            );
          } catch (_) {/* swallow — session may already be torn down */}
          _scanning = false;
          if (!completer.isCompleted) completer.complete(id);
        },
      );
    } catch (e) {
      debugPrint('NfcService: startSession() threw — $e');
      _scanning = false;
      if (!completer.isCompleted) completer.complete(null);
    }

    return completer.future;
  }

  /// Cancel an in-flight scan. Safe to call when no scan is active.
  Future<void> stopScan() async {
    if (!_scanning) return;
    _scanning = false;
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {/* swallow */}
  }

  // ────────────────────────────────────────────────────────────────────
  // PARSING
  //
  // Research team flashes tags as a single NDEF Text record holding
  // just the Unique ID (e.g. "P-001"). We tolerate two extra layouts
  // in case a tag is re-flashed differently:
  //   1. NDEF URI record like "ccq://login/P-001" or "ccq:P-001".
  //   2. Anything else — fall back to UTF-8 decoding the raw payload.
  //
  // Recovered text gets `_normaliseId`'d (trimmed, whitespace stripped).
  // ────────────────────────────────────────────────────────────────────

  String? _extractParticipantId(NfcTag tag) {
    try {
      final ndef = Ndef.from(tag);
      if (ndef == null) return null;
      final cached = ndef.cachedMessage;
      if (cached == null || cached.records.isEmpty) return null;

      for (final record in cached.records) {
        final tnf = record.typeNameFormat;

        if (tnf == NdefTypeNameFormat.nfcWellknown) {
          final type = String.fromCharCodes(record.type);
          if (type == 'T') {
            final text = _decodeTextPayload(record.payload);
            if (text != null && text.isNotEmpty) return _normaliseId(text);
          } else if (type == 'U') {
            final uri = _decodeUriPayload(record.payload);
            if (uri != null && uri.isNotEmpty) {
              return _normaliseId(_idFromUri(uri));
            }
          }
        } else {
          // Last-resort raw UTF-8 — covers tags written outside the
          // canonical Text / URI formats.
          try {
            final raw =
                utf8.decode(record.payload, allowMalformed: true).trim();
            if (raw.isNotEmpty) return _normaliseId(raw);
          } catch (_) {/* fall through */}
        }
      }
    } catch (e) {
      debugPrint('NfcService: parse error — $e');
    }
    return null;
  }

  /// NDEF Text record payload layout:
  ///   byte 0       : status — top bit = 0 (UTF-8) / 1 (UTF-16),
  ///                  low 6 bits = language-code length
  ///   bytes 1..1+L : language code (e.g. "en")
  ///   bytes 1+L..  : the actual text
  String? _decodeTextPayload(List<int> payload) {
    if (payload.isEmpty) return null;
    final status = payload[0];
    final langLen = status & 0x3F;
    final isUtf16 = (status & 0x80) != 0;
    final start = 1 + langLen;
    if (start >= payload.length) return null;
    final bytes = payload.sublist(start);
    try {
      return isUtf16
          ? String.fromCharCodes(_utf16BeDecode(bytes))
          : utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  Iterable<int> _utf16BeDecode(List<int> bytes) sync* {
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      yield (bytes[i] << 8) | bytes[i + 1];
    }
  }

  /// NDEF URI record payload layout:
  ///   byte 0    : URI prefix shorthand code (NFC Forum spec — table 7)
  ///   bytes 1.. : the rest of the URI
  String? _decodeUriPayload(List<int> payload) {
    if (payload.isEmpty) return null;
    const prefixes = <String>[
      '',
      'http://www.', 'https://www.', 'http://', 'https://',
      'tel:', 'mailto:',
      'ftp://anonymous:anonymous@', 'ftp://ftp.', 'ftps://',
      'sftp://', 'smb://', 'nfs://', 'ftp://', 'dav://',
      'news:', 'telnet://', 'imap:', 'rtsp://', 'urn:', 'pop:',
      'sip:', 'sips:', 'tftp:', 'btspp://', 'btl2cap://',
      'btgoep://', 'tcpobex://', 'irdaobex://', 'file://',
      'urn:epc:id:', 'urn:epc:tag:', 'urn:epc:pat:', 'urn:epc:raw:',
      'urn:epc:', 'urn:nfc:',
    ];
    final code = payload[0];
    final prefix = code < prefixes.length ? prefixes[code] : '';
    try {
      return prefix + utf8.decode(payload.sublist(1));
    } catch (_) {
      return null;
    }
  }

  /// Pull a Unique ID out of a URI we wrote ourselves. Handles:
  ///   ccq://login/P-001       → P-001
  ///   ccq:P-001               → P-001
  ///   https://x.app/?id=P-001 → P-001
  String _idFromUri(String uri) {
    final qIndex = uri.indexOf('id=');
    if (qIndex >= 0) return uri.substring(qIndex + 3).split('&').first;
    if (uri.contains('/')) return uri.split('/').last;
    if (uri.contains(':')) return uri.split(':').last;
    return uri;
  }

  String _normaliseId(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), '');
}
