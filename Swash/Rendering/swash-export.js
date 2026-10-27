// Typesets an exported document in place: TeX with KaTeX and Mermaid diagrams as inline SVG.
// DocumentExporter loads swash-export.html, then calls swashTypeset() with the rendered HTML.
// Mermaid (5 MB) is loaded only when the document has a diagram.

function swashLoadScript(name) {
  return new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = name;
    script.onload = resolve;
    script.onerror = () => reject(new Error(name + " failed to load"));
    document.head.appendChild(script);
  });
}

function swashImagesLoaded(root, timeout) {
  const pending = Array.from(root.querySelectorAll("img")).filter(img => !img.complete);
  const loads = pending.map(img => new Promise(resolve => { img.onload = resolve; img.onerror = resolve; }));
  return Promise.race([Promise.all(loads), new Promise(resolve => setTimeout(resolve, timeout))]);
}

async function swashTypeset(html, title) {
  const root = document.querySelector(".swash-document");
  document.title = title;
  root.innerHTML = html;
  const failures = [];
  const katexOptions = { throwOnError: false, output: "html", trust: false, strict: "ignore" };

  if (window.katex) {
    for (const span of root.querySelectorAll("span.math-inline")) {
      try { katex.render(span.textContent, span, Object.assign({ displayMode: false }, katexOptions)); }
      catch (error) { failures.push(String(error)); }
    }
    for (const code of root.querySelectorAll("pre > code.language-math")) {
      const block = document.createElement("div");
      block.className = "math-display";
      try {
        katex.render(code.textContent, block, Object.assign({ displayMode: true }, katexOptions));
        code.parentElement.replaceWith(block);
      } catch (error) { failures.push(String(error)); }
    }
  }

  const diagrams = Array.from(root.querySelectorAll("pre > code.language-mermaid"));
  if (diagrams.length > 0) {
    try {
      await swashLoadScript("mermaid.min.js");
      mermaid.initialize({ startOnLoad: false, securityLevel: "strict", theme: "default",
                           fontFamily: "-apple-system, Helvetica Neue, sans-serif" });
      let count = 0;
      for (const code of diagrams) {
        count += 1;
        try {
          const { svg } = await mermaid.render("swash-export-diagram-" + count, code.textContent);
          const figure = document.createElement("div");
          figure.className = "mermaid";
          figure.innerHTML = svg;
          code.parentElement.replaceWith(figure);
        } catch (error) {
          failures.push(String(error));
        }
        // Mermaid leaves its measuring element behind when a diagram fails
        document.querySelectorAll("body > [id^='dswash-export-diagram']").forEach(e => e.remove());
      }
    } catch (error) {
      failures.push(String(error));
    }
  }

  // Remote images
  await swashImagesLoaded(root, 10000);

  const usesKaTeX = root.querySelector(".katex") !== null;
  if (usesKaTeX) {
    // KaTeX fonts load lazily and can miss the first PDF or print pass: load them all now
    await Promise.all(Array.from(document.fonts).map(face => face.load().catch(() => null)));
  }
  await document.fonts.ready;
  return { html: root.innerHTML, usesKaTeX: usesKaTeX, failures: failures };
}
