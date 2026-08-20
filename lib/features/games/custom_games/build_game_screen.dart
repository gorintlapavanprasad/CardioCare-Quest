// BuildGameScreen - the simple "build your own game" screen.
// Tap the healthy things you want in your game, give it a name, tap CREATE.
// Behind the scenes each tapped activity becomes one step of a real Twine
// story, so the finished game plays in the WebView with the full hooks.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/hooks/hooks.dart';
import '../../../core/providers/user_data_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../game_stories.dart';
import 'custom_game.dart';
import 'custom_games_repository.dart';

// One part a patient can add to their game. Each becomes a story step. `kind`
// decides how the step plays:
//   walk    - tap-to-walk mini-game, logs exercise
//   plate   - tap-to-collect-foods mini-game, logs a meal
//   pill    - tap-the-pill mini-game, logs medication
//   bp      - blood-pressure entry, logs a reading
//   breathe - paced-breathing calm break (no log)
//   choice  - a simple yes/no question (used where a mini-game doesn't fit)
class _Activity {
  final String emoji;
  final String label; // shown on the card
  final String question; // the story step's prompt
  final GameCategory category;
  final String kind;

  const _Activity(
    this.emoji,
    this.label,
    this.question,
    this.category, {
    this.kind = 'choice',
  });
}

// The menu of playable parts to assemble a game from - "build your meal" style,
// grouped by health area. Order here is the order they appear under each heading.
const List<_Activity> _activities = [
  // Exercise - tap-to-walk mini-games.
  _Activity('🐕', 'Dog walk', 'Walk the dog!',
      GameCategory.exercise, kind: 'walk'),
  _Activity('🚶', 'Go for a walk', 'Take a walk!',
      GameCategory.exercise, kind: 'walk'),
  // Diet - build-a-plate mini-games.
  _Activity('🍽️', 'Healthy plate', 'Build a healthy plate',
      GameCategory.diet, kind: 'plate'),
  _Activity('🥗', 'Eat your veggies', 'Fill your plate with good food',
      GameCategory.diet, kind: 'plate'),
  // Medication - tap-the-pill mini-game.
  _Activity('💊', 'Take medicine', 'Time for your medicine',
      GameCategory.medication, kind: 'pill'),
  // Measurements - blood-pressure entry.
  _Activity('🩺', 'Blood pressure', 'Enter your blood pressure',
      GameCategory.measurements, kind: 'bp'),
  // Wellbeing - a calm break plus a couple of simple check-ins.
  _Activity('🧘', 'Calm breathing', 'Breathe in as it grows, out as it shrinks',
      GameCategory.education, kind: 'breathe'),
  _Activity('😊', 'Check your mood', 'Are you feeling good today?',
      GameCategory.education),
  _Activity('☎️', 'Call someone', 'Did you talk to a friend or family?',
      GameCategory.education),
];

// Heading emoji for each of the five health factors. The text is the factor's
// own name (category.label) so the sections read as the five standard areas.
String _categoryEmoji(GameCategory c) {
  switch (c) {
    case GameCategory.exercise:
      return '🏃';
    case GameCategory.diet:
      return '🥗';
    case GameCategory.medication:
      return '💊';
    case GameCategory.measurements:
      return '🩺';
    case GameCategory.education:
      return '💜';
  }
}

// Which daily-log hook a "Yes" answer for a plain 'choice' step should fire.
// The mini-game kinds (walk, plate, pill, bp) log themselves inside their own
// story passage, so this only maps the leftover wellbeing check-ins.
String _logKindFor(_Activity a) {
  switch (a.category) {
    case GameCategory.exercise:
      return 'exercise';
    case GameCategory.diet:
      return 'meal';
    case GameCategory.medication:
      return 'medication';
    case GameCategory.measurements:
    case GameCategory.education:
      return 'none';
  }
}

// The build-your-own-game screen.
class BuildGameScreen extends StatefulWidget {
  const BuildGameScreen({super.key});

  @override
  State<BuildGameScreen> createState() => _BuildGameScreenState();
}

class _BuildGameScreenState extends State<BuildGameScreen> {
  final _nameController = TextEditingController();

  // Which activities the patient has tapped, kept in tap order so the story
  // steps flow in the order they picked.
  final List<_Activity> _picked = [];

  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // Tap a card to add or remove that activity.
  void _toggle(_Activity activity) {
    setState(() {
      if (_picked.contains(activity)) {
        _picked.remove(activity);
      } else {
        _picked.add(activity);
      }
    });
  }

