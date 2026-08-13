// nfc_service.dart - reads a participant's Unique ID (e.g. "P-001") off an NFC
// tap card. Tags hold a single NDEF Text record written by the research team.
// On iOS a button press is required; on Android scanning can start automatically.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';

// Reads NFC login cards and returns the participant's ID.
class NfcService {
  bool _scanning = false;

  // ---- SCANNING ----

  // True when the device has NFC hardware and it's switched on.
  Future<bool> isAvailable() async {
    try {
      return await NfcManager.instance.isAvailable();
    } catch (e) {
      debugPrint('NfcService: isAvailable() failed - $e');
      return false;
    }
  }

  bool get isScanning => _scanning;

  // Start a scan. Returns the participant ID on success, or null on cancel/timeout/error.
  // On iOS this pops the system "Ready to Scan" sheet.
  Future<String?> startScan({
    String alertMessage = 'Hold your NFC card to the back of the phone.',
  }) async {
    if (_scanning) {
      debugPrint('NfcService: scan already in progress');
      return null;
    }
    // Clear stale diagnostic from the last scan.
    lastDiagnostic = null;
    final completer = Completer<String?>();
    _scanning = true;

    try {
      await NfcManager.instance.startSession(
        alertMessage: alertMessage,
        onDiscovered: (NfcTag tag) async {
          // _extractParticipantId is async because Android's cachedMessage
          // is often empty, so it falls back to a live ndef.read().
          final id = await _extractParticipantId(tag);
          try {
            await NfcManager.instance.stopSession(
              alertMessage: id != null ? 'Logged in.' : null,
              errorMessage: id == null ? 'Tag not recognised.' : null,
            );
          } catch (_) {/* swallow - session may already be torn down */}
          _scanning = false;
          if (!completer.isCompleted) completer.complete(id);
        },
      );
    } catch (e) {
      debugPrint('NfcService: startSession() threw - $e');
      _scanning = false;
      if (!completer.isCompleted) completer.complete(null);
    }

    // Give up after 20 seconds so the login screen never hangs.
    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () async {
        await stopScan();
        lastDiagnostic =
            'Scan timed out - no tag detected. Hold the card flat against '
            'the back of the phone and try again.';
        debugPrint('NfcService: $lastDiagnostic');
        _scanning = false;
        return null;
      },
    );
  }

  // Cancel an in-progress scan. Safe to call when nothing is scanning.
  Future<void> stopScan() async {
    if (!_scanning) return;
    _scanning = false;
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {/* swallow */}
  }

  // ---- PARSING ----
  // Tags normally hold a single NDEF Text record with the Unique ID.
  // Falls back to URI format (ccq://login/P-001) or raw UTF-8 if needed.

  // Last parse result or error message. Cleared on the next startScan.
  String? lastDiagnostic;

  // Pull the Unique ID out of a scanned tag. Tries Text format first,
  // then URI, then raw UTF-8.
  Future<String?> _extractParticipantId(NfcTag tag) async {
    lastDiagnostic = null;
    try {
      final ndef = Ndef.from(tag);
      if (ndef == null) {
        lastDiagnostic = 'Tag had no NDEF data - likely a blank tag or '
            'a non-NDEF format (Mifare Classic etc.). Re-flash with '
            'a Text record.';
        debugPrint('NfcService: $lastDiagnostic');
        return null;
      }
      // On Android the cached message is often empty, so fall back to a live read.
      var cached = ndef.cachedMessage;
      if (cached == null || cached.records.isEmpty) {
        try {
          cached = await ndef.read();
        } catch (e) {
          lastDiagnostic = 'Tag is NDEF but no cached message and a live '
              'read failed: $e';
          debugPrint('NfcService: $lastDiagnostic');
          return null;
        }
      }
      if (cached.records.isEmpty) {
        lastDiagnostic = 'Tag is NDEF but carries no records.';
        debugPrint('NfcService: $lastDiagnostic');
        return null;
      }

      // Try each record; first non-empty parse wins.
      final perRecord = <String>[];

      for (final record in cached.records) {
        final tnf = record.typeNameFormat;
        final typeStr = String.fromCharCodes(record.type);
        final payloadLen = record.payload.length;

        if (tnf == NdefTypeNameFormat.nfcWellknown) {
          if (typeStr == 'T') {
            final text = _decodeTextPayload(record.payload);
            if (text != null && text.isNotEmpty) {
              final id = _normaliseId(text);
              lastDiagnostic = 'Parsed NDEF Text record → "$id"';
              debugPrint('NfcService: $lastDiagnostic');
              return id;
            }
            perRecord.add('T record (${payloadLen}B) - empty after decode');
          } else if (typeStr == 'U') {
            final uri = _decodeUriPayload(record.payload);
            if (uri != null && uri.isNotEmpty) {
              final id = _normaliseId(_idFromUri(uri));
              if (id.isNotEmpty) {
                lastDiagnostic =
                    'Parsed NDEF URI record "$uri" → "$id"';
                debugPrint('NfcService: $lastDiagnostic');
                return id;
              }
            }
            perRecord.add('U record (${payloadLen}B) - could not extract id');
          } else {
            perRecord.add('Well-known type "$typeStr" - not handled');
          }
        } else {
          // Last resort: try reading the raw bytes as UTF-8.
          try {
            final raw =
                utf8.decode(record.payload, allowMalformed: true).trim();
            if (raw.isNotEmpty) {
              final id = _normaliseId(raw);
              if (id.isNotEmpty) {
                lastDiagnostic = 'Parsed non-NDEF record (TNF=${tnf.name}, '
                    'type="$typeStr") as raw UTF-8 → "$id"';
                debugPrint('NfcService: $lastDiagnostic');
                return id;
              }
            }
            perRecord.add(
              'TNF=${tnf.name} type="$typeStr" - UTF-8 decode produced empty',
            );
          } catch (_) {
            perRecord.add(
              'TNF=${tnf.name} type="$typeStr" - UTF-8 decode failed',
            );
          }
        }
      }

      lastDiagnostic =
          'Tag had ${cached.records.length} record(s) but none yielded '
          'a Unique ID: ${perRecord.join('; ')}';
      debugPrint('NfcService: $lastDiagnostic');
    } catch (e) {
      lastDiagnostic = 'Parse threw: $e';
      debugPrint('NfcService: $lastDiagnostic');
    }
    return null;
  }

  // Decode an NDEF Text record. Byte 0 holds the language-code length and
  // the encoding (UTF-8 vs UTF-16); the actual text follows after the language code.
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

  // Decode big-endian UTF-16 bytes into character codes.
  Iterable<int> _utf16BeDecode(List<int> bytes) sync* {
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      yield (bytes[i] << 8) | bytes[i + 1];
    }
  }

  // Decode an NDEF URI record. Byte 0 is a prefix shorthand (NFC Forum table 7);
  // the rest is UTF-8 text.
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

  // Extract the participant ID from a URI (handles our ccq:// scheme and ?id= params).
  String _idFromUri(String uri) {
    final qIndex = uri.indexOf('id=');
    if (qIndex >= 0) return uri.substring(qIndex + 3).split('&').first;
    if (uri.contains('/')) return uri.split('/').last;
    if (uri.contains(':')) return uri.split(':').last;
    return uri;
  }

  // Trim and collapse internal spaces (e.g. "P- 001" becomes "P-001").
  String _normaliseId(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), '');
}
