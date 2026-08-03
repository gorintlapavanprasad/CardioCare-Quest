// joint_setup_screen.dart - the quick "set up together" wizard a caregiver
// runs before handing the phone to the participant. Three steps (who's
// helping, text size, pace), then it starts the shared session.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cardio_care_quest/core/hooks/hooks.dart';
import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:cardio_care_quest/core/services/session_settings_service.dart';
import 'package:cardio_care_quest/core/theme/app_colors.dart';

/// Joint setup for a caregiver + participant co-play session.
///
/// Three quick steps - who's helping, text size, pace - then a "hand to the
/// participant" confirmation that starts the paired session (via [PairHooks])
/// and applies the chosen settings globally (via [SessionSettingsService]).
///
/// Pops with `true` once a session has started so the launching screen can
/// switch to the caregiver view.
class JointSetupScreen extends StatefulWidget {
  const JointSetupScreen({super.key});

  @override
  State<JointSetupScreen> createState() => _JointSetupScreenState();
}

class _JointSetupScreenState extends State<JointSetupScreen> {
  int _step = 0; // which of the 3 setup steps we're on
  final TextEditingController _caregiverController = TextEditingController(); // caregiver name box
  double _textScale = 1.0; // chosen text size (1.0 = normal)
  SessionPace _pace = SessionPace.standard; // chosen game speed
  bool _starting = false; // true while the session is being created

  // The text-size choices and their friendly labels (must line up 1-to-1).
  static const _textScaleOptions = <double>[1.0, 1.3, 1.6, 2.0];
  static const _textScaleLabels = <String>['Default', 'Large', 'Larger', 'Largest'];

  @override
  void dispose() {
    _caregiverController.dispose();
    super.dispose();
  }

  // Last step: apply the chosen settings app-wide and start the paired
  // session, then close this screen (returning true = "we started").
  Future<void> _finish() async {
    if (_starting) return;
    setState(() => _starting = true);

    final participantId = context.read<UserDataProvider>().uid;
    final settings =
        SessionSettings(textScale: _textScale, pace: _pace);

    // Apply text size / pace immediately for the whole app.
    SessionSettingsService.instance.apply(settings);

    final label = _caregiverController.text.trim();
    await PairHooks.start(
      participantId: participantId,
      caregiverLabel: label.isEmpty ? null : label,
      settings: settings.toMap(),
    );

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  // The screen shell: progress dots on top, the current step, nav buttons below.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Set up together'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StepDots(current: _step, total: 3),
              const SizedBox(height: 24),
              Expanded(child: SingleChildScrollView(child: _buildStep())),
              const SizedBox(height: 16),
              _buildNav(),
            ],
          ),
        ),
      ),
    );
  }

  // Picks which step's content to show based on _step.
  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _caregiverStep();
      case 1:
        return _textSizeStep();
      default:
        return _paceStep();
    }
  }

  // Step 1: optional caregiver label (e.g. "Daughter", "Nurse").
  Widget _caregiverStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Who is helping today?',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.title)),
        const SizedBox(height: 8),
        const Text(
          'Optional - a label for the caregiver so their notes and help '
          'markers are recorded. e.g. "Daughter", "Nurse".',
          style: TextStyle(fontSize: 16, color: AppColors.subtitle),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _caregiverController,
          decoration: InputDecoration(
            hintText: 'Caregiver label',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: AppColors.cardBorder)),
          ),
        ),
      ],
    );
  }

  // Step 2: pick a comfortable text size (the tiles preview it live).
  Widget _textSizeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Choose a comfortable text size',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.title)),
        const SizedBox(height: 8),
        const Text('The preview updates as you choose.',
            style: TextStyle(fontSize: 16, color: AppColors.subtitle)),
        const SizedBox(height: 24),
        for (var i = 0; i < _textScaleOptions.length; i++)
          _sizeTile(_textScaleOptions[i], _textScaleLabels[i]),
      ],
    );
  }

  // One text-size choice row. Its own text is shown at that size as a preview.
  Widget _sizeTile(double scale, String label) {
    final selected = _textScale == scale;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _textScale = scale),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withValues(alpha: 0.12) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: selected ? AppColors.primary : AppColors.cardBorder, width: 2),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text('$label - Aa',
                    style: TextStyle(
                        fontSize: 18 * scale,
                        fontWeight: FontWeight.w600,
                        color: AppColors.title)),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  // Step 3: pick the game pace (how much time to allow on each step).
  Widget _paceStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Set the pace',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.title)),
        const SizedBox(height: 8),
        const Text('How much time to allow during games.',
            style: TextStyle(fontSize: 16, color: AppColors.subtitle)),
        const SizedBox(height: 24),
        _paceTile(SessionPace.relaxed, 'Relaxed', 'More time on every step'),
        _paceTile(SessionPace.standard, 'Standard', 'The usual timing'),
        _paceTile(SessionPace.brisk, 'Brisk', 'A quicker rhythm'),
      ],
    );
  }

  // One pace choice row (title + short description).
  Widget _paceTile(SessionPace pace, String title, String subtitle) {
    final selected = _pace == pace;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _pace = pace),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withValues(alpha: 0.12) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: selected ? AppColors.primary : AppColors.cardBorder, width: 2),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.title)),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 14, color: AppColors.subtitle)),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  // The bottom Back / Next row. On the last step "Next" becomes the finish button.
  Widget _buildNav() {
    final isLast = _step == 2;
    return Row(
      children: [
        if (_step > 0)
          TextButton(
            onPressed: _starting ? null : () => setState(() => _step -= 1),
            child: const Text('Back'),
          ),
        const Spacer(),
        ElevatedButton(
          onPressed: _starting
              ? null
              : () {
                  if (isLast) {
                    _finish();
                  } else {
                    setState(() => _step += 1);
                  }
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          child: _starting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(isLast ? 'Hand to participant' : 'Next'),
        ),
      ],
    );
  }
}

// The little progress bars at the top: filled up to the current step.
class _StepDots extends StatelessWidget {
  final int current;
  final int total;
  const _StepDots({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < total; i++)
          Expanded(
            child: Container(
              height: 6,
              margin: EdgeInsets.only(right: i == total - 1 ? 0 : 8),
              decoration: BoxDecoration(
                color: i <= current ? AppColors.primary : AppColors.cardBorder,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ],
    );
  }
}
