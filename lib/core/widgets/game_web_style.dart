// Shared stylesheet injected into every Twine game WebView. Makes all games
// full-bleed, correct height on every phone, and uses larger text and emoji.
// Applied from both game hosts on every onPageFinished; the id guard makes it
// safe to inject more than once.

// JavaScript that injects the shared CCQ stylesheet. Skips if already present.
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