  // Turns the picked activities into a linear story, saves it, pops back.
  Future<void> _handleCreate() async {
    if (_picked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tap at least one thing to add it to your game.'),
      ));
      return;
    }
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

    // Each picked activity is one story step, in the order they picked. The
    // mini-game parts (walk, plate, pill, bp, breathe) play out and log
    // themselves; the plain check-ins are a simple yes/no that moves on.
    final scenes = <StoryScene>[];
    for (var i = 0; i < _picked.length; i++) {
      final activity = _picked[i];
      final isLast = i == _picked.length - 1;
      final next = isLast ? -1 : i + 1;
      final prompt = '${activity.question} ${activity.emoji}';
      if (activity.kind == 'choice') {
        scenes.add(StoryScene(
          prompt: prompt,
          // A "Yes" answer fires the matching daily-log hook; logLabel is the
          // readable activity saved with it.
          logKind: _logKindFor(activity),
          logLabel: activity.label,
          options: [
            StoryOption(label: 'Yes 👍', nextScene: next),
            StoryOption(label: 'Not yet 🙌', nextScene: next),
          ],
        ));
      } else {
        // Interactive mini-game step. It advances to the next step (or the
        // finish) on its own, so it needs no options. logLabel names the
        // activity the step logs (walk, meal, etc).
        scenes.add(StoryScene(
          kind: activity.kind,
          prompt: prompt,
          logLabel: activity.label,
        ));
      }
    }

    final title = _nameController.text.trim().isEmpty
        ? 'My Health Game'
        : _nameController.text.trim();
    // Use the first activity's area as the game's category.
    final category = _picked.first.category;

    // id is blank here; the save step assigns a real one.
    final draft = CustomGame(
      id: '',
      title: title,
      description: '',
      category: category,
      gameType: CustomGameType.story,
      scenes: scenes,
    );

    try {
      final id = await CustomGamesRepository.instance.create(
        uid: uid,
        draft: draft,
      );
      // Log creation for research - no title, no personal info.
      // ignore: unawaited_futures
      TelemetryHooks.logEvent(
        'custom_game_created',
        parameters: {
          'gameId': id,
          'category': category.name,
          'stepCount': scenes.length,
        },
        userId: uid,
      );

      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Created "$title"'),
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
          'Build Your Own Game',
          style: TextStyle(color: AppColors.title),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.title),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            const _Hint(
              text:
                  'Tap the healthy things you want in your game. Each one becomes a step. Pick as many as you like, then give your game a name.',
            ),
            const SizedBox(height: 24),
            _SectionLabel('Tap to add to your game'),
            const SizedBox(height: 4),
            // One section per health area, only showing areas that have cards.
            for (final category in GameCategory.values)
              if (_activities.any((a) => a.category == category)) ...[
                const SizedBox(height: 16),
                Text(
                  '${_categoryEmoji(category)}  ${category.label}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: _activities
                      .where((a) => a.category == category)
                      .map((activity) {
                    return _ActivityCard(
                      activity: activity,
                      selected: _picked.contains(activity),
                      order: _picked.indexOf(activity) + 1,
                      onTap: () => _toggle(activity),
                    );
                  }).toList(),
                ),
              ],
            const SizedBox(height: 28),
            _SectionLabel('Name your game (optional)'),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              maxLength: 40,
              inputFormatters: [LengthLimitingTextInputFormatter(40)],
              decoration: InputDecoration(
                hintText: 'e.g. My Morning Routine',
                filled: true,
                fillColor: Colors.white,
                counterText: '',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.cardBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      AppColors.primary.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                ),
                onPressed: (_saving || _picked.isEmpty) ? null : _handleCreate,
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _picked.isEmpty
                            ? 'PICK SOMETHING TO START'
                            : 'CREATE GAME (${_picked.length})',
                        style: const TextStyle(
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
    );
  }
}

// A big emoji card for one activity. Turns blue with a number when picked.
class _ActivityCard extends StatelessWidget {
  final _Activity activity;
  final bool selected;
  final int order; // its position in the game, shown when selected
  final VoidCallback onTap;

  const _ActivityCard({
    required this.activity,
    required this.selected,
    required this.order,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppColors.primary : Colors.white;
    final fg = selected ? Colors.white : AppColors.title;
    final border = selected ? AppColors.primary : AppColors.cardBorder;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: 150,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border, width: 2),
          ),
          child: Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    activity.emoji,
                    style: const TextStyle(fontSize: 40),
                  ),
                  if (selected)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$order',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                activity.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Bold heading above each section.
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.title,
        fontSize: 16,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    );
  }
}

// Tip box at the top of the screen.
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
                fontSize: 14,
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
