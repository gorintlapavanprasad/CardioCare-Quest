// Turns a user-made story game into a playable Twine/SugarCube page.
//
// The catalog games are authored in Twine and compiled by Tweego into
// self-contained HTML. We can't run Tweego on the phone, but we don't need to:
// the compiled page just embeds each passage as an HTML-escaped
// <tw-passagedata> element inside <tw-storydata>, and the inlined SugarCube
// engine parses that at load. So here we generate those <tw-passagedata>
// elements ourselves from the scenes the patient built, then drop them into the
// bundled engine shell (assets/game/custom_game_template.html) at the
// <!--CCQ_STORYDATA_PASSAGES--> marker. The result is loaded as an HTML string
// by TwineQuestionnaireHost, which injects the CCQ bridge so the story reaches
// the full hooks API (submitResponse, logQuestCompletion, goHome, telemetry).

import 'custom_game.dart';

const String _passagesMarker = '<!--CCQ_STORYDATA_PASSAGES-->';
const String _nameMarker = '%%CCQ_NAME%%';
const String _startNodeMarker = '%%CCQ_STARTNODE%%';

// Builds the full HTML page for [game] by filling in [template] (the contents
// of assets/game/custom_game_template.html).
String buildStoryHtml(CustomGame game, {required String template}) {
  final title = _sanitize(game.title.isEmpty ? 'My Story' : game.title);
  final scenes = game.scenes;

  // pid layout: Welcome = 1, scenes = 2..(1+n), Submit, then Done.
  const welcomePid = 1;
  final submitPid = 2 + scenes.length;
  final donePid = 3 + scenes.length;

  final passages = <String>[
    _welcomePassage(welcomePid, title, _sanitize(game.description)),
  ];

  for (var i = 0; i < scenes.length; i++) {
    passages.add(_scenePassage(
      pid: 2 + i,
      title: title,
      sceneIndex: i,
      scene: scenes[i],
      sceneCount: scenes.length,
    ));
  }

  passages.add(_submitPassage(submitPid, title, game));
  passages.add(_donePassage(donePid, title));

  return template
      .replaceFirst(_nameMarker, _escapeAttr(title))
      .replaceFirst(_startNodeMarker, '$welcomePid')
      .replaceFirst(_passagesMarker, passages.join());
}

// ---- passage builders (raw SugarCube source, escaped by _passage) ----

String _welcomePassage(int pid, String title, String description) {
  final lead = description.isEmpty
      ? 'Tap start when you are ready.'
      : description;
  final body = '''
<div class="phone">
  <div class="header"><span>$title</span></div>
  <h1>$title</h1>
  <p class="lead">$lead</p>
  <div class="primary-cta">
    <<button "Start">>
      <<set \$answers to {}>>
      <<goto "Scene 1">>
    <</button>>
  </div>
</div>''';
  return _passage(pid: pid, name: 'Welcome', body: body);
}

// The JS a choice button runs (besides recording the answer) to fire the
// matching daily-log hook. Returns '' when the step logs nothing. Exercise and
// meal fire only on the affirmative answer; medication fires on both (taken or
// not). Each call is guarded so it no-ops if an older bridge lacks the function.
String _sceneHookJs(String logKind, String logLabel, {required bool affirmative}) {
  switch (logKind) {
    case 'exercise':
      if (!affirmative) return '';
      return ' if(window.CCQ&&window.CCQ.logExercise){CCQ.logExercise("$logLabel",10);}';
    case 'meal':
      if (!affirmative) return '';
      return ' if(window.CCQ&&window.CCQ.logMeal){CCQ.logMeal("$logLabel",4);}';
    case 'medication':
      final taken = affirmative ? 'true' : 'false';
      return ' if(window.CCQ&&window.CCQ.logMedication){CCQ.logMedication($taken);}';
    default:
      return '';
  }
}

// How many taps / items a mini-game step needs before it counts as done.
const int _walkGoal = 8;
const int _plateGoal = 3;

// Where a single-path step (bp / walk / plate / breathe / pill) goes when the
// player finishes it: the next scene, or the Submit step if it was the last.
String _advanceTarget(int sceneIndex, int sceneCount) =>
    (sceneIndex + 1 < sceneCount) ? 'Scene ${sceneIndex + 2}' : 'Submit';

