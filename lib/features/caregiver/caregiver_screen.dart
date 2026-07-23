// caregiver_screen.dart - the helper's dashboard during a paired session.
// Shows what game the participant is on, lets the caregiver tap "I helped",
// jot notes, and end the session. It reads the session live from the cloud.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:cardio_care_quest/core/hooks/hooks.dart';
import 'package:cardio_care_quest/core/services/session_manager.dart';
import 'package:cardio_care_quest/core/theme/app_colors.dart';

/// Caregiver view for an active paired session. Shows what the participant is
/// doing (current game + difficulty), lets the caregiver mark when help was
/// given, and records free-text notes. Reads live from `pairedSessions/{id}`.
class CaregiverScreen extends StatefulWidget {
  const CaregiverScreen({super.key});

  @override
  State<CaregiverScreen> createState() => _CaregiverScreenState();
}

class _CaregiverScreenState extends State<CaregiverScreen> {
  final TextEditingController _noteController = TextEditingController(); // the note text box
  bool _savingNote = false; // true while a note is being saved

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  // Record that the caregiver helped with a step, then confirm on screen.
  Future<void> _markHelp() async {
    await CaregiverHooks.markHelp(helpType: 'general');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Help marked'), duration: Duration(seconds: 1)),
    );
  }

  // Save the typed note. Does nothing if it's empty or already saving.
  Future<void> _saveNote() async {
    final text = _noteController.text.trim();
    if (text.isEmpty || _savingNote) return;
    setState(() => _savingNote = true);
    await CaregiverHooks.addNote(text);
    if (!mounted) return;
    _noteController.clear();
    setState(() => _savingNote = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Note saved'), duration: Duration(seconds: 1)),
    );
  }

  // End the paired session and close this screen.
  Future<void> _endSession() async {
    await PairHooks.end();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // The screen: if a session is active show the cards, otherwise a hint.
  @override
  Widget build(BuildContext context) {
    final pairedSessionId = SessionManager.pairedSessionId;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Caregiver'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (pairedSessionId != null)
            TextButton(
              onPressed: _endSession,
              child: const Text('End'),
            ),
        ],
      ),
      body: pairedSessionId == null
          ? const _NoSession()
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _liveContextCard(pairedSessionId),
                    const SizedBox(height: 20),
                    _markHelpCard(),
                    const SizedBox(height: 20),
                    _notesCard(),
                  ],
                ),
              ),
            ),
    );
  }

  // Live "Now playing" card. It listens to the session in the cloud and
  // updates by itself as the participant moves between games.
  Widget _liveContextCard(String pairedSessionId) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(FirestorePaths.pairedSessions)
          .doc(pairedSessionId)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? const <String, dynamic>{};
        final game = (data['currentGame'] ?? SessionManager.currentGame) as String?;
        final difficulty = data['currentDifficulty']?.toString();
        final helpCount = (data['helpMarkerCount'] as num?)?.toInt() ?? 0;
        final caregiver = data['caregiverLabel'] as String?;

        return _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Now playing',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.subtitle)),
              const SizedBox(height: 6),
              Text(game ?? 'On the dashboard',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.title)),
              if (difficulty != null) ...[
                const SizedBox(height: 4),
                Text('Difficulty: $difficulty',
                    style: const TextStyle(
                        fontSize: 16, color: AppColors.body)),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  _pill('Help given: $helpCount'),
                  const SizedBox(width: 8),
                  if (caregiver != null) _pill(caregiver),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // Card with the big "Mark help given" button.
  Widget _markHelpCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Give a hand',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.title)),
          const SizedBox(height: 4),
          const Text('Tap whenever you help the participant with a step.',
              style: TextStyle(fontSize: 14, color: AppColors.subtitle)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _markHelp,
            icon: const Icon(Icons.pan_tool_alt),
            label: const Text('Mark help given'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ),
    );
  }

  // Card with the notes box and a Save button.
  Widget _notesCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Notes',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.title)),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'What went well? What was hard?',
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.cardBorder)),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: _savingNote ? null : _saveNote,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _savingNote
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save note'),
            ),
          ),
        ],
      ),
    );
  }

  // A small rounded label chip (e.g. "Help given: 3").
  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primary)),
    );
  }

  // Shared white rounded-box wrapper used by every card above.
  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: child,
    );
  }
}

// Shown when there's no active paired session - just a "start one" hint.
class _NoSession extends StatelessWidget {
  const _NoSession();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'No paired session is active. Start one from the dashboard.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: AppColors.subtitle),
        ),
      ),
    );
  }
}
