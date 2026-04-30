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
    post(payload);
  }

  window.CCQ = {
    startTracking: startTracking,
    setBuddyName: setBuddyName,
    saveState: saveState,
    finishQuest: finishQuest,
    goHome: goHome,
    telemetry: telemetry,
    submitResponse: submitResponse,
  };
})();