String _scenePassage({
  required int pid,
  required String title,
  required int sceneIndex,
  required StoryScene scene,
  required int sceneCount,
}) {
  // Some steps are little interactive mini-games rather than yes/no questions.
  // Each renders its own passage and logs the matching health hook.
  switch (scene.kind) {
    case 'bp':
      return _bpScenePassage(
        pid: pid,
        title: title,
        sceneIndex: sceneIndex,
        scene: scene,
        sceneCount: sceneCount,
      );
    case 'walk':
      return _walkScenePassage(
        pid: pid,
        title: title,
        sceneIndex: sceneIndex,
        scene: scene,
        sceneCount: sceneCount,
      );
    case 'plate':
      return _plateScenePassage(
        pid: pid,
        title: title,
        sceneIndex: sceneIndex,
        scene: scene,
        sceneCount: sceneCount,
      );
    case 'breathe':
      return _breatheScenePassage(
        pid: pid,
        title: title,
        sceneIndex: sceneIndex,
        scene: scene,
        sceneCount: sceneCount,
      );
    case 'pill':
      return _pillScenePassage(
        pid: pid,
        title: title,
        sceneIndex: sceneIndex,
        scene: scene,
        sceneCount: sceneCount,
      );
  }

  final sceneNo = sceneIndex + 1;
  final prompt = _sanitize(scene.prompt.isEmpty ? 'How did it go?' : scene.prompt);
  final logLabel = _sanitize(scene.logLabel.isEmpty ? scene.prompt : scene.logLabel);

  final buttons = StringBuffer();
  for (var i = 0; i < scene.options.length; i++) {
    final option = scene.options[i];
    final label = _sanitize(option.label);
    if (label.isEmpty) continue;
    // Clamp out-of-range or self/backward targets to "finish".
    final target = (option.nextScene >= 0 &&
            option.nextScene < sceneCount &&
            option.nextScene != sceneIndex)
        ? 'Scene ${option.nextScene + 1}'
        : 'Submit';
    // The first option is the affirmative one ("Yes"); it fires the matching
    // health hook. Medication logs on both answers (taken vs. not).
    final hook = _sceneHookJs(scene.logKind, logLabel, affirmative: i == 0);
    buttons.writeln('''
      <<button "$label">>
        <<run State.variables.answers["scene$sceneNo"] = "$label";$hook>>
        <<goto "$target">>
      <</button>>''');
  }

  final body = '''
<div class="phone">
  <div class="header"><span>$title</span></div>
  <div class="question">
    <div class="question-text">$prompt</div>
    <div class="options">
$buttons    </div>
  </div>
</div>''';
  return _passage(pid: pid, name: 'Scene $sceneNo', body: body);
}

// A blood-pressure entry step. Two number boxes and a Save button that hands the
// reading to CCQ.logBP (the host writes the reading, snapshots vitals, and bumps
// the measurement counters). A Skip button lets the player move on without one.
String _bpScenePassage({
  required int pid,
  required String title,
  required int sceneIndex,
  required StoryScene scene,
  required int sceneCount,
}) {
  final sceneNo = sceneIndex + 1;
  final prompt =
      _sanitize(scene.prompt.isEmpty ? 'Enter your blood pressure' : scene.prompt);
  // Both buttons go to the next step (or Submit if this is the last step).
  final target = (sceneIndex + 1 < sceneCount) ? 'Scene ${sceneNo + 1}' : 'Submit';

  final body = '''
<div class="phone">
  <div class="header"><span>$title</span></div>
  <div class="question">
    <div class="question-text">$prompt</div>
    <div class="options">
      <p class="bp-label">Top number</p>
      <<textbox "_sys" "">>
      <p class="bp-label">Bottom number</p>
      <<textbox "_dia" "">>
      <<button "Save reading">>
        <<run
          try {
            var s = parseInt(String(State.temporary.sys || ""), 10);
            var d = parseInt(String(State.temporary.dia || ""), 10);
            if (window.CCQ && window.CCQ.logBP && s > 0 && d > 0) {
              CCQ.logBP(s, d);
              State.variables.answers["scene$sceneNo"] = s + "/" + d;
            }
          } catch (e) {}
        >>
        <<goto "$target">>
      <</button>>
      <<button "Skip">>
        <<goto "$target">>
      <</button>>
    </div>
  </div>
</div>''';
  return _passage(pid: pid, name: 'Scene $sceneNo', body: body);
}

