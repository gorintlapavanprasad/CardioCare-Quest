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
        var staleKeys = [
          'quietMinute_history',
          'quietMinute_points',
          'vv_save',
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
  };

  // ───────────────────────────────────────────────────────────────────
  // BURGER MENU
  //
  // Every compiled Twine game has a `<span class="menu-icon">≡</span>`
  // (or similar) in its header. Handling the menu HERE — in the shared
  // bridge — instead of per-game means all 7 games inherit the same
  // options, the same animation, and the same UX without duplicating
  // markup across 7 .tw files.
  //
  // Options exposed today:
  //   • Go to dashboard — calls CCQ.goHome()
  //   • Restart this game — calls SugarCube.Engine.restart()
  //   • Close menu — dismisses the panel
  //
  // Implementation notes:
  //   • Click delegation on `document` (capture phase) so the trigger
  //     works regardless of when the .menu-icon was added to the DOM
  //     and survives every passage transition.
  //   • Overlay div is created lazily on first open — by then body
  //     exists, even though this script runs in <head>.
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
      '.ccq-menu-overlay {' +
      '  position: fixed; inset: 0;' +
      '  background: rgba(20, 22, 32, 0.55);' +
      '  display: flex; align-items: flex-start; justify-content: flex-end;' +
      '  z-index: 99999;' +
      '  opacity: 0; pointer-events: none;' +
      '  transition: opacity 0.18s ease-out;' +
      '  font-family: \'Nunito\', system-ui, -apple-system, "Segoe UI", sans-serif;' +
      '}' +
      '.ccq-menu-overlay.ccq-open { opacity: 1; pointer-events: auto; }' +
      '.ccq-menu-panel {' +
      '  margin: 14px;' +
      '  background: #ffffff;' +
      '  border-radius: 14px;' +
      '  box-shadow: 0 12px 32px rgba(0, 0, 0, 0.28);' +
      '  min-width: 240px; max-width: 80vw;' +
      '  overflow: hidden;' +
      '  transform: translateY(-8px);' +
      '  transition: transform 0.18s ease-out;' +
      '}' +
      '.ccq-menu-overlay.ccq-open .ccq-menu-panel { transform: translateY(0); }' +
      '.ccq-menu-item {' +
      '  padding: 14px 18px;' +
      '  font-size: 15px;' +
      '  font-weight: 700;' +
      '  color: #2d3140;' +
      '  cursor: pointer;' +
      '  display: flex;' +
      '  align-items: center;' +
      '  gap: 12px;' +
      '  border-bottom: 1px solid rgba(0, 0, 0, 0.06);' +
      '  background: #ffffff;' +
      '  border: none;' +
      '  width: 100%;' +
      '  text-align: left;' +
      '  font-family: inherit;' +
      '}' +
      '.ccq-menu-item:last-child { border-bottom: none; }' +
      '.ccq-menu-item:hover, .ccq-menu-item:active { background: #f4f5f7; }' +
      '.ccq-menu-icon-glyph {' +
      '  width: 22px;' +
      '  text-align: center;' +
      '  font-size: 17px;' +
      '  flex: 0 0 22px;' +
      '}' +
      '.ccq-menu-item-restart { color: #2d7d6d; }' +
      '.ccq-menu-item-close   { color: #6b7280; }';
    document.head.appendChild(style);
  }

  function buildOverlay() {
    var overlay = document.createElement('div');
    overlay.id = 'ccq-menu-overlay';
    overlay.className = 'ccq-menu-overlay';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-label', 'Game menu');
    overlay.innerHTML =
      '<div class="ccq-menu-panel">' +
      '  <button class="ccq-menu-item" data-action="dashboard">' +
      '    <span class="ccq-menu-icon-glyph">⌂</span>' +
      '    <span>Go to dashboard</span>' +
      '  </button>' +
      '  <button class="ccq-menu-item ccq-menu-item-restart" data-action="restart">' +
      '    <span class="ccq-menu-icon-glyph">↻</span>' +
      '    <span>Restart this game</span>' +
      '  </button>' +
      '  <button class="ccq-menu-item ccq-menu-item-close" data-action="close">' +
      '    <span class="ccq-menu-icon-glyph">✕</span>' +
      '    <span>Close menu</span>' +
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

      if (action === 'close') {
        closeMenu();
      } else if (action === 'dashboard') {
        closeMenu();
        try { goHome(); } catch (err) { console.error('[CCQ] goHome failed:', err); }
      } else if (action === 'restart') {
        closeMenu();
        try {
          if (window.SugarCube && window.SugarCube.Engine && typeof window.SugarCube.Engine.restart === 'function') {
            window.SugarCube.Engine.restart();
          } else {
            // Fallback for the very rare case where SugarCube isn't on
            // the window namespace yet — reload the page so the player
            // gets a clean start either way.
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
