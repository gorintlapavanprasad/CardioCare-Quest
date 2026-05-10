// CardioCare Quest — Twine ↔ Flutter bridge shim.
//
// Drop this script into the <head> of any Twine HTML game hosted by the
// Flutter `TwineGameHost` widget. It exposes a friendly `window.CCQ` object
// that wraps the raw `window.FlutterBridge.postMessage(...)` JSON protocol
// the host expects.
//
// Usage from Twine / vanilla JS:
//
//   CCQ.startTracking(500);             // begin a movement quest of 500m
//   CCQ.setBuddyName('Rex');            // user named their companion
//   CCQ.saveState(JSON.stringify(state));// persist your local state JSON
//   CCQ.finishQuest();                   // tell host the quest is done
//   CCQ.goHome();                        // exit back to dashboard
//   CCQ.telemetry('scene2_visited', {sceneId:'2'}); // optional analytics
//
// The host also CALLS into your Twine page through a few well-known global
// functions (these are ones YOUR HTML must define if you want them invoked):
//
//   setBuddyName(name)               — restore the saved companion name
//   setWeeklyQuestCount(count)       — update the week-completion stats line
//   updateGameProgress(walked, target) — drive the progress bar mid-walk
//   resumeWalk(walked, target)       — switch to the active-walk page on resume
//   onQuestFinished(pointsGained)    — show your completion scene
//   hydrateState(jsonString)         — restore your local state on launch
//
// All bridge messages are best-effort. If `FlutterBridge` is unavailable
// (e.g. the page is opened in a regular browser for development), CCQ
// silently logs to the console instead of throwing.