// A tap-to-walk mini-game (dog walk). Each tap of the big button advances a
// progress bar; when it fills, CCQ.logExercise records the walk and the story
// moves on. jQuery ($) drives the bar and counter; $mini holds the tap count.
String _walkScenePassage({
  required int pid,
  required String title,
  required int sceneIndex,
  required StoryScene scene,
  required int sceneCount,
}) {
  final sceneNo = sceneIndex + 1;
  final prompt =
      _sanitize(scene.prompt.isEmpty ? 'Walk the dog!' : scene.prompt);
  final label = _sanitize(scene.logLabel.isEmpty ? 'Walk' : scene.logLabel);
  final target = _advanceTarget(sceneIndex, sceneCount);
  final pct = (100 / _walkGoal).toStringAsFixed(2);

  final body = '''
<div class="phone">
  <div class="header"><span>$title</span></div>
  <div class="question">
    <div class="question-text">$prompt</div>
    <<set \$mini to 0>>
    <div class="mini">
      <div class="mini-emoji">🐕</div>
      <div class="progress-track"><div class="progress-fill" id="mini-fill"></div></div>
      <div class="count-badge" id="mini-count">0 / $_walkGoal steps</div>
      <div class="tap-big">
        <<button "Walk the dog 🐾">>
          <<set \$mini to \$mini + 1>>
          <<run
            try {
              \$("#mini-fill").css("width", Math.min(100, \$mini * $pct) + "%");
              \$("#mini-count").text(\$mini + " / $_walkGoal steps");
            } catch (e) {}
          >>
          <<if \$mini gte $_walkGoal>>
            <<run
              try {
                if (window.CCQ && window.CCQ.logExercise) { CCQ.logExercise("$label", 10); }
                State.variables.answers["scene$sceneNo"] = "walked";
              } catch (e) {}
            >>
            <<goto "$target">>
          <</if>>
        <</button>>
      </div>
    </div>
  </div>
</div>''';
  return _passage(pid: pid, name: 'Scene $sceneNo', body: body);
}

// A build-a-healthy-plate mini-game. Tapping food buttons fills the plate; once
// enough foods are on it, CCQ.logMeal records the meal and the story moves on.
String _plateScenePassage({
  required int pid,
  required String title,
  required int sceneIndex,
  required StoryScene scene,
  required int sceneCount,
}) {
  final sceneNo = sceneIndex + 1;
  final prompt = _sanitize(
      scene.prompt.isEmpty ? 'Build a healthy plate' : scene.prompt);
  final label = _sanitize(scene.logLabel.isEmpty ? 'Healthy plate' : scene.logLabel);
  final target = _advanceTarget(sceneIndex, sceneCount);

  const foods = ['🥦', '🍎', '🥕', '🐟', '🥬', '🍅'];
  final foodButtons = StringBuffer();
  for (final food in foods) {
    foodButtons.writeln('''
        <<button "$food">>
          <<set \$mini to \$mini + 1>>
          <<run
            try {
              \$("#mini-count").text(Math.min(\$mini, $_plateGoal) + " / $_plateGoal foods");
            } catch (e) {}
          >>
          <<if \$mini gte $_plateGoal>>
            <<run
              try {
                if (window.CCQ && window.CCQ.logMeal) { CCQ.logMeal("$label", $_plateGoal); }
                State.variables.answers["scene$sceneNo"] = "ate healthy";
              } catch (e) {}
            >>
            <<goto "$target">>
          <</if>>
        <</button>>''');
  }

  final body = '''
<div class="phone">
  <div class="header"><span>$title</span></div>
  <div class="question">
    <div class="question-text">$prompt</div>
    <<set \$mini to 0>>
    <div class="mini">
      <div class="mini-emoji">🍽️</div>
      <div class="count-badge" id="mini-count">0 / $_plateGoal foods</div>
      <div class="food-row">
$foodButtons      </div>
    </div>
  </div>
</div>''';
  return _passage(pid: pid, name: 'Scene $sceneNo', body: body);
}

// A paced-breathing calm break. A CSS circle grows and shrinks; the player taps
// Done when they feel ready. Logs nothing (just records the answer) but gives a
// real interactive moment. A Skip button is not needed as Done always advances.
String _breatheScenePassage({
  required int pid,
  required String title,
  required int sceneIndex,
  required StoryScene scene,
  required int sceneCount,
}) {
  final sceneNo = sceneIndex + 1;
  final prompt = _sanitize(scene.prompt.isEmpty
      ? 'Breathe in as it grows, out as it shrinks'
      : scene.prompt);
  final target = _advanceTarget(sceneIndex, sceneCount);

  final body = '''
<div class="phone">
  <div class="header"><span>$title</span></div>
  <div class="question">
    <div class="question-text">$prompt</div>
    <div class="mini">
      <div class="breathe-circle"></div>
      <div class="count-badge">In… and out…</div>
      <div class="tap-big">
        <<button "I feel calmer">>
          <<run
            try { State.variables.answers["scene$sceneNo"] = "breathed"; } catch (e) {}
          >>
          <<goto "$target">>
        <</button>>
      </div>
    </div>
  </div>
</div>''';
  return _passage(pid: pid, name: 'Scene $sceneNo', body: body);
}

