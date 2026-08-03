// One shared stylesheet injected into EVERY in-app Twine game WebView so all
// games render the same way on any device:
//   * Full-bleed - no floating "phone card" on a cream border, no rounded
//     corners, no fixed 380px width.
//   * Full viewport height via dvh (tracks the visible viewport, so it fits
//     every phone regardless of status/nav-bar insets) with a vh fallback.
//   * Larger text + emoji for readability (the audience skews older).
//
// It is applied on page load from both game hosts (twine_questionnaire_host
// and twine_game_host). Using `!important` plus a single injected <style> in
// <head> means it wins over each game's own CSS and survives SugarCube
// passage swaps, which only replace the passage body and never touch <head>.
//
// The games all come from the same design system, so they share these class
// names (.phone, .hero-emoji, .quiz-emoji, .narrative, .food-emoji, ...);
// targeting them here restyles all games at once from one place.

/// JavaScript that appends the shared CCQ game stylesheet. Idempotent - it
/// no-ops if the style element is already present, so it's safe to run on
/// every `onPageFinished`.
const String kCcqGameStyleInjectionJs = '''
(function () {
  try {
    var id = 'ccq-global-style';
    if (document.getElementById(id)) return;
    var css =
      /* ---- full-bleed layout, every device ---- */
      "html,body{margin:0!important;padding:0!important;}" +
      "#story{max-width:100%!important;margin:0 auto!important;padding:0!important;}" +
      ".phone{border-radius:0!important;box-shadow:none!important;width:100%!important;max-width:100%!important;min-height:100vh!important;min-height:100dvh!important;}" +
      /* ---- larger text ---- */
      ".header{font-size:18px!important;}" +
      ".intro-title{font-size:36px!important;}" +
      ".narrative,.round-status{font-size:20px!important;}" +
      ".quiz-name{font-size:29px!important;}" +
      ".quiz-desc{font-size:17px!important;}" +
      /* ---- larger emoji / icons ---- */
      ".hero-emoji,.quiz-emoji{font-size:108px!important;}" +
      ".celebration-emoji{font-size:110px!important;}" +
      ".food-emoji{font-size:96px!important;}" +
      ".duo-emoji-good,.duo-emoji-bad{font-size:94px!important;}" +
      ".welcome-emoji,.result-emoji,.done-emoji{font-size:86px!important;}" +
      ".action-emoji{font-size:78px!important;}";
    var s = document.createElement('style');
    s.id = id;
    s.appendChild(document.createTextNode(css));
    (document.head || document.documentElement).appendChild(s);
  } catch (e) {}
})();
''';