(function () {
  'use strict';

  // ───────────────────────────────────────────────────────────────────
  // PARTICIPANT ISOLATION
  //
  // Each Flutter host (`TwineQuestionnaireHost`, `TwineGameHost`) sets
  // the WebView's user agent to `CCQApp/<participantId>` before
  // navigating to the compiled HTML. That tag is the only signal the
  // Twine side gets about WHO is currently logged in — `localStorage`
  // is otherwise shared across all participants on the same device,
  // which would let participant 124 see participant 123's last BP
  // reading, voyage-taken-today gate, points cache, etc.
  //
  // We compare the tagged uid against a stamp stored in localStorage
  // (`ccq_active_pid`) and, on mismatch, clear the per-user keys so
  // the new participant starts clean. Runs synchronously here at the
  // top of the bridge IIFE — that's BEFORE SugarCube StoryInit, which
  // is what reads the cleared keys back.
  try {
    var ua = (typeof navigator !== 'undefined' && navigator.userAgent) || '';
    var match = ua.match(/CCQApp\/([^\s]+)/);
    var currentPid = match ? match[1] : '';
    if (currentPid) {
      var savedPid = window.localStorage.getItem('ccq_active_pid') || '';
      if (savedPid !== currentPid) {
        // Add new keys to this list as games introduce them.
        // 2026-05-10: pill_path_save was missing — participant A's
        // 7-stone path data was leaking to participant B on shared
        // devices. Same vector as quietMinute_history.
        // 2026-05-10 (later): cardiocarequest_survey added — the
        // post-play survey writes a defensive backup of every
        // participant's full payload to that key on the Done
        // passage. Without this entry, participant B would see
        // participant A's last survey responses if A's WebView
        // localStorage were inspected.
        var staleKeys = [
          'quietMinute_history',
          'quietMinute_points',
          'vv_save',
          'pill_path_save',
          'cardiocarequest_survey',
        ];
        for (var i = 0; i < staleKeys.length; i++) {
          try {
            window.localStorage.removeItem(staleKeys[i]);
          } catch (e) { /* ignore */ }
        }
        window.localStorage.setItem('ccq_active_pid', currentPid);
      }
    }
  } catch (e) { /* keep going — isolation is best-effort */ }

  // ───────────────────────────────────────────────────────────────────
  // ATKINSON HYPERLEGIBLE FONT
  //
  // Designed by the Braille Institute for low-vision readability.
  // Bundled locally (TTF in `assets/fonts/Atkinson_Hyperlegible/`,
  // declared in `pubspec.yaml`) so the font loads even when offline
  // and on devices Google Fonts can't reach. We inject `@font-face`
  // declarations once per WebView via a <style> tag in <head>; the
  // path is resolved relative to the compiled HTML's location, which
  // is `assets/game/<game>.html` under flutter_assets, so `../fonts/`
  // walks one directory up to the bundled font folder.
  //
  // Idempotent via the id check so the style block doesn't duplicate
  // across passage re-renders or LAUNCH_GAME sub-host stacking.
  // ───────────────────────────────────────────────────────────────────
  try {
    var injectFontFace = function () {
      if (document.getElementById('ccq-fonts-style')) return;
      var style = document.createElement('style');
      style.id = 'ccq-fonts-style';
      style.textContent =
        "@font-face {" +
        "  font-family: 'Atkinson Hyperlegible';" +
        "  src: url('../fonts/Atkinson_Hyperlegible/AtkinsonHyperlegible-Regular.ttf') format('truetype');" +
        "  font-weight: 400;" +
        "  font-style: normal;" +
        "  font-display: swap;" +
        "}" +
        "@font-face {" +
        "  font-family: 'Atkinson Hyperlegible';" +
        "  src: url('../fonts/Atkinson_Hyperlegible/AtkinsonHyperlegible-Italic.ttf') format('truetype');" +
        "  font-weight: 400;" +
        "  font-style: italic;" +
        "  font-display: swap;" +
        "}" +
        "@font-face {" +
        "  font-family: 'Atkinson Hyperlegible';" +
        "  src: url('../fonts/Atkinson_Hyperlegible/AtkinsonHyperlegible-Bold.ttf') format('truetype');" +
        "  font-weight: 700;" +
        "  font-style: normal;" +
        "  font-display: swap;" +
        "}" +
        "@font-face {" +
        "  font-family: 'Atkinson Hyperlegible';" +
        "  src: url('../fonts/Atkinson_Hyperlegible/AtkinsonHyperlegible-BoldItalic.ttf') format('truetype');" +
        "  font-weight: 700;" +
        "  font-style: italic;" +
        "  font-display: swap;" +
        "}";
      var head = document.head || document.getElementsByTagName('head')[0];
      if (head) head.appendChild(style);
    };
    if (document.head) {
      injectFontFace();
    } else {
      // <head> not yet parsed — defer until it exists.
      document.addEventListener('DOMContentLoaded', injectFontFace);
    }
  } catch (e) { /* font is best-effort — fallback stack handles it */ }

  function post(payload) {
    try {
      if (window.FlutterBridge && typeof window.FlutterBridge.postMessage === 'function') {
        window.FlutterBridge.postMessage(JSON.stringify(payload));
      } else {
        console.log('[CCQ.dev] Bridge unavailable, payload would have been:', payload);
      }
    } catch (e) {
      console.error('[CCQ] Bridge post failed:', e, payload);
    }
  }

  /**
   * Start the GPS-tracked portion of a quest. The host begins listening to
   * the position stream, applies an accuracy filter, and writes periodic
   * batches via the OfflineQueue. Pass the **target distance in meters**.
   */
  function startTracking(distance) {
    post({type: 'START_TRACKING', distance: Number(distance) || 0});
  }

  /**
   * Persist the player's chosen companion name. Mirrors to both `dogName`
   * and `buddyName` on the user profile so it survives across games.
   */
  function setBuddyName(name) {
    if (typeof name !== 'string' || !name.trim()) return;
    post({type: 'SET_DOG_NAME', name: name.trim()});
  }

  /**
   * Save your Twine state as a JSON string. The host writes it to
   * `userData/{uid}/gameStates/{gameId}.gameState` (string field). On the
   * next app launch the host calls `hydrateState(stateJson)` so your page
   * can restore.
   */
  function saveState(stateJson) {
    if (typeof stateJson !== 'string') return;
    post({type: 'SAVE_STATE', state: stateJson});
  }

  /**
   * Tell the host the quest is finished. The host runs the end-game flow:
   * awards points, writes the session completion + CheckData, clears the
   * resume slot, fires the `*_quest_completed` telemetry event, and then
   * calls `onQuestFinished(pointsGained)` back into your page so you can
   * show the completion scene.
   */
  function finishQuest() {
    post({type: 'FINISH_QUEST_DATA'});
  }

  /**
   * Pop back to the dashboard. Use on "Back to home" buttons inside the
   * game.
   */
  function goHome() {
    post({type: 'GO_HOME'});
  }

  /**
   * Fire a custom telemetry event. The host queues it through
   * LoggingService so it lands in `events/*` regardless of online state.
   * `params` should be a plain object with primitive values (no PII).
   *
   * Note: requires `TwineGameHost.onCustomBridgeMessage` to be wired up to
   * route `TELEMETRY` to TelemetryHooks. The host's default handler does
   * NOT process this message — it's reserved for game-specific extensions.
   */
  function telemetry(name, params) {
    if (typeof name !== 'string' || !name) return;
    post({type: 'TELEMETRY', name: name, params: params || {}});
  }

  /**
   * Submit a completed questionnaire / survey response. Used by the
   * non-movement `TwineQuestionnaireHost` (e.g. control game, post-play
   * survey). The host writes one row to
   * `surveys/{surveyId}/responses/{auto}` plus an immutable `events/*` row.
   *
   * @param {Object} answers       Plain object of {questionId: answer}.
   * @param {Object} [opts]        Optional extras.
   * @param {number} [opts.pointsEarned]  Override host's default points.
   * @param {string} [opts.surveyId]      Override host's surveyId (rare).
   * @param {boolean} [opts.countAsCompletion=true]  Set false to credit
   *   `points` without bumping the user-level `surveysCompleted`
   *   counter. Used by games whose individual submits are partial
   *   progress (e.g. Vascular Village's per-quest credits) — the host
   *   then bumps `surveysCompleted` once on session exit instead.
   */
  function submitResponse(answers, opts) {
    if (typeof answers !== 'object' || answers === null) return;
    var payload = {type: 'SUBMIT_RESPONSE', answers: answers};
    if (opts && typeof opts.pointsEarned === 'number') {
      payload.pointsEarned = opts.pointsEarned;
    }
    if (opts && typeof opts.surveyId === 'string' && opts.surveyId) {
      payload.surveyId = opts.surveyId;
    }
    if (opts && opts.countAsCompletion === false) {
      payload.countAsCompletion = false;
    }
    post(payload);
  }

  /**
   * Log a per-quest completion from a hub-and-spoke game (Vascular
   * Village's quests, etc.). The host routes this to GameLogHooks
   * which writes to `userData/{uid}/gameLogs/{auto}` rather than
   * `surveys/...` — keeps research game data out of the surveys
   * collection (surveys are reserved for actual questionnaires).
   *
   * @param {string} questId          Quest identifier within the game.
   * @param {Object} [opts]
   * @param {number} [opts.pointsEarned=0]  Points credited to the user.
   * @param {string} [opts.gameId]          Override host's gameId (rare).
   * @param {Object} [opts.data]            Free-form context (e.g. quality, choices).
   * @param {boolean} [opts.countAsCompletion=true]  Set false to skip
   *   the user-level `surveysCompleted` counter bump — the host fires
   *   it once on session exit instead. Use for partial-progress
   *   submits where one play of the game produces multiple calls.
   */
  function logQuestCompletion(questId, opts) {
    if (typeof questId !== 'string' || !questId) return;
    var payload = {type: 'LOG_QUEST_COMPLETION', questId: questId};
    if (opts && typeof opts.pointsEarned === 'number') {
      payload.pointsEarned = opts.pointsEarned;
    }
    if (opts && typeof opts.gameId === 'string' && opts.gameId) {
      payload.gameId = opts.gameId;
    }
    if (opts && opts.data && typeof opts.data === 'object') {
      payload.data = opts.data;
    }
    if (opts && opts.countAsCompletion === false) {
      payload.countAsCompletion = false;
    }
    post(payload);
  }

  /**
   * Log a blood-pressure reading captured inside the game (e.g. the Quiet
   * Minute calm-state BP form). The host routes this to
   * `DailyLogHooks.logBP` which writes the reading to
   * `userData/{uid}/dailyLogs/{today}/bpReadings/{auto}` and bumps the
   * dashboard's lifetime counters. Mood defaults to 2 (neutral) if not
   * provided — the post-game prompt intentionally skips mood capture.
   *
   * @param {number} systolic   top number, mmHg
   * @param {number} diastolic  bottom number, mmHg
   * @param {number} [mood=2]   0..4, 2 is neutral
   */
  function logBP(systolic, diastolic, mood) {
    var sys = Number(systolic);
    var dia = Number(diastolic);
    if (!isFinite(sys) || !isFinite(dia) || sys <= 0 || dia <= 0) return;
    var m = (typeof mood === 'number' && isFinite(mood)) ? mood : 2;
    post({type: 'LOG_BP', systolic: sys, diastolic: dia, mood: m});
  }

  /**
   * Launch another catalog game on top of the current one as a sub-flow.
   * The host pushes a new route for the target game. When that game's
   * GO_HOME fires, the route pops back to this game with control where it
   * left off. If the sub-game logged BP via CCQ.logBP, the host injects
   * the values into THIS game's SugarCube state so the parent picks up
   * the fresh reading without needing shared localStorage:
   *   SugarCube.State.variables.lastSys
   *   SugarCube.State.variables.lastDia
   *
   * Used by Vascular Village to route the player through Quiet Minute
   * for a calm-state BP reading mid-story.
   *
   * @param {string} gameId  Catalog id of the target game (e.g. 'quiet_minute').
   */
  function launchGame(gameId) {
    if (typeof gameId !== 'string' || !gameId) return;
    post({type: 'LAUNCH_GAME', gameId: gameId});
  }

  /**
   * Pull the latest blood-pressure reading FOR TODAY from Firestore via
   * the host. Fire-and-forget: the host responds asynchronously by
   * calling `runJavaScript` to set:
   *   SugarCube.State.variables.lastSys
   *   SugarCube.State.variables.lastDia
   * and then `Engine.play(currentPassage)` so the rendered passage
   * picks up the fresh reading.
   *
   * Why this exists: webview_flutter on Android does NOT reliably
   * share localStorage across WebViewController instances — Quiet
   * Landscape's `quietMinute_history` write lands in its own WebView's
   * storage and Vascular Village's StoryInit can't see it. Calling
   * this in StoryInit gives Vascular Village a Firestore-backed
   * fallback so the village BP gate works regardless of how the
   * platform's WebView implements storage isolation. The host also
   * seeds `quietMinute_history` in this WebView's localStorage so
   * subsequent renders inside the same launch (e.g. Hub's self-heal
   * script) hit the cache rather than asking Flutter again.
   *
   * No-op when called from a host that doesn't recognise GET_TODAY_BP
   * (older builds) — the host swallows unknown message types.
   */
  function getTodayBP() {
    post({type: 'GET_TODAY_BP'});
  }

  window.CCQ = {
    startTracking: startTracking,
    setBuddyName: setBuddyName,
    saveState: saveState,
    finishQuest: finishQuest,
    goHome: goHome,
    telemetry: telemetry,
    submitResponse: submitResponse,
    logQuestCompletion: logQuestCompletion,
    logBP: logBP,
    launchGame: launchGame,
    getTodayBP: getTodayBP,
  };

  // ───────────────────────────────────────────────────────────────────
  // BURGER MENU — LEFT-SIDE OFF-CANVAS DRAWER
  //
  // Every compiled Twine game has a `<span class="menu-icon">≡</span>`
  // (or similar) in its header. Tapping it slides a drawer in from the
  // LEFT edge (matching netguage's SugarCube UIBar pattern) with four
  // options. Handling the menu HERE — in the shared bridge — instead
  // of per-game means all 7 games inherit the same options, the same
  // animation, and the same UX without duplicating markup across 7
  // .tw files.
  //
  // Options:
  //   • Home              — CCQ.goHome() (back to Flutter dashboard)
  //   • Back              — SugarCube.Engine.backward() (one passage)
  //   • Exit the game     — CCQ.goHome() (same effect as Home; the
  //                         label is for participants who think of
  //                         "leaving" as different from "Home")
  //   • Play from beginning — SugarCube.Engine.restart() (full reset)
  //
  // Implementation notes:
  //   • Click delegation on `document` (capture phase) so the trigger
  //     works regardless of when the .menu-icon was added to the DOM
  //     and survives every passage transition.
  //   • Overlay div is created lazily on first open — by then body
  //     exists, even though this script runs in <head>.
  //   • Drawer slides in via `transform: translateX` so the animation
  //     stays GPU-composited; the dim backdrop fades in via `opacity`.
  //   • Inline styles use Nunito (matches the games) with a system-
  //     font fallback so the menu still reads if Nunito hasn't loaded.
  // ───────────────────────────────────────────────────────────────────

  function injectMenuStyles() {
    if (document.getElementById('ccq-menu-styles')) return;
    var style = document.createElement('style');
    style.id = 'ccq-menu-styles';
    // `.menu-icon` styles use !important so they win over per-game CSS
    // (Dog Quest had `.menu-icon { display: none }` for years, and other
    // games may have similar one-off rules). Color is white-with-shadow
    // so the glyph stays legible on both the dark headers (most games)
    // and any light-themed ones — the dark text-shadow gives it an
    // outline against light backgrounds. font-size:1.4em scales from
    // the parent header's size so small headers (Dog Quest's 0.7rem
    // "EXERCISE" label) still get a tappable icon.
    style.textContent =
      '.menu-icon {' +
      '  cursor: pointer !important;' +
      '  user-select: none; -webkit-user-select: none;' +
      '  display: inline-flex !important;' +
      '  align-items: center;' +
      '  justify-content: center;' +
      '  color: rgba(255, 255, 255, 0.95) !important;' +
      '  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.4);' +
      '  font-size: 24px !important;' +
      '  line-height: 1 !important;' +
      // No `margin-left: auto` — most game headers already use
      // `justify-content: space-between` to spread their children
      // (title / progress / icon). Auto margin here collapses the
      // first two children together (e.g. End Survey screen smushed
      // "End Survey" against "Step 9 of 12" with no gap).
      '  padding: 4px 6px !important;' +
      '  min-width: 28px;' +
      '  min-height: 28px;' +
      '}' +
      // Backdrop: full-screen dim layer beneath the drawer. Click
      // anywhere on it (outside the panel) to dismiss.
      '.ccq-menu-overlay {' +
      '  position: fixed; inset: 0;' +
      '  background: rgba(15, 18, 28, 0.55);' +
      '  z-index: 99999;' +
      '  opacity: 0; pointer-events: none;' +
      '  transition: opacity 0.22s ease-out;' +
      '  font-family: \'Atkinson Hyperlegible\', system-ui, -apple-system, "Segoe UI", sans-serif;' +
      '}' +
      '.ccq-menu-overlay.ccq-open { opacity: 1; pointer-events: auto; }' +
      // Drawer: full-screen overlay that slides in from the left.
      // Width is 100vw so the menu fully covers the game while open
      // — easier reading for older participants and removes any
      // ambiguity about what's tappable. Gradient mirrors the
      // in-game phone-frame palette so the drawer reads as part of
      // the game, not a stray dialog.
      '.ccq-menu-panel {' +
      '  position: fixed; top: 0; left: 0; bottom: 0; right: 0;' +
      '  width: 100vw;' +
      '  background: linear-gradient(180deg, #2a1a4a 0%, #3b528b 55%, #21918c 100%);' +
      '  box-shadow: 4px 0 28px rgba(0, 0, 0, 0.45);' +
      '  display: flex; flex-direction: column;' +
      '  padding: 0 0 12px 0;' +
      '  transform: translateX(-100%);' +
      '  transition: transform 0.25s ease-out;' +
      '  overflow-y: auto;' +
      '  -webkit-overflow-scrolling: touch;' +
      '}' +
      '.ccq-menu-overlay.ccq-open .ccq-menu-panel { transform: translateX(0); }' +
      // Header row: "MENU" label + an X close button. With the
      // panel full-width there's no exposed backdrop to tap-to-
      // dismiss, so we need an explicit close affordance for
      // participants who open the menu and change their mind.
      //
      // Layout: header is a flex row with align-items: center, so
      // both children (the MENU span and the X button) land with
      // their vertical centers on the same y. The header's
      // top-padding uses `env(safe-area-inset-top)` so the row sits
      // BELOW the system status bar on devices that report one,
      // matching the game's own .header behaviour set by the build-
      // time viewport override.
      '.ccq-menu-header {' +
      '  padding-top: max(20px, calc(env(safe-area-inset-top, 0px) + 12px));' +
      '  padding-right: 16px;' +
      '  padding-bottom: 14px;' +
      '  padding-left: 22px;' +
      '  font-size: 12px;' +
      '  letter-spacing: 1.6px;' +
      '  text-transform: uppercase;' +
      '  color: rgba(255, 255, 255, 0.65);' +
      '  font-weight: 800;' +
      '  display: flex;' +
      '  align-items: center;' +
      '  justify-content: space-between;' +
      '  min-height: 56px;' +
      '  box-sizing: border-box;' +
      '}' +
      // 44×44 square button — gives a recommended-minimum tap
      // target without resorting to a negative-margin trick that
      // used to knock the X out of vertical alignment with the
      // MENU label. flex centering on the inner X glyph keeps it
      // pixel-centered inside the square regardless of font
      // metrics. The button itself is then vertically centered
      // by the parent row's align-items: center, so MENU + X
      // share the same y baseline.
      '.ccq-menu-close {' +
      '  background: transparent;' +
      '  border: none;' +
      '  color: rgba(255, 255, 255, 0.92);' +
      '  font-size: 22px;' +
      '  line-height: 1;' +
      '  cursor: pointer;' +
      '  width: 44px;' +
      '  height: 44px;' +
      '  display: flex;' +
      '  align-items: center;' +
      '  justify-content: center;' +
      '  padding: 0;' +
      '  margin: 0;' +
      '  border-radius: 50%;' +
      '  font-family: inherit;' +
      '}' +
      '.ccq-menu-close:hover, .ccq-menu-close:active, .ccq-menu-close:focus {' +
      '  background: rgba(255, 255, 255, 0.10);' +
      '  outline: none;' +
      '}' +
      '.ccq-menu-item {' +
      '  padding: 16px 22px;' +
      '  font-size: 16px;' +
      '  font-weight: 700;' +
      '  color: rgba(255, 255, 255, 0.95);' +
      '  cursor: pointer;' +
      '  display: flex;' +
      '  align-items: center;' +
      '  gap: 14px;' +
      '  border: none;' +
      '  background: transparent;' +
      '  width: 100%;' +
      '  text-align: left;' +
      '  font-family: inherit;' +
      '  border-left: 3px solid transparent;' +
      '  transition: background-color 0.12s ease-out, border-color 0.12s ease-out;' +
      '}' +
      '.ccq-menu-item:hover, .ccq-menu-item:active, .ccq-menu-item:focus {' +
      '  background: rgba(255, 255, 255, 0.10);' +
      '  border-left-color: #fde725;' +
      '  outline: none;' +
      '}' +
      '.ccq-menu-icon-glyph {' +
      '  width: 24px;' +
      '  text-align: center;' +
      '  font-size: 20px;' +
      '  flex: 0 0 24px;' +
      '  opacity: 0.9;' +
      '}';
    document.head.appendChild(style);
  }

  function buildOverlay() {
    var overlay = document.createElement('div');
    overlay.id = 'ccq-menu-overlay';
    overlay.className = 'ccq-menu-overlay';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-label', 'Game menu');
    overlay.innerHTML =
      '<div class="ccq-menu-panel" role="navigation">' +
      '  <div class="ccq-menu-header">' +
      '    <span>Menu</span>' +
      '    <button class="ccq-menu-close" data-action="close" aria-label="Close menu">✕</button>' +
      '  </div>' +
      '  <button class="ccq-menu-item" data-action="dashboard">' +
      '    <span class="ccq-menu-icon-glyph">⌂</span>' +
      '    <span>Home</span>' +
      '  </button>' +
      '  <button class="ccq-menu-item" data-action="back">' +
      '    <span class="ccq-menu-icon-glyph">←</span>' +
      '    <span>Back</span>' +
      '  </button>' +
      '  <button class="ccq-menu-item" data-action="exit">' +
      '    <span class="ccq-menu-icon-glyph">⏻</span>' +
      '    <span>Exit the game</span>' +
      '  </button>' +
      '  <button class="ccq-menu-item" data-action="restart">' +
      '    <span class="ccq-menu-icon-glyph">↻</span>' +
      '    <span>Play from beginning</span>' +
      '  </button>' +
      '</div>';

    overlay.addEventListener('click', function (e) {
      var item = e.target.closest('[data-action]');
      var insidePanel = e.target.closest('.ccq-menu-panel');
      var action = item ? item.getAttribute('data-action') : null;

      // Tapped the dimmed backdrop (outside the panel) — dismiss.
      if (!action && !insidePanel) {
        closeMenu();
        return;
      }
      if (!action) return;
      e.preventDefault();
      e.stopPropagation();

      // Every action closes the drawer first so the slide-out
      // animation runs before the page does its thing — keeps the
      // transition feeling intentional rather than abrupt.
      closeMenu();

      if (action === 'dashboard' || action === 'exit') {
        // Home and Exit both return to the Flutter dashboard. Kept
        // as separate menu entries because participants think of
        // "going home" and "exiting the game" as distinct ideas
        // even though the underlying call is the same.
        try {
          goHome();
        } catch (err) { console.error('[CCQ] goHome failed:', err); }
      } else if (action === 'back') {
        // SugarCube's history.backward — undoes the last passage
        // navigation. No-ops silently if there's nothing to undo
        // (e.g. fresh game launch) since `backward()` returns false.
        try {
          if (window.SugarCube && window.SugarCube.Engine
              && typeof window.SugarCube.Engine.backward === 'function') {
            window.SugarCube.Engine.backward();
          }
        } catch (err) { console.error('[CCQ] back failed:', err); }
      } else if (action === 'restart') {
        try {
          if (window.SugarCube && window.SugarCube.Engine
              && typeof window.SugarCube.Engine.restart === 'function') {
            window.SugarCube.Engine.restart();
          } else {
            // Fallback for the very rare case where SugarCube isn't
            // on the window namespace yet — reload the page so the
            // player gets a clean start either way.
            window.location.reload();
          }
        } catch (err) {
          console.error('[CCQ] restart failed:', err);
          window.location.reload();
        }
      }
    });

    return overlay;
  }

  function openMenu() {
    console.log('[CCQ.menu] openMenu() called');
    injectMenuStyles();
    console.log('[CCQ.menu] styles injected');
    var overlay = document.getElementById('ccq-menu-overlay');
    if (!overlay) {
      console.log('[CCQ.menu] no overlay yet — building');
      overlay = buildOverlay();
      if (!document.body) {
        console.error('[CCQ.menu] document.body missing — cannot append overlay');
        return;
      }
      document.body.appendChild(overlay);
      console.log('[CCQ.menu] overlay appended to body');
    } else {
      console.log('[CCQ.menu] overlay already in DOM, reusing');
    }
    // Force a frame so the transition runs; without it the panel pops
    // in instantly because the element was just inserted.
    requestAnimationFrame(function () {
      overlay.classList.add('ccq-open');
      console.log('[CCQ.menu] .ccq-open class added — should be visible now');
    });
    try { telemetry('menu_opened', {passage: (window.SugarCube && SugarCube.State && SugarCube.State.passage) || ''}); } catch (e) {}
  }

  function closeMenu() {
    var overlay = document.getElementById('ccq-menu-overlay');
    if (overlay) overlay.classList.remove('ccq-open');
  }

  // Capture-phase delegation. Capture so per-game .menu-icon click
  // handlers (if any are ever added) can't swallow the event before
  // we see it. Also handles `.ccq-home-trigger` — a convention any
  // in-game button can opt into to fire goHome directly without
  // navigating through an intermediate "Central Hub" trampoline
  // passage. Earlier the trampoline pattern caused a "Returning…"
  // screen to occasionally hang when the bridge pop raced the
  // SugarCube re-render; firing goHome from the click instead skips
  // the race entirely.
  // ⚠ DIAGNOSTIC LOGGING — temporarily verbose to debug "burger doesn't
  // open menu" reports. Logs every click on `document` (capture phase),
  // what element was hit, and which selector (if any) it matched.
  // Once the issue is resolved these `console.log` lines should be
  // removed or downgraded.
  console.log('[CCQ.menu] click delegation attached on document (capture)');

  document.addEventListener('click', function (e) {
    // Match both `.menu-icon` (modern, what the bridge auto-injects)
    // AND `.header .menu` (legacy — Quiet Minute and any not-yet-
    // rebuilt compiled HTML still use this older class). Without the
    // legacy match, players who tapped the visible burger on a stale
    // build saw nothing happen because the click selector didn't fit
    // the actual element class.
    var t = e.target;
    var tagInfo = t && t.tagName
        ? (t.tagName + (t.className ? '.' + String(t.className).split(' ').join('.') : ''))
        : '(no target)';
    console.log('[CCQ.menu] click hit:', tagInfo);

    var icon = t.closest('.menu-icon, .header .menu');
    if (icon) {
      console.log('[CCQ.menu] matched menu trigger, opening menu',
                  icon.className || icon.tagName);
      e.preventDefault();
      e.stopPropagation();
      openMenu();
      return;
    }
    var homeTrigger = t.closest('.ccq-home-trigger');
    if (homeTrigger) {
      console.log('[CCQ.menu] matched .ccq-home-trigger, firing goHome()');
      e.preventDefault();
      e.stopPropagation();
      try { goHome(); } catch (err) { console.error('[CCQ] home trigger:', err); }
      return;
    }
  }, true);

  // Auto-inject a `<span class="menu-icon">≡</span>` into every
  // `.header` row that doesn't already have one. Three of the seven
  // games (Bingo Bash, Dog Quest, Quiet Minute) bake the icon into
  // their markup; the rest (Salt Sludge, DASH Diet, Daily Check-In,
  // Post-Play Survey, Vascular Village) don't. Doing the injection
  // here gives every game the burger control without 50+ per-passage
  // edits across 5 .tw files. Uses MutationObserver so the icon shows
  // up on each new passage SugarCube renders, not just the first one.
  function ensureMenuIconInHeaders(root) {
    if (!root || !root.querySelectorAll) return;
    var headers = root.querySelectorAll('.header');
    if (headers.length) {
      console.log('[CCQ.menu] ensureMenuIconInHeaders found',
                  headers.length, 'header element(s)');
    }
    for (var i = 0; i < headers.length; i++) {
      var header = headers[i];
      // Skip if a burger already exists — match BOTH the modern
      // `.menu-icon` class AND the legacy `.menu` class (Quiet Minute
      // and other pre-rebuild HTMLs use the older class). For existing
      // ones we ATTACH the handler instead of injecting a new icon —
      // belt-and-suspenders so the menu opens regardless of whether
      // the document-level click delegation actually fires (some
      // WebViews swallow capture-phase events on touch).
      var existing = header.querySelector('.menu-icon, .menu');
      if (existing) {
        attachDirectClickHandler(existing);
        console.log('[CCQ.menu] header already has burger:',
                    existing.className || existing.tagName,
                    '— attached direct handler');
        continue;
      }
      var icon = document.createElement('span');
      icon.className = 'menu-icon';
      icon.textContent = '≡';
      icon.setAttribute('role', 'button');
      icon.setAttribute('aria-label', 'Open menu');
      icon.title = 'Menu';
      // Visual styling lives in the !important `.menu-icon` block in
      // injectMenuStyles() so it overrides any per-game CSS that might
      // hide or recolor the glyph (e.g. Dog Quest's old display:none
      // rule). No inline styles needed here.
      attachDirectClickHandler(icon);
      header.appendChild(icon);
      console.log('[CCQ.menu] injected fresh menu-icon + direct handler');
    }
  }

  // Direct click + touch handler attached straight to the element.
  // Belt-and-suspenders alongside the document-level delegation: some
  // Android WebView builds fire `click` only on the originating element
  // and don't bubble it to `document` capture-phase listeners reliably
  // (especially for span/anchor tags inside flex headers). Attaching
  // the handler directly on the element guarantees the menu opens.
  // Idempotent via a `data-ccq-handler-attached` attribute so we don't
  // stack multiple handlers if the same element is processed twice
  // (e.g. by both initial scan AND a MutationObserver fire).
  function attachDirectClickHandler(el) {
    if (!el || el.dataset.ccqHandlerAttached === 'yes') return;
    el.dataset.ccqHandlerAttached = 'yes';
    var fire = function (e) {
      console.log('[CCQ.menu] direct handler fired on',
                  el.className || el.tagName, e.type);
      try { e.preventDefault(); e.stopPropagation(); } catch (_) {}
      openMenu();
    };
    el.addEventListener('click', fire);
    // Some Android WebView builds + screen-reader gestures only fire
    // `touchend` cleanly. Bind that too as a fallback. Mark with
    // `passive: false` so preventDefault() works (otherwise the WebView
    // can fire a synthetic click that we'd then double-handle, but the
    // `data-ccq-handler-attached` guard protects against that).
    el.addEventListener('touchend', fire, {passive: false});
  }

  function setupHeaderInjection() {
    // Make sure the `.menu-icon` styles are in the DOM BEFORE any icons
    // get injected — otherwise the freshly-added icon paints with
    // default styling (often black on a dark header → invisible) until
    // something else triggers injectMenuStyles. Calling it here is
    // idempotent thanks to the `getElementById('ccq-menu-styles')`
    // short-circuit.
    injectMenuStyles();
    ensureMenuIconInHeaders(document);
    if (typeof MutationObserver !== 'function') return;
    var observer = new MutationObserver(function (mutations) {
      for (var i = 0; i < mutations.length; i++) {
        var added = mutations[i].addedNodes;
        for (var j = 0; j < added.length; j++) {
          var node = added[j];
          if (node.nodeType !== 1) continue;
          // Element itself might be a header, OR contain headers.
          if (node.matches && node.matches('.header')) {
            ensureMenuIconInHeaders(node.parentNode || document);
          }
          ensureMenuIconInHeaders(node);
        }
      }
    });
    observer.observe(document.body, {childList: true, subtree: true});
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', setupHeaderInjection);
  } else {
    setupHeaderInjection();
  }

  // Expose imperative entry points so games can trigger the menu from
  // a custom widget if needed (e.g. a "More" button).
  window.CCQ.openMenu = openMenu;
  window.CCQ.closeMenu = closeMenu;
})();
