/**
 * CardioCare Quest — minimal SugarCube-subset Twee runtime.
 *
 * Lets us play `.twee` source files inside the app's WebView without
 * compiling them through Tweego. Hand-rolled because we only need the
 * subset of macros our authored stories actually use:
 *
 *   <<set $x to expr>>           variable assignment
 *   <<goto "Passage">>            jump to passage
 *   <<run expr>>                  run JS expression for side effects
 *   <<print expr>>                inline print of expression value
 *   <<if cond>>...<<elseif cond>>...<<else>>...<</if>>
 *   <<link "Label">> body <</link>>   clickable; runs body on click
 *   <<linkreplace "Label">> body <</linkreplace>>  one-shot replace
 *   <<for _x range $list>>...<</for>>   simple range iteration
 *   <<textbox "$var" "default">>  text input bound to $var
 *   [[Label|Target]] / [[Target]] inline navigation links
 *   ''bold''                      SugarCube-style bold
 *   $varName                      variable interpolation
 *
 * Anything outside this subset is rendered verbatim. The runtime
 * intentionally does NOT try to be a full SugarCube replacement — its job
 * is to make the three authored stories play through smoothly and call
 * `CCQ.goHome()` at the end. Data collection is out of scope here.
 */
(function () {
  'use strict';

  const State = {
    vars: {},
    passages: {},
    stylesheets: [],
    rootEl: null,
    sourceLoaded: false,
    onCentralHub: null,
    onExit: null,
    exitPassages: [],
    htmlMode: false,
  };

  // Make Math available to author expressions (vascular_village uses it).
  function exprContext() {
    return Object.assign({}, State.vars, { Math: Math });
  }

  function evalExpr(expr) {
    // Replace $foo / _foo with state['foo'].
    const remapped = expr.replace(/[\$_]([A-Za-z_][A-Za-z0-9_]*)/g, "ctx.$1");
    try {
      // eslint-disable-next-line no-new-func
      return new Function("ctx", "return (" + remapped + ");")(exprContext());
    } catch (e) {
      console.error("[twee] expr error:", expr, e);
      return undefined;
    }
  }

  function execAssign(stmt) {
    // Examples:
    //   $score to 0                              ← classic SugarCube
    //   $score to $score + 1
    //   $marked to []
    //   $pressure to Math.max(0, $pressure - 10)
    //   $q1Answer = ""                           ← also accepted
    //   $list = ["a", "b"]
    const m = stmt.match(
      /^\s*\$([A-Za-z_][A-Za-z0-9_]*)\s+(?:to\b|=)\s*(.+)$/
    );
    if (!m) {
      console.warn("[twee] bad <<set>>:", stmt);
      return;
    }
    State.vars[m[1]] = evalExpr(m[2]);
  }

  function execRun(stmt) {
    // Examples:
    //   $marked.push("water"), $score += 1
    // Allow comma-joined expressions.
    const remapped = stmt.replace(/[\$_]([A-Za-z_][A-Za-z0-9_]*)/g, "ctx.$1");
    try {
      // eslint-disable-next-line no-new-func
      const fn = new Function("ctx", remapped + "; return null;");
      fn(exprContext());
      // exprContext returns a SHALLOW copy of vars. To persist changes
      // we re-eval the assignment-like statements: convert
      //   ctx.score += 1     → State.vars.score += 1
      //   ctx.marked.push(x) → State.vars.marked.push(x) (push mutates)
      // For mutations on objects/arrays the shallow copy still holds the
      // same reference, so push() already worked. For primitive
      // re-assignments we need to actually run against State.vars itself.
      const remapped2 = stmt.replace(/[\$_]([A-Za-z_][A-Za-z0-9_]*)/g, "vars.$1");
      // eslint-disable-next-line no-new-func
      new Function("vars", "Math", remapped2)(State.vars, Math);
    } catch (e) {
      console.error("[twee] <<run>> error:", stmt, e);
    }
  }

  function evalCondition(cond) {
    return Boolean(evalExpr(translateOps(cond)));
  }

  // SugarCube allows English-y operators. Translate them.
  function translateOps(expr) {
    return expr
      .replace(/\bis not\b/g, "!==")
      .replace(/\bis\b/g, "===")
      .replace(/\bgte\b/g, ">=")
      .replace(/\blte\b/g, "<=")
      .replace(/\bgt\b/g, ">")
      .replace(/\blt\b/g, "<")
      .replace(/\beq\b/g, "===")
      .replace(/\bneq\b/g, "!==")
      .replace(/\band\b/g, "&&")
      .replace(/\bor\b/g, "||")
      .replace(/\bnot\b/g, "!");
  }

  function interpolate(text) {
    // Replace $var with the persistent value. SugarCube convention is
    // that `$foo` persists in story state and `_foo` is a transient
    // (e.g. `<<for _item range $list>>` iterator). Both live on
    // State.vars here — execAssign / parse() strip the leading sigil
    // before storing, so we look up by bare name.
    function lookup(name) {
      const v = State.vars[name];
      return (v === undefined || v === null) ? "" : String(v);
    }
    let out = text.replace(/\$([A-Za-z_][A-Za-z0-9_]*)/g,
      function (_, name) { return lookup(name); });
    // For `_var`, only replace at word boundaries so we don't munch
    // stuff like `mid_word_text`. The leading char must be start-of-
    // string or non-word; preserve it.
    out = out.replace(/(^|[^A-Za-z0-9_])_([A-Za-z][A-Za-z0-9_]*)/g,
      function (whole, lead, name) { return lead + lookup(name); });
    out = out.replace(/''([^']+)''/g, "<strong>$1</strong>");
    return out;
  }

  // Tokenize a passage body into an array of tokens.
  // Token types: text, macroOpen, macroClose, macroSelf, link
  function tokenize(body) {
    // Strip /* ... */ comments first.
    body = body.replace(/\/\*[\s\S]*?\*\//g, "");

    const tokens = [];
    const re = /<<\s*(\/)?(\w+)([^>]*?)>>|\[\[([^\]]+)\]\]/g;
    let last = 0;
    let m;
    while ((m = re.exec(body)) !== null) {
      if (m.index > last) {
        tokens.push({ type: "text", value: body.slice(last, m.index) });
      }
      if (m[4] !== undefined) {
        // [[Label|Target]], [[Label → Target]], [[Label -> Target]],
        // or [[Target]]. SugarCube traditionally uses '|', but the
        // post-play survey was authored with a Unicode arrow separator.
        const inner = m[4];
        let label, target;
        const sepMatch = inner.match(/\s*(?:\|| ?-> ?| ?→ ?)\s*/);
        if (sepMatch) {
          label = inner.slice(0, sepMatch.index).trim();
          target = inner.slice(sepMatch.index + sepMatch[0].length).trim();
        } else {
          label = target = inner.trim();
        }
        tokens.push({ type: "link", label: label, target: target });
      } else {
        const closing = !!m[1];
        const name = m[2];
        const args = (m[3] || "").trim();
        tokens.push({
          type: closing ? "macroClose" : "macroOpen",
          name: name,
          args: args,
        });
      }
      last = re.lastIndex;
    }
    if (last < body.length) {
      tokens.push({ type: "text", value: body.slice(last) });
    }
    return tokens;
  }

  // Parse tokens into a small AST of nodes the renderer walks.
  // Block-form macros (if/link/linkreplace/for) need their bodies grouped.
  function parse(tokens) {
    let i = 0;

    function parseBlock(stopNames) {
      const nodes = [];
      while (i < tokens.length) {
        const t = tokens[i];
        if (t.type === "macroOpen" && stopNames.indexOf(t.name) >= 0) {
          // Caller will consume this stop token.
          break;
        }
        if (t.type === "macroClose" && stopNames.indexOf(t.name) >= 0) {
          break;
        }
        i++;
        if (t.type === "text") {
          nodes.push({ type: "text", value: t.value });
        } else if (t.type === "link") {
          nodes.push({ type: "link", label: t.label, target: t.target });
        } else if (t.type === "macroOpen") {
          switch (t.name) {
            case "set": {
              nodes.push({ type: "set", expr: t.args });
              break;
            }
            case "run": {
              nodes.push({ type: "run", expr: t.args });
              break;
            }
            case "goto": {
              const m = t.args.match(/^"([^"]+)"$/);
              nodes.push({ type: "goto", target: m ? m[1] : t.args });
              break;
            }
            case "print": {
              nodes.push({ type: "print", expr: t.args });
              break;
            }
            case "textbox": {
              const m = t.args.match(/^"\$([A-Za-z_][A-Za-z0-9_]*)"\s*"([^"]*)"/);
              if (m) nodes.push({ type: "textbox", name: m[1], dflt: m[2] });
              break;
            }
            case "if": {
              const branches = [];
              branches.push({ cond: t.args, body: parseBlock(["elseif", "else", "if"]) });
              while (i < tokens.length) {
                const tk = tokens[i];
                if (tk.type === "macroOpen" && tk.name === "elseif") {
                  i++;
                  branches.push({ cond: tk.args, body: parseBlock(["elseif", "else", "if"]) });
                } else if (tk.type === "macroOpen" && tk.name === "else") {
                  i++;
                  branches.push({ cond: null, body: parseBlock(["if"]) });
                } else if (tk.type === "macroClose" && tk.name === "if") {
                  i++;
                  break;
                } else {
                  // Defensive: bail if structure is malformed.
                  break;
                }
              }
              nodes.push({ type: "if", branches: branches });
              break;
            }
            case "link":
            case "linkreplace": {
              // <<link "Label">> ... <</link>>  (or linkreplace)
              const m = t.args.match(/^"([^"]+)"/);
              const label = m ? m[1] : t.args;
              const body = parseBlock([t.name]);
              // consume close
              if (
                tokens[i] &&
                tokens[i].type === "macroClose" &&
                tokens[i].name === t.name
              ) {
                i++;
              }
              nodes.push({
                type: t.name,
                label: label,
                body: body,
              });
              break;
            }
            case "for": {
              // <<for _x range $list>>...<</for>>
              const m = t.args.match(/^_([A-Za-z_][A-Za-z0-9_]*)\s+range\s+\$([A-Za-z_][A-Za-z0-9_]*)/);
              const body = parseBlock(["for"]);
              if (
                tokens[i] &&
                tokens[i].type === "macroClose" &&
                tokens[i].name === "for"
              ) {
                i++;
              }
              if (m) {
                nodes.push({
                  type: "for",
                  iterVar: m[1],
                  listVar: m[2],
                  body: body,
                });
              }
              break;
            }
            default:
              // Unknown macro — ignore to keep stories playable.
              break;
          }
        }
      }
      return nodes;
    }

    return parseBlock([]);
  }

  // Render an AST into the rootEl.
  function render(nodes, container) {
    nodes.forEach(function (n) {
      switch (n.type) {
        case "text": {
          const interpolated = interpolate(n.value);
          if (State.htmlMode) {
            // Survey-style passages contain raw HTML (`<div>`, `<button>`,
            // inline `<script>`). Render the text verbatim so the
            // author's structure governs layout.
            const wrap = document.createElement("span");
            wrap.innerHTML = interpolated;
            container.appendChild(wrap);
          } else {
            // Prose stories: split blank-line blocks into <p>, single
            // newlines into <br/>.
            const blocks = interpolated.split(/\n{2,}/);
            blocks.forEach(function (block) {
              const trimmed = block.trim();
              if (trimmed.length === 0) return;
              const p = document.createElement("p");
              p.innerHTML = trimmed.replace(/\n/g, "<br/>");
              container.appendChild(p);
            });
          }
          break;
        }
        case "set":
          execAssign(n.expr);
          break;
        case "run":
          execRun(n.expr);
          break;
        case "goto":
          // <<goto>> mid-render: schedule navigation, stop adding content.
          setTimeout(function () { renderPassage(n.target); }, 0);
          throw new GotoSignal(n.target);
        case "print": {
          const v = evalExpr(n.expr);
          container.appendChild(document.createTextNode(v == null ? "" : String(v)));
          break;
        }
        case "textbox": {
          const inp = document.createElement("input");
          inp.type = "text";
          inp.value = State.vars[n.name] != null ? String(State.vars[n.name]) : (n.dflt || "");
          inp.placeholder = n.dflt || "";
          inp.className = "twee-textbox";
          inp.addEventListener("input", function () {
            State.vars[n.name] = inp.value;
          });
          // Persist initial value so <<if $var is "">> works.
          State.vars[n.name] = inp.value;
          container.appendChild(inp);
          break;
        }
        case "if": {
          for (let i = 0; i < n.branches.length; i++) {
            const b = n.branches[i];
            if (b.cond === null || evalCondition(b.cond)) {
              render(b.body, container);
              break;
            }
          }
          break;
        }
        case "link": {
          const a = makeButton(interpolate(n.label));
          a.addEventListener("click", function () {
            // Run the body once on click.
            const tmp = document.createElement("div");
            try { render(n.body, tmp); }
            catch (e) {
              if (e instanceof GotoSignal) return; // navigation already started
              throw e;
            }
            // If the body included a <<goto>>, the GotoSignal would have
            // been thrown above. Otherwise we just navigate to the
            // implied target if the body was nothing but a goto.
          });
          container.appendChild(a);
          break;
        }
        case "linkreplace": {
          const a = makeButton(interpolate(n.label));
          a.addEventListener("click", function () {
            const replacement = document.createElement("span");
            try { render(n.body, replacement); }
            catch (e) { if (!(e instanceof GotoSignal)) throw e; }
            a.replaceWith(replacement);
          });
          container.appendChild(a);
          break;
        }
        case "for": {
          const list = State.vars[n.listVar];
          if (Array.isArray(list)) {
            list.forEach(function (item) {
              State.vars[n.iterVar] = item;
              render(n.body, container);
            });
            delete State.vars[n.iterVar];
          }
          break;
        }
        case "navigate": {
          const a = makeButton(interpolate(n.label));
          a.addEventListener("click", function () { renderPassage(n.target); });
          container.appendChild(a);
          break;
        }
        default:
          break;
      }
      // The [[Label|Target]] inline link case:
      if (n.type === "link" && n.target) {
        // Already handled above? No — that was the macro <<link>>.
        // The [[..]] case is type "navigate"; fall through is fine.
      }
    });
  }

  // [[Label|Target]] tokens get type "link" in tokenize() but their AST
  // form should be a "navigate" node — distinguish them at parse time.
  // (Handled implicitly: in parse() we push them as type:"link" but with a
  // .target field. Override render() to detect that shape.)
  // — Patch the renderer to convert link-with-target into navigate.
  const _origRender = render;
  render = function (nodes, container) {
    const adj = nodes.map(function (n) {
      if (n.type === "link" && typeof n.target === "string" && !n.body) {
        return { type: "navigate", label: n.label, target: n.target };
      }
      return n;
    });
    _origRender(adj, container);
  };

  function makeButton(label) {
    const a = document.createElement("button");
    a.className = "twee-link";
    a.type = "button";
    a.innerHTML = label;
    return a;
  }

  function GotoSignal(t) { this.target = t; }

  function parsePassages(source) {
    const out = {};
    const stylesheets = [];
    const lines = source.split(/\r?\n/);
    let current = null;
    let currentTags = "";
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const m = line.match(/^::\s*([^\[]+?)(?:\s+\[([^\]]*)\])?\s*$/);
      if (m) {
        current = m[1].trim();
        currentTags = (m[2] || "").trim();
        // Stylesheet-tagged passages are collected separately and applied
        // to the document head, NOT rendered as gameplay passages.
        if (/\bstylesheet\b/.test(currentTags)) {
          stylesheets.push({ name: current, body: "" });
          current = "__stylesheet:" + current;
        }
        out[current] = out[current] || "";
        continue;
      }
      if (current) {
        out[current] += line + "\n";
      }
    }
    // Move stylesheet bodies into the dedicated list and drop them from
    // the playable passage map.
    stylesheets.forEach(function (s) {
      s.body = out["__stylesheet:" + s.name] || "";
      delete out["__stylesheet:" + s.name];
    });
    // Drop SugarCube special passages we don't run.
    delete out["StoryTitle"];
    delete out["StoryData"];
    delete out["UserStylesheet"];
    delete out["UserScript"];
    State.stylesheets = stylesheets;
    return out;
  }

  function applyStylesheets() {
    State.stylesheets.forEach(function (s) {
      if (!s.body || !s.body.trim()) return;
      const styleEl = document.createElement("style");
      styleEl.setAttribute("data-twee-source", s.name);
      styleEl.textContent = s.body;
      document.head.appendChild(styleEl);
    });
  }

  function isExitPassage(name) {
    if (!name) return false;
    if (/Central Hub/i.test(name)) return true;
    return State.exitPassages.some(function (p) {
      return p.toLowerCase() === name.toLowerCase();
    });
  }

  function reExecuteScripts(container) {
    // <script> tags inserted via innerHTML are inert by spec. Clone each
    // one into a fresh <script> element so the browser actually runs it.
    const scripts = container.querySelectorAll("script");
    scripts.forEach(function (old) {
      const fresh = document.createElement("script");
      // Preserve src / type if any.
      Array.prototype.slice.call(old.attributes).forEach(function (attr) {
        fresh.setAttribute(attr.name, attr.value);
      });
      fresh.text = old.textContent;
      old.parentNode.replaceChild(fresh, old);
    });
  }

  function renderPassage(name) {
    // Generalized exit detection — covers "Central Hub" (pre-existing
    // convention) plus any names listed in options.exitPassages.
    if (isExitPassage(name)) {
      const cb = State.onExit || State.onCentralHub;
      if (typeof cb === "function") {
        cb(name);
        return;
      }
      // No exit hook installed — render the passage normally if we have
      // it, otherwise warn.
    }
    if (!State.passages[name]) {
      console.warn("[twee] missing passage:", name);
      return;
    }
    State.rootEl.innerHTML = "";
    const wrapper = document.createElement("div");
    wrapper.className = "passage";
    State.rootEl.appendChild(wrapper);
    const tokens = tokenize(State.passages[name]);
    const ast = parse(tokens);
    try { render(ast, wrapper); }
    catch (e) {
      if (!(e instanceof GotoSignal)) {
        console.error("[twee] render error:", e);
      }
    }
    // Inline `<script>` tags inside passages need to be re-instantiated
    // so they actually execute (only relevant in htmlMode).
    if (State.htmlMode) reExecuteScripts(wrapper);
    State.rootEl.scrollTop = 0;
    window.scrollTo(0, 0);
  }

  // SugarCube-compatibility shims for surveys that were authored against
  // the real SugarCube API. They route into our renderPassage / state.
  function installSugarCubeShims() {
    window.Engine = window.Engine || {};
    window.Engine.play = function (target) { renderPassage(target); };
    window.SugarCube = window.SugarCube || {};
    window.SugarCube.State = window.SugarCube.State || {};
    // Aliasing the state object so author code that mutates
    // `SugarCube.State.variables.foo = bar` updates ours in place.
    window.SugarCube.State.variables = State.vars;
  }

  function run(source, startPassage, options) {
    State.vars = {};
    State.passages = parsePassages(source);
    State.rootEl = (options && options.rootEl) || document.getElementById("twee-root");
    State.onCentralHub = (options && options.onCentralHub) || null;
    State.onExit = (options && options.onExit) || null;
    State.exitPassages = (options && options.exitPassages) || [];
    State.htmlMode = !!(options && options.htmlMode);
    if (!State.rootEl) {
      console.error("[twee] no rootEl. Pass options.rootEl or add #twee-root to the page.");
      return;
    }
    applyStylesheets();
    installSugarCubeShims();
    // Re-bind SugarCube.State.variables to the (now-fresh) State.vars.
    window.SugarCube.State.variables = State.vars;
    renderPassage(startPassage);
  }

  function runFromScript(scriptId, startPassage, options) {
    const el = document.getElementById(scriptId);
    if (!el) {
      console.error("[twee] no script element:", scriptId);
      return;
    }
    run(el.textContent, startPassage, options);
  }

  window.CCQTwee = {
    run: run,
    runFromScript: runFromScript,
    state: State, // exposed for debugging
  };
})();
