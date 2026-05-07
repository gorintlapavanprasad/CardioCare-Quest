// BuildGameScreen — the "Design Your Own Game" form.
//
// Replaces the placeholder ComingSoonScreen the dashboard used to push
// for the Design Your Own Game tile. Lets the participant author a
// personal goal:
//
//   • Title — required
//   • Description — optional context for the goal
//   • Category — one of the 5 pillars (drives the icon + dashboard grouping)
//   • Points reward — discrete steps 10 / 25 / 50 / 75 / 100
//
// On Create:
//   • CustomGamesRepository.create writes the doc via OfflineQueue
//     (offline-safe; replays when connectivity returns)
//   • TelemetryHooks.logEvent('custom_game_created', ...) fires so
//     researchers can see how many participants used the feature
//   • Pop back to the dashboard, which has a StreamBuilder watching
//     the customGames collection — the new card shows up instantly.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/hooks/hooks.dart';
import '../../../core/providers/user_data_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../game_stories.dart';
import 'custom_game.dart';
import 'custom_games_repository.dart';

class BuildGameScreen extends StatefulWidget {
  const BuildGameScreen({super.key});

  @override
  State<BuildGameScreen> createState() => _BuildGameScreenState();
}

class _BuildGameScreenState extends State<BuildGameScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  // Quiz questions. Starts with one. Participants can add up to
  // [_maxQuestions] questions and remove all but the last. Each draft
  // owns its own controllers; we dispose them when removed.
  final List<_QuestionDraft> _quizQuestions = [_QuestionDraft()];

  // Default to walking quest — most participants want to track movement,
  // and that's the type that demonstrates the real hook chain
  // (LocationDispatcher + MovementHooks). Quiz is the alternative for
  // a pure-survey style goal.
  CustomGameType _gameType = CustomGameType.walk;
  GameCategory _category = GameCategory.exercise;
  int _pointsReward = 25;
  // Walk-type target distance presets — same scale as Dog Quest
  // (Easy/Medium/Hard at 500/1000/1500m).
  int _targetDistance = 500;
  bool _saving = false;

  // Reward presets — keeps the choice quick (no slider fiddling) and
  // bounded so participants can't set absurdly high rewards. Mirrors
  // the points scale used by the catalog games (Dog Quest 30/60/100,
  // Quiet Minute 50, etc.).
  static const _pointOptions = <int>[10, 25, 50, 75, 100];

  // Cap on quiz questions per game. Five matches the post-play
  // survey's question count and keeps the form scrollable on small
  // phones without becoming overwhelming for older participants.
  static const _maxQuestions = 5;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    for (final q in _quizQuestions) {
      q.dispose();
    }
    super.dispose();
  }

  void _addQuestion() {
    if (_quizQuestions.length >= _maxQuestions) return;
    setState(() => _quizQuestions.add(_QuestionDraft()));
  }

  void _removeQuestion(int index) {
    if (_quizQuestions.length <= 1) return;
    setState(() {
      _quizQuestions.removeAt(index).dispose();
    });
  }

  Future<void> _handleCreate() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final userProvider = Provider.of<UserDataProvider>(context, listen: false);
    final uid = userProvider.uid;

    if (uid.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Sign in first, then come back here.'),
      ));
      setState(() => _saving = false);
      return;
    }

    // Quiz-type validation — walk-type skips this. Each question
    // needs both a prompt and at least two non-empty options.
    final List<QuizQuestion> questions;
    if (_gameType == CustomGameType.quiz) {
      final collected = <QuizQuestion>[];
      for (var i = 0; i < _quizQuestions.length; i++) {
        final draft = _quizQuestions[i];
        final prompt = draft.promptController.text.trim();
        final opts = draft.collectOptions();
        if (prompt.isEmpty) {
          messenger.showSnackBar(SnackBar(
            content: Text('Question ${i + 1} needs a prompt.'),
          ));
          setState(() => _saving = false);
          return;
        }
        if (opts.length < 2) {
          messenger.showSnackBar(SnackBar(
            content: Text(
                'Question ${i + 1} needs at least two answer choices.'),
          ));
          setState(() => _saving = false);
          return;
        }
        collected.add(QuizQuestion(prompt: prompt, options: opts));
      }
      questions = collected;
    } else {
      questions = const <QuizQuestion>[];
    }

    final draft = CustomGame(
      id: '',
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      category: _category,
      pointsReward: _pointsReward,
      gameType: _gameType,
      // Only walk-type uses targetDistance; for quiz we save 0.
      targetDistance:
          _gameType == CustomGameType.walk ? _targetDistance : 0,
      // Multi-question structure for quiz games. Legacy `prompt` +
      // `options` are mirrored from the first question so older
      // clients (or any code still reading those fields) continue
      // to work; new players read from `questions` directly.
      questions: questions,
      prompt: questions.isNotEmpty ? questions.first.prompt : '',
      options:
          questions.isNotEmpty ? questions.first.options : const <String>[],
    );

    try {
      final id = await CustomGamesRepository.instance.create(
        uid: uid,
        draft: draft,
      );
      // Telemetry — researchers track engagement with the feature.
      // No PII; the title is intentionally omitted to keep events PII-clean.
      // ignore: unawaited_futures
      TelemetryHooks.logEvent(
        'custom_game_created',
        parameters: {
          'gameId': id,
          'category': _category.name,
          'pointsReward': _pointsReward,
          'titleLength': draft.title.length,
          'hasDescription': draft.description.isNotEmpty,
        },
        userId: uid,
      );

      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Created "${draft.title}"'),
        duration: const Duration(seconds: 2),
      ));
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Could not save your game: $e'),
      ));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Design Your Own Game',
          style: TextStyle(color: AppColors.title),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.title),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              const _Hint(
                text:
                    'Build a personal goal that fits your day. Pick a category, name the goal, and choose how many points it should be worth. Tap your goal on the dashboard each time you do it to earn the points.',
              ),
              const SizedBox(height: 24),
              _SectionLabel('What do you want to do?'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _titleController,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 60,
                inputFormatters: [LengthLimitingTextInputFormatter(60)],
                decoration: _inputDecoration(
                  hint: 'e.g. Walk to the mailbox',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Give your goal a short name.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _SectionLabel('Add a note (optional)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 160,
                maxLines: 3,
                inputFormatters: [LengthLimitingTextInputFormatter(160)],
                decoration: _inputDecoration(
                  hint:
                      'A reminder or detail — e.g. "after lunch, twice around the block"',
                ),
              ),
              const SizedBox(height: 24),
              _SectionLabel('What kind of game?'),
              const SizedBox(height: 8),
              _GameTypePicker(
                selected: _gameType,
                onChanged: (type) => setState(() => _gameType = type),
              ),
              const SizedBox(height: 24),
              // Walk-type: target distance picker. Plays back as a
              // GPS-tracked quest using LocationDispatcher + MovementHooks.
              if (_gameType == CustomGameType.walk) ...[
                _SectionLabel('How far do you want to walk?'),
                const SizedBox(height: 8),
                _DistancePicker(
                  selected: _targetDistance,
                  onChanged: (d) => setState(() => _targetDistance = d),
                ),
                const SizedBox(height: 24),
              ],
              // Quiz-type: dynamic list of questions. Plays back as a
              // multi-step survey — the participant cycles through
              // each question in order, and SurveyHooks submits one
              // structured payload at the end of play.
              if (_gameType == CustomGameType.quiz) ...[
                for (var i = 0; i < _quizQuestions.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _QuestionCard(
                      index: i,
                      draft: _quizQuestions[i],
                      canRemove: _quizQuestions.length > 1,
                      onRemove: () => _removeQuestion(i),
                      buildInputDecoration: _inputDecoration,
                    ),
                  ),
                if (_quizQuestions.length < _maxQuestions)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _addQuestion,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(
                          'Add another question (${_quizQuestions.length}/$_maxQuestions)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary, width: 1.5),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
              ],
              _SectionLabel('Which area is this about?'),
              const SizedBox(height: 8),
              _CategoryPicker(
                selected: _category,
                onChanged: (cat) => setState(() => _category = cat),
              ),
              const SizedBox(height: 24),
              _SectionLabel('Points to earn each time you do it'),
              const SizedBox(height: 8),
              _PointsPicker(
                selected: _pointsReward,
                options: _pointOptions,
                onChanged: (pts) => setState(() => _pointsReward = pts),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                  onPressed: _saving ? null : _handleCreate,
                  child: _saving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'CREATE GOAL',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      counterText: '',
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.title,
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline,
              color: AppColors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.title,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card row for picking the game's TYPE — walk vs quiz. Drives which
/// player + which hook chain plays back when the participant taps the
/// custom game later.
class _GameTypePicker extends StatelessWidget {
  final CustomGameType selected;
  final ValueChanged<CustomGameType> onChanged;
  const _GameTypePicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: CustomGameType.values.map((type) {
        final isSelected = type == selected;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: isSelected ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onChanged(type),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.cardBorder,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      type.icon,
                      size: 28,
                      color: isSelected ? Colors.white : AppColors.primary,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            type.label,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: isSelected ? Colors.white : AppColors.title,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            type.tagline,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.92)
                                  : AppColors.subtitle,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Pill row for picking the walk target distance. Same scale Dog Quest
/// uses (Easy/Medium/Hard at 500/1000/1500m) so participants who've
/// played Dog Quest already understand the scale.
class _DistancePicker extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  const _DistancePicker({required this.selected, required this.onChanged});

  static const _options = <(int, String)>[
    (500, 'Easy · 500m'),
    (1000, 'Medium · 1km'),
    (1500, 'Hard · 1.5km'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _options.map((opt) {
        return _PickerChip(
          label: opt.$2,
          selected: opt.$1 == selected,
          onTap: () => onChanged(opt.$1),
        );
      }).toList(),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  final GameCategory selected;
  final ValueChanged<GameCategory> onChanged;

  const _CategoryPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: GameCategory.values.map((cat) {
        final isSelected = cat == selected;
        return _PickerChip(
          icon: cat.icon,
          label: cat.label,
          selected: isSelected,
          onTap: () => onChanged(cat),
        );
      }).toList(),
    );
  }
}

class _PointsPicker extends StatelessWidget {
  final int selected;
  final List<int> options;
  final ValueChanged<int> onChanged;

  const _PointsPicker({
    required this.selected,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((pts) {
        return _PickerChip(
          label: '$pts pts',
          selected: pts == selected,
          onTap: () => onChanged(pts),
        );
      }).toList(),
    );
  }
}

/// Reusable selectable pill used for both category and points pickers.
/// Two-line variant when [icon] is provided (icon stacked above label),
/// single-line otherwise.
class _PickerChip extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PickerChip({
    this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppColors.primary : Colors.white;
    final fg = selected ? Colors.white : AppColors.title;
    final border = selected ? AppColors.primary : AppColors.cardBorder;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: icon != null ? 14 : 18,
            vertical: icon != null ? 10 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: 1.5),
          ),
          child: icon != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: fg),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ],
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Mutable working state for a single quiz question while the
/// participant is filling out the form. The screen owns a list of
/// these and translates them to immutable [QuizQuestion]s on save.
class _QuestionDraft {
  final TextEditingController promptController;
  // Up to 4 option text fields — first 2 default to "Yes" / "No" so
  // a participant can create a usable question without typing any
  // option text. Empty optional fields are dropped at submit.
  final List<TextEditingController> optionControllers;

  _QuestionDraft()
      : promptController = TextEditingController(),
        optionControllers = [
          TextEditingController(text: 'Yes'),
          TextEditingController(text: 'No'),
          TextEditingController(),
          TextEditingController(),
        ];

  void dispose() {
    promptController.dispose();
    for (final c in optionControllers) {
      c.dispose();
    }
  }

  List<String> collectOptions() => optionControllers
      .map((c) => c.text.trim())
      .where((t) => t.isNotEmpty)
      .toList();
}

/// Card UI for one question in the build form. Shows a numbered
/// header, the prompt input, four answer-option inputs (the first two
/// labelled required), and an optional "remove" button when the
/// parent has more than one question in the list.
class _QuestionCard extends StatelessWidget {
  final int index;
  final _QuestionDraft draft;
  final bool canRemove;
  final VoidCallback onRemove;
  final InputDecoration Function({required String hint}) buildInputDecoration;

  const _QuestionCard({
    required this.index,
    required this.draft,
    required this.canRemove,
    required this.onRemove,
    required this.buildInputDecoration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Question ${index + 1}',
                  style: const TextStyle(
                    color: AppColors.title,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (canRemove)
                TextButton.icon(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    minimumSize: const Size(0, 32),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: draft.promptController,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 120,
            maxLines: 2,
            inputFormatters: [LengthLimitingTextInputFormatter(120)],
            decoration: buildInputDecoration(
              hint: 'e.g. Did I take my medicine today?',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Answer choices (at least two)',
            style: TextStyle(
              color: AppColors.subtitle,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < draft.optionControllers.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextFormField(
                controller: draft.optionControllers[i],
                textCapitalization: TextCapitalization.sentences,
                maxLength: 40,
                inputFormatters: [LengthLimitingTextInputFormatter(40)],
                decoration: buildInputDecoration(
                  hint: i < 2
                      ? 'Choice ${i + 1} (required)'
                      : 'Choice ${i + 1} (optional)',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