// A take-your-pill mini-game (like Pill Path). Tapping the pill logs the dose
// through CCQ.logMedication(true); "Not now" logs it as not taken. Either way
// the story moves on.
String _pillScenePassage({
  required int pid,
  required String title,
  required int sceneIndex,
  required StoryScene scene,
  required int sceneCount,
}) {
  final sceneNo = sceneIndex + 1;
  final prompt =
      _sanitize(scene.prompt.isEmpty ? 'Time for your medicine' : scene.prompt);
  final target = _advanceTarget(sceneIndex, sceneCount);

  final body = '''
<div class="phone">
  <div class="header"><span>$title</span></div>
  <div class="question">
    <div class="question-text">$prompt</div>
    <div class="mini">
      <div class="mini-emoji">💊</div>
      <div class="tap-big">
        <<button "Take my pill">>
          <<run
            try {
              if (window.CCQ && window.CCQ.logMedication) { CCQ.logMedication(true); }
              State.variables.answers["scene$sceneNo"] = "taken";
            } catch (e) {}
          >>
          <<goto "$target">>
        <</button>>
      </div>
      <div class="options">
        <<button "Not now">>
          <<run
            try {
              if (window.CCQ && window.CCQ.logMedication) { CCQ.logMedication(false); }
              State.variables.answers["scene$sceneNo"] = "skipped";
            } catch (e) {}
          >>
          <<goto "$target">>
        <</button>>
      </div>
    </div>
  </div>
</div>''';
  return _passage(pid: pid, name: 'Scene $sceneNo', body: body);
}

String _submitPassage(int pid, String title, CustomGame game) {
  // surveyId matches the native quiz path so all of a game's responses group
  // under the same survey document.
  final surveyId = 'custom_${game.id}';
  final body = '''
<div class="phone center-text">
  <div class="header"><span>$title</span></div>
  <h1>Saving your answers</h1>
  <p class="lead">Just a moment…</p>
  <div class="spinner" aria-label="Saving"></div>
</div>

<<run
  try {
    if (window.CCQ && window.CCQ.submitResponse) {
      CCQ.submitResponse(State.variables.answers, {
        surveyId: "$surveyId"
      });
    }
  } catch (e) {}
>>
<<run
  try {
    if (window.CCQ && window.CCQ.saveState) {
      CCQ.saveState(JSON.stringify(State.variables.answers));
    }
  } catch (e) {}
>>
<<run
  try {
    if (window.CCQ && window.CCQ.logQuestCompletion) {
      /* Log-only: submitResponse already recorded the completion tick, so
         this call keeps the gameLogs entry without double-counting
         (countAsCompletion false). */
      CCQ.logQuestCompletion("$surveyId", {
        countAsCompletion: false,
        data: State.variables.answers
      });
    }
  } catch (e) {}
>>
<<run
  try {
    /* Whole-play score: count the affirmative ("Yes") answers so it records
       the trivia_completed event. */
    var ans = State.variables.answers || {};
    var total = 0, score = 0;
    for (var k in ans) {
      total++;
      if (String(ans[k]).indexOf("Yes") === 0) score++;
    }
    if (window.CCQ && window.CCQ.logTrivia) {
      CCQ.logTrivia(score, total);
    }
  } catch (e) {}
>>

<<timed 700ms>>
  <<goto "Done">>
<</timed>>''';
  return _passage(pid: pid, name: 'Submit', body: body);
}

String _donePassage(int pid, String title) {
  final body = '''
<div class="phone center-text">
  <div class="header"><span>$title</span></div>
  <h1>Thank you</h1>
  <p class="lead">Nice work. Your answers have been saved.</p>
  <div class="primary-cta">
    <<button "Back home">>
      <<run if (window.CCQ && typeof window.CCQ.goHome === "function") { window.CCQ.goHome(); }>>
    <</button>>
  </div>
</div>''';
  return _passage(pid: pid, name: 'Done', body: body);
}

// ---- helpers ----

// Wraps a raw passage body in a <tw-passagedata> element, HTML-escaping the
// body exactly as Tweego does (the engine un-escapes before parsing SugarCube).
String _passage({required int pid, required String name, required String body}) {
  return '<tw-passagedata pid="$pid" name="${_escapeAttr(name)}" '
      'tags="nobr" position="100,100" size="100,100">'
      '${_escapeBody(body)}</tw-passagedata>';
}

// Escape a passage body for storage inside <tw-passagedata>. Order matters: & first.
String _escapeBody(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

// Escape an attribute value (passage/story name).
String _escapeAttr(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

// Removes characters that would break SugarCube parsing once the body is
// un-escaped by the engine (macro delimiters `<<`/`>>`, quotes, the `$`
// variable sigil, braces, backslashes, backticks). Patients type short plain
// answers, so dropping these is safe and keeps generated macros well-formed.
String _sanitize(String s) {
  final cleaned = s.replaceAll(RegExp(r'''[<>"$`{}\\]'''), '');
  return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
}
