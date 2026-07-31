(function () {
  "use strict";

  var TICK = String.fromCharCode(96);
  var LANDING_TITLE = "qBittorrent Material — Native. Modern. Yours.";
  var STORAGE = {
    theme: "qbt-material-theme-v1",
    imported: "qbt-material-imported-docs-v1",
    search: "qbt-material-search-state-v1",
    regexLibrary: "qbt-material-regex-library-v1"
  };
  var CATEGORY_ORDER = [
    "Overview", "Wiki", "Get started", "Interface", "Design",
    "Product", "Engineering", "Reference", "Imported"
  ];
  var FILTER_FIELDS = [
    ["all", "Every field"],
    ["title", "Title"],
    ["path", "Path"],
    ["category", "Category"],
    ["format", "File type"],
    ["content", "Content"]
  ];
  var FILTER_OPERATORS = [
    ["contains", "contains"],
    ["equals", "equals"],
    ["starts", "starts with"],
    ["ends", "ends with"],
    ["regex", "matches regex"],
    ["not-regex", "does not match regex"]
  ];

  function byId(id) { return document.getElementById(id); }
  function all(selector, root) {
    return Array.prototype.slice.call((root || document).querySelectorAll(selector));
  }
  function escapeHtml(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }
  function escapeRegExp(value) {
    return String(value).replace(/[.*+?^$()|[\]\\{}]/g, "\\$&");
  }
  function slugify(value) {
    return String(value || "document").toLowerCase()
      .normalize("NFKD").replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "document";
  }
  function safeJsonParse(value, fallback) {
    if (value == null || value === "") return fallback;
    try {
      var parsed = JSON.parse(value);
      return parsed == null ? fallback : parsed;
    } catch (error) { return fallback; }
  }
  function loadStored(key, fallback) {
    try { return safeJsonParse(localStorage.getItem(key), fallback); }
    catch (error) { return fallback; }
  }
  function saveStored(key, value) {
    try {
      localStorage.setItem(key, JSON.stringify(value));
      return true;
    } catch (error) {
      showSnackbar("Browser storage is full; export your local pages before leaving.");
      return false;
    }
  }
  function normalizeFilter(rule) {
    if (!rule || typeof rule !== "object") return null;
    var allowedFields = FILTER_FIELDS.map(function (option) { return option[0]; });
    var allowedOperators = FILTER_OPERATORS.map(function (option) { return option[0]; });
    var field = allowedFields.indexOf(rule.field) >= 0 ? rule.field : "all";
    var operator = allowedOperators.indexOf(rule.operator) >= 0 ? rule.operator : "contains";
    return {
      field: field,
      operator: operator,
      value: String(rule.value == null ? "" : rule.value).slice(0, 1000),
      negate: Boolean(rule.negate)
    };
  }
  function normalizeFilters(filters) {
    return Array.isArray(filters) ? filters.map(normalizeFilter).filter(Boolean).slice(0, 40) : [];
  }
  function normalizeStoredImport(doc, index) {
    if (!doc || typeof doc !== "object") return null;
    var title = String(doc.title || "Imported document").slice(0, 180);
    var path = String(doc.path || ("local/" + slugify(title) + ".md"))
      .replace(/\\/g, "/").slice(0, 1000);
    return {
      slug: slugify(doc.slug || ("local-" + title + "-" + index)),
      title: title,
      path: path,
      category: String(doc.category || "Imported").slice(0, 180),
      format: doc.format === "json" ? "json" : "markdown",
      content: String(doc.content == null ? "" : doc.content).slice(0, 1000000),
      importedAt: typeof doc.importedAt === "string" ? doc.importedAt : null
    };
  }
  function decodeRoutePart(value) {
    try { return decodeURIComponent(value); }
    catch (error) { return value; }
  }
  function debounce(fn, delay) {
    var timer = 0;
    return function () {
      var args = arguments;
      clearTimeout(timer);
      timer = setTimeout(function () { fn.apply(null, args); }, delay);
    };
  }
  function showDialog(dialog) {
    if (!dialog) return;
    if (typeof dialog.showModal === "function") dialog.showModal();
    else dialog.setAttribute("open", "");
  }
  function closeDialog(dialog) {
    if (!dialog) return;
    if (typeof dialog.close === "function") dialog.close();
    else dialog.removeAttribute("open");
  }
  function showSnackbar(message) {
    var bar = byId("snackbar");
    var label = byId("snackbar-message");
    if (!bar || !label) return;
    label.textContent = message;
    bar.hidden = false;
    bar.classList.add("is-visible");
    clearTimeout(showSnackbar.timer);
    showSnackbar.timer = setTimeout(function () {
      bar.classList.remove("is-visible");
      setTimeout(function () { bar.hidden = true; }, 220);
    }, 4200);
  }

  var corpus = window.QBT_DOCS && Array.isArray(window.QBT_DOCS.documents)
    ? window.QBT_DOCS.documents : [];
  var imported = loadStored(STORAGE.imported, []);
  imported = Array.isArray(imported)
    ? imported.slice(0, 500).map(normalizeStoredImport).filter(Boolean) : [];
  try { localStorage.setItem(STORAGE.imported, JSON.stringify(imported)); } catch (error) {}
  var savedSearch = loadStored(STORAGE.search, {});
  var state = {
    docs: [],
    docBySlug: new Map(),
    docByPath: new Map(),
    activeSlug: "",
    query: typeof savedSearch.query === "string" ? savedSearch.query : "",
    regex: Boolean(savedSearch.regex),
    caseSensitive: Boolean(savedSearch.caseSensitive),
    wholeWord: Boolean(savedSearch.wholeWord),
    regexFlags: typeof savedSearch.regexFlags === "string" ? savedSearch.regexFlags : "gi",
    filters: normalizeFilters(savedSearch.filters),
    filterMode: savedSearch.filterMode === "any" ? "any" : "all",
    imported: imported,
    lastResultSlugs: []
  };
  var filterDraft = [];
  var searchWorker = null;
  var searchRequestId = 0;
  var previewWorker = null;
  var previewRequestId = 0;
  var focusNextRoute = false;

  function normalizeDocument(doc, index, importedDoc) {
    doc = doc && typeof doc === "object" ? doc : {};
    var path = String(doc.path || ((importedDoc ? "local/" : "docs/") + (doc.title || "Document") + ".md"))
      .replace(/\\/g, "/");
    return {
      slug: slugify(doc.slug || (importedDoc ? "local-" : "") + (doc.title || path || index)),
      title: String(doc.title || path.split("/").pop().replace(/\.[^.]+$/, "") || "Document"),
      path: path,
      category: String(doc.category || (importedDoc ? "Imported" : "Reference")),
      format: String(doc.format || (/\.json$/i.test(path) ? "json" : "markdown")),
      content: String(doc.content == null ? "" : doc.content),
      imported: Boolean(importedDoc),
      importedAt: doc.importedAt || null
    };
  }

  function rebuildCorpus() {
    var result = [];
    var used = new Set();
    corpus.forEach(function (doc, index) {
      var normalized = normalizeDocument(doc, index, false);
      var base = normalized.slug;
      var suffix = 2;
      while (used.has(normalized.slug)) normalized.slug = base + "-" + suffix++;
      used.add(normalized.slug);
      result.push(normalized);
    });
    state.imported.forEach(function (doc, index) {
      var normalized = normalizeDocument(doc, index, true);
      var base = normalized.slug;
      var suffix = 2;
      while (used.has(normalized.slug)) normalized.slug = base + "-" + suffix++;
      used.add(normalized.slug);
      result.push(normalized);
    });
    state.docs = result;
    state.docBySlug = new Map();
    state.docByPath = new Map();
    result.forEach(function (doc) {
      state.docBySlug.set(doc.slug, doc);
      state.docByPath.set(doc.path.toLowerCase(), doc);
      state.docByPath.set(doc.path.split("/").pop().toLowerCase(), doc);
    });
    var count = byId("document-count");
    if (count) count.textContent = result.length + " documents";
  }

  function categoryRank(category) {
    var index = CATEGORY_ORDER.indexOf(category);
    return index < 0 ? CATEGORY_ORDER.length : index;
  }

  function sortedDocuments() {
    return state.docs.slice().sort(function (a, b) {
      return categoryRank(a.category) - categoryRank(b.category)
        || a.category.localeCompare(b.category)
        || a.title.localeCompare(b.title);
    });
  }

  function renderNavigation() {
    var nav = byId("doc-nav");
    if (!nav) return;
    var previousCategory = "";
    var html = "";
    sortedDocuments().forEach(function (doc) {
      if (doc.category !== previousCategory) {
        previousCategory = doc.category;
        html += '<div class="doc-nav-group">' + escapeHtml(previousCategory) + "</div>";
      }
      html += '<button type="button" data-doc-slug="' + escapeHtml(doc.slug) + '"'
        + (doc.slug === state.activeSlug ? ' class="is-active" aria-current="page"' : "")
        + '><svg aria-hidden="true" viewBox="0 0 24 24"><path d="M6 3h9l4 4v14H6zM14 3v5h5"/></svg>'
        + "<span>" + escapeHtml(doc.title) + "</span></button>";
    });
    nav.innerHTML = html || '<span class="toc-empty">No documents are available.</span>';
  }

  function resolveRepoPath(basePath, relativePath) {
    var base = basePath.split("/");
    base.pop();
    String(relativePath).split("/").forEach(function (part) {
      if (!part || part === ".") return;
      if (part === "..") base.pop();
      else base.push(part);
    });
    return base.join("/");
  }

  function safeExternalUrl(url) {
    var value = String(url || "").trim();
    if (/^(?:https?:|mailto:)/i.test(value)) return value;
    return "";
  }

  function resolveImageUrl(url, doc) {
    var value = String(url || "").trim();
    var external = safeExternalUrl(value);
    if (external) return doc.imported ? "" : external;
    if (/^(?:data:image\/(?:png|jpeg|gif|webp|svg\+xml);base64,)/i.test(value)) return value;
    value = value.replace(/^\.\//, "");
    if (doc.path.indexOf("docs/wiki/") === 0 && value.indexOf("images/") === 0) return value;
    var resolved = resolveRepoPath(doc.path, value);
    if (resolved.indexOf("docs/") === 0) return resolved.substring(5);
    if (resolved.indexOf("README") === 0) return value.replace(/^docs\//, "");
    return "https://raw.githubusercontent.com/Ding-Ding-Projects/qbittorrent-material/master/" + resolved;
  }

  function resolveDocumentLink(url, doc) {
    var value = String(url || "").trim();
    if (!value) return { href: "#", external: false };
    if (value.charAt(0) === "#") {
      var localAnchor = value.substring(1);
      return {
        href: "#wiki/" + encodeURIComponent(doc.slug) + "/" + encodeURIComponent(localAnchor),
        slug: doc.slug,
        anchor: localAnchor,
        external: false
      };
    }
    var external = safeExternalUrl(value);
    if (external) return { href: external, external: true };
    var parts = value.split("#");
    var path = parts[0];
    var anchor = parts[1] || "";
    var resolved = resolveRepoPath(doc.path, path).toLowerCase();
    var target = state.docByPath.get(resolved) || state.docByPath.get(path.toLowerCase());
    if (target) {
      return {
        href: "#wiki/" + encodeURIComponent(target.slug) + (anchor ? "/" + encodeURIComponent(anchor) : ""),
        slug: target.slug,
        anchor: anchor,
        external: false
      };
    }
    return {
      href: "https://github.com/Ding-Ding-Projects/qbittorrent-material/blob/master/" + resolveRepoPath(doc.path, path),
      external: true
    };
  }

  function inlineMarkdown(source, doc) {
    var tokens = [];
    function reserve(html) {
      var marker = "\u0001" + tokens.length + "\u0002";
      tokens.push(html);
      return marker;
    }
    var text = String(source || "");
    var codePattern = new RegExp(TICK + "([^" + TICK + "]+)" + TICK, "g");
    text = text.replace(codePattern, function (_, code) {
      return reserve("<code>" + escapeHtml(code) + "</code>");
    });
    text = text.replace(/!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g, function (_, alt, url) {
      var resolvedImage = resolveImageUrl(url, doc);
      if (!resolvedImage) {
        return reserve('<span class="blocked-image" role="note">Remote image blocked: '
          + escapeHtml(alt || url) + "</span>");
      }
      return reserve('<img src="' + escapeHtml(resolvedImage) + '" alt="' + escapeHtml(alt)
        + '" loading="lazy" referrerpolicy="no-referrer">');
    });
    text = text.replace(/\[([^\]]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g, function (_, label, url) {
      var link = resolveDocumentLink(url, doc);
      return reserve('<a href="' + escapeHtml(link.href) + '"'
        + (link.slug ? ' data-doc-slug="' + escapeHtml(link.slug) + '"' : "")
        + (link.anchor ? ' data-doc-anchor="' + escapeHtml(link.anchor) + '"' : "")
        + (link.external ? ' target="_blank" rel="noopener noreferrer"' : "")
        + ">" + escapeHtml(label) + "</a>");
    });
    text = text.replace(/<((?:https?:\/\/)[^ >]+)>/g, function (_, url) {
      return reserve('<a href="' + escapeHtml(url) + '" target="_blank" rel="noopener noreferrer">' + escapeHtml(url) + "</a>");
    });
    text = escapeHtml(text);
    text = text
      .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
      .replace(/__([^_]+)__/g, "<strong>$1</strong>")
      .replace(/~~([^~]+)~~/g, "<del>$1</del>")
      .replace(/(^|[\s(])\*([^*\n]+)\*/g, "$1<em>$2</em>")
      .replace(/(^|[\s(])_([^_\n]+)_/g, "$1<em>$2</em>");
    text = text.replace(/\u0001(\d+)\u0002/g, function (_, index) {
      return tokens[Number(index)] || "";
    });
    return text;
  }

  function headingId(text, used) {
    var base = slugify(text);
    var id = base;
    var suffix = 2;
    while (used.has(id)) id = base + "-" + suffix++;
    used.add(id);
    return id;
  }

  function isTableDivider(line) {
    return /^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|?\s*$/.test(line || "");
  }
  function splitTableRow(line) {
    return String(line).trim().replace(/^\||\|$/g, "").split("|").map(function (cell) {
      return cell.trim();
    });
  }
  function isBlockStart(lines, index) {
    var line = lines[index] || "";
    if (!line.trim()) return true;
    if (/^#{1,6}\s+/.test(line) || /^>\s?/.test(line) || /^\s*([-+*]|\d+\.)\s+/.test(line)) return true;
    if (/^\s*(?:---+|\*\*\*+)\s*$/.test(line)) return true;
    if (line.trim().indexOf(TICK + TICK + TICK) === 0) return true;
    if (index + 1 < lines.length && line.indexOf("|") >= 0 && isTableDivider(lines[index + 1])) return true;
    return false;
  }

  function renderMarkdown(content, doc) {
    var lines = String(content || "").replace(/\r\n?/g, "\n").split("\n");
    var output = [];
    var toc = [];
    var usedIds = new Set();
    var i = 0;
    while (i < lines.length) {
      var line = lines[i];
      if (!line.trim()) { i++; continue; }

      if (line.trim().indexOf(TICK + TICK + TICK) === 0) {
        var language = line.trim().substring(3).trim();
        var code = [];
        i++;
        while (i < lines.length && lines[i].trim().indexOf(TICK + TICK + TICK) !== 0) code.push(lines[i++]);
        if (i < lines.length) i++;
        output.push('<div class="code-block"><button type="button" class="copy-code">Copy</button><pre><code'
          + (language ? ' class="language-' + escapeHtml(language) + '"' : "")
          + ">" + escapeHtml(code.join("\n")) + "</code></pre></div>");
        continue;
      }

      var heading = /^(#{1,6})\s+(.+?)\s*$/.exec(line);
      if (heading) {
        var level = heading[1].length;
        var plain = heading[2].replace(/[*_~]/g, "").replace(new RegExp(TICK, "g"), "");
        var id = doc.slug + "--" + headingId(plain, usedIds);
        if (level <= 3) toc.push({ id: id, level: level, title: plain });
        output.push("<h" + level + ' id="' + escapeHtml(id) + '"><a class="heading-anchor" data-doc-slug="'
          + escapeHtml(doc.slug) + '" data-doc-anchor="' + escapeHtml(id) + '" href="#wiki/'
          + encodeURIComponent(doc.slug) + "/" + encodeURIComponent(id)
          + '" aria-label="Link to this section">#</a>'
          + inlineMarkdown(heading[2], doc) + "</h" + level + ">");
        i++;
        continue;
      }

      if (/^\s*(?:---+|\*\*\*+)\s*$/.test(line)) {
        output.push("<hr>");
        i++;
        continue;
      }

      if (i + 1 < lines.length && line.indexOf("|") >= 0 && isTableDivider(lines[i + 1])) {
        var headers = splitTableRow(line);
        i += 2;
        var rows = [];
        while (i < lines.length && lines[i].trim() && lines[i].indexOf("|") >= 0) rows.push(splitTableRow(lines[i++]));
        var table = "<table><thead><tr>" + headers.map(function (cell) {
          return "<th>" + inlineMarkdown(cell, doc) + "</th>";
        }).join("") + "</tr></thead><tbody>";
        rows.forEach(function (row) {
          table += "<tr>" + headers.map(function (_, column) {
            return "<td>" + inlineMarkdown(row[column] || "", doc) + "</td>";
          }).join("") + "</tr>";
        });
        output.push(table + "</tbody></table>");
        continue;
      }

      if (/^>\s?/.test(line)) {
        var quotes = [];
        while (i < lines.length && /^>\s?/.test(lines[i])) quotes.push(lines[i++].replace(/^>\s?/, ""));
        output.push("<blockquote><p>" + inlineMarkdown(quotes.join(" "), doc) + "</p></blockquote>");
        continue;
      }

      var listMatch = /^\s*([-+*]|\d+\.)\s+(.+)$/.exec(line);
      if (listMatch) {
        var ordered = /\d+\./.test(listMatch[1]);
        var tag = ordered ? "ol" : "ul";
        var items = [];
        while (i < lines.length) {
          var match = /^\s*([-+*]|\d+\.)\s+(.+)$/.exec(lines[i]);
          if (!match || /\d+\./.test(match[1]) !== ordered) break;
          items.push("<li>" + inlineMarkdown(match[2], doc) + "</li>");
          i++;
        }
        output.push("<" + tag + ">" + items.join("") + "</" + tag + ">");
        continue;
      }

      var paragraph = [line.trim()];
      i++;
      while (i < lines.length && lines[i].trim() && !isBlockStart(lines, i)) {
        paragraph.push(lines[i].trim());
        i++;
      }
      output.push("<p>" + inlineMarkdown(paragraph.join(" "), doc) + "</p>");
    }
    return { html: output.join("\n"), toc: toc };
  }

  function renderJson(content, doc) {
    var pretty = content;
    try { pretty = JSON.stringify(JSON.parse(content), null, 2); } catch (error) {}
    var id = doc.slug + "--" + slugify(doc.title);
    return {
      html: '<h1 id="' + id + '">' + escapeHtml(doc.title) + '</h1><div class="code-block"><button type="button" class="copy-code">Copy</button><pre><code class="language-json">'
        + escapeHtml(pretty) + "</code></pre></div>",
      toc: [{ id: id, level: 1, title: doc.title }]
    };
  }

  function renderToc(items) {
    var toc = byId("article-toc");
    if (!toc) return;
    if (!items.length) {
      toc.innerHTML = '<span class="toc-empty">No headings on this page.</span>';
      return;
    }
    toc.innerHTML = items.map(function (item) {
      return '<a href="#wiki/' + encodeURIComponent(state.activeSlug) + "/" + encodeURIComponent(item.id)
        + '" data-doc-slug="' + escapeHtml(state.activeSlug) + '" data-doc-anchor="'
        + escapeHtml(item.id) + '" data-level="' + item.level + '">'
        + escapeHtml(item.title) + "</a>";
    }).join("");
  }

  function activateDocument(slug, anchor, focusArticle) {
    var doc = state.docBySlug.get(slug) || state.docs[0];
    if (!doc) return;
    state.activeSlug = doc.slug;
    var rendered = doc.format === "json" ? renderJson(doc.content, doc) : renderMarkdown(doc.content, doc);
    var index = sortedDocuments().findIndex(function (candidate) { return candidate.slug === doc.slug; });
    var ordered = sortedDocuments();
    var previous = index > 0 ? ordered[index - 1] : null;
    var next = index >= 0 && index < ordered.length - 1 ? ordered[index + 1] : null;
    var article = byId("doc-article");
    var resultsPanel = byId("search-results");
    if (resultsPanel) resultsPanel.hidden = true;
    if (article) {
      article.hidden = false;
      article.innerHTML = '<nav class="breadcrumbs" id="doc-breadcrumbs" aria-label="Breadcrumb">'
        + '<a href="#wiki">Wiki</a><span>/</span><span>' + escapeHtml(doc.category)
        + '</span><span>/</span><span>' + escapeHtml(doc.title) + "</span></nav>"
        + '<div class="doc-article__content">' + rendered.html + "</div>"
        + '<nav class="doc-pagination" aria-label="Adjacent wiki pages">'
        + '<button class="button button--text" id="doc-prev" type="button"' + (previous ? "" : " disabled")
        + '><svg aria-hidden="true" viewBox="0 0 24 24"><path d="m15 18-6-6 6-6"/></svg>'
        + (previous ? escapeHtml(previous.title) : "Previous") + "</button>"
        + '<button class="button button--text" id="doc-next" type="button"' + (next ? "" : " disabled")
        + ">" + (next ? escapeHtml(next.title) : "Next")
        + '<svg aria-hidden="true" viewBox="0 0 24 24"><path d="m9 18 6-6-6-6"/></svg></button></nav>';
      var previousButton = byId("doc-prev");
      var nextButton = byId("doc-next");
      if (previousButton && previous) previousButton.addEventListener("click", function () { navigateToDocument(previous.slug); });
      if (nextButton && next) nextButton.addEventListener("click", function () { navigateToDocument(next.slug); });
      if (focusArticle) article.focus({ preventScroll: true });
    }
    renderNavigation();
    renderToc(rendered.toc);
    if (/^#wiki\//.test(location.hash)) document.title = doc.title + " | qBittorrent Material";
    if (anchor) {
      setTimeout(function () {
        var target = document.getElementById(anchor)
          || document.getElementById(doc.slug + "--" + slugify(anchor))
          || document.getElementById(slugify(anchor));
        if (target) target.scrollIntoView({ behavior: "smooth", block: "start" });
      }, 0);
    }
  }

  function navigateToDocument(slug, anchor) {
    var hash = "#wiki/" + encodeURIComponent(slug) + (anchor ? "/" + encodeURIComponent(anchor) : "");
    focusNextRoute = true;
    if (location.hash === hash) {
      focusNextRoute = false;
      activateDocument(slug, anchor, true);
    } else location.hash = hash;
  }

  function handleRoute() {
    var match = /^#wiki\/([^/]+)(?:\/(.+))?$/.exec(location.hash);
    if (match) {
      searchRequestId++;
      stopSearchWorker();
      var shouldFocus = focusNextRoute;
      focusNextRoute = false;
      activateDocument(decodeRoutePart(match[1]), match[2] ? decodeRoutePart(match[2]) : "", shouldFocus);
      var wiki = byId("wiki");
      if (wiki && location.hash.indexOf("#wiki/") === 0) wiki.scrollIntoView({ block: "start" });
      return true;
    }
    if (location.hash === "#wiki" && (state.query || state.filters.length)) {
      document.title = LANDING_TITLE;
      performSearch(false);
      return true;
    }
    if (!state.activeSlug && state.docs.length) {
      var preferred = state.docBySlug.get("wiki-home") || state.docBySlug.get("overview") || state.docs[0];
      activateDocument(preferred.slug, "", false);
    }
    document.title = LANDING_TITLE;
    return false;
  }

  function compileSearch(query, options) {
    if (!query) return null;
    var source = options.regex ? query : escapeRegExp(query);
    if (source.length > 320) throw new Error("Pattern exceeds 320 characters.");
    if (options.wholeWord) source = "\\b(?:" + source + ")\\b";
    var flags = options.regex ? String(options.flags || "") : "";
    flags = flags.replace(/[^gimsu]/g, "");
    if (flags.indexOf("g") < 0) flags += "g";
    if (options.caseSensitive) flags = flags.replace(/i/g, "");
    else if (flags.indexOf("i") < 0) flags += "i";
    flags = Array.from(new Set(flags.split(""))).join("");
    return new RegExp(source, flags);
  }

  function validateFilterRules(rules) {
    (rules || []).forEach(function (rule, index) {
      if (rule.operator !== "regex" && rule.operator !== "not-regex") return;
      try {
        compileSearch(rule.value, {
          regex: true,
          wholeWord: false,
          caseSensitive: state.caseSensitive,
          flags: state.regexFlags
        });
      } catch (error) {
        throw new Error("Filter " + (index + 1) + ": " + error.message);
      }
    });
  }

  function cloneRegex(regex, global) {
    var flags = regex.flags.replace(/g/g, "");
    if (global) flags += "g";
    return new RegExp(regex.source, flags);
  }
  function regexTest(regex, value) {
    regex.lastIndex = 0;
    return regex.test(String(value || ""));
  }

  function filterValue(doc, field) {
    if (field === "title") return doc.title;
    if (field === "path") return doc.path;
    if (field === "category") return doc.category;
    if (field === "format") return doc.format;
    if (field === "content") return doc.content;
    return [doc.title, doc.path, doc.category, doc.format, doc.content].join("\n");
  }

  function matchesFilter(doc, rule) {
    var value = filterValue(doc, rule.field || "all");
    var needle = String(rule.value || "");
    if (!needle) return true;
    var source = state.caseSensitive ? value : value.toLowerCase();
    var target = state.caseSensitive ? needle : needle.toLowerCase();
    var result = false;
    if (rule.operator === "equals") result = source === target;
    else if (rule.operator === "starts") result = source.indexOf(target) === 0;
    else if (rule.operator === "ends") result = source.lastIndexOf(target) === source.length - target.length;
    else if (rule.operator === "regex" || rule.operator === "not-regex") {
      try {
        var regex = compileSearch(needle, {
          regex: true,
          wholeWord: false,
          caseSensitive: state.caseSensitive,
          flags: state.regexFlags
        });
        result = regexTest(regex, value);
        if (rule.operator === "not-regex") result = !result;
      } catch (error) { result = false; }
    } else result = source.indexOf(target) >= 0;
    return rule.negate ? !result : result;
  }

  function passesFilters(doc) {
    if (!state.filters.length) return true;
    var tests = state.filters.map(function (rule) { return matchesFilter(doc, rule); });
    return state.filterMode === "any" ? tests.some(Boolean) : tests.every(Boolean);
  }

  function firstMatch(content, regex) {
    if (!regex) return { index: 0, text: "" };
    var local = cloneRegex(regex, false);
    var match = local.exec(content);
    return match ? { index: match.index, text: match[0] } : null;
  }

  function makeExcerpt(doc, regex) {
    var clean = doc.content
      .replace(/<[^>]+>/g, " ")
      .replace(/!\[([^\]]*)\]\([^)]+\)/g, "$1")
      .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
      .replace(/^#{1,6}\s+/gm, "")
      .replace(/[`*_>|]/g, " ")
      .replace(/\s+/g, " ")
      .trim();
    var match = firstMatch(clean, regex);
    var index = match ? match.index : 0;
    var start = Math.max(0, index - 90);
    var end = Math.min(clean.length, index + (match ? match.text.length : 0) + 170);
    var before = clean.slice(start, match ? index : end);
    var marked = match ? clean.slice(index, index + match.text.length) : "";
    var after = match ? clean.slice(index + match.text.length, end) : "";
    return (start ? "…" : "") + escapeHtml(before)
      + (match ? '<mark class="search-highlight">' + escapeHtml(marked || "match") + "</mark>" : "")
      + escapeHtml(after) + (end < clean.length ? "…" : "");
  }

  function cleanExcerptText(value) {
    return String(value || "")
      .replace(/<[^>]+>/g, " ")
      .replace(/!\[([^\]]*)\]\([^)]+\)/g, "$1")
      .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
      .replace(/^#{1,6}\s+/gm, "")
      .replace(/[`*_>|]/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  }

  function makeWorkerExcerpt(doc, matchInfo) {
    var index = Math.max(0, Number(matchInfo && matchInfo.contentIndex) || 0);
    var matchText = String(matchInfo && matchInfo.matchText || "");
    var start = Math.max(0, index - 90);
    var end = Math.min(doc.content.length, index + matchText.length + 170);
    var before = cleanExcerptText(doc.content.slice(start, index));
    var marked = cleanExcerptText(matchText);
    var after = cleanExcerptText(doc.content.slice(index + matchText.length, end));
    if (!matchText) {
      before = cleanExcerptText(doc.content.slice(0, 260));
      after = "";
    }
    return (start && matchText ? "…" : "") + escapeHtml(before)
      + (matchText ? '<mark class="search-highlight">' + escapeHtml(marked || matchText) + "</mark>" : "")
      + escapeHtml(after) + (end < doc.content.length ? "…" : "");
  }

  function renderSearchMatches(matches, matcher, workerInfo) {
    var resultsPanel = byId("search-results");
    var article = byId("doc-article");
    var status = byId("search-status");
    var list = byId("search-result-list");
    state.lastResultSlugs = matches.map(function (doc) { return doc.slug; });
    if (resultsPanel) resultsPanel.hidden = false;
    if (article) article.hidden = true;
    if (status) status.textContent = matches.length + " matching document" + (matches.length === 1 ? "" : "s");
    if (!list) return;
    list.innerHTML = matches.length ? matches.map(function (doc) {
      var excerpt = workerInfo ? makeWorkerExcerpt(doc, workerInfo.get(doc.slug)) : makeExcerpt(doc, matcher);
      return '<a class="search-result" href="#wiki/' + encodeURIComponent(doc.slug)
        + '" data-doc-slug="' + escapeHtml(doc.slug) + '"><div class="search-result__meta"><span>'
        + escapeHtml(doc.category) + "</span><span>" + escapeHtml(doc.format) + "</span></div><h3>"
        + escapeHtml(doc.title) + "</h3><p>" + excerpt + "</p></a>";
    }).join("") : '<div class="empty-state"><strong>No matching documents</strong><p>Try a broader query, remove a filter, or test the pattern in the regex builder.</p></div>';
  }

  function searchNeedsWorker(query) {
    return Boolean(query && state.regex) || state.filters.some(function (rule) {
      return rule.operator === "regex" || rule.operator === "not-regex";
    });
  }

  function stopSearchWorker() {
    if (searchWorker) searchWorker.terminate();
    searchWorker = null;
  }

  function renderSearchError(title, message) {
    var resultsPanel = byId("search-results");
    var article = byId("doc-article");
    var status = byId("search-status");
    var list = byId("search-result-list");
    state.lastResultSlugs = [];
    if (resultsPanel) resultsPanel.hidden = false;
    if (article) article.hidden = true;
    if (status) status.textContent = message;
    if (list) list.innerHTML = '<div class="empty-state"><strong>' + escapeHtml(title)
      + "</strong><p>" + escapeHtml(message) + "</p></div>";
  }

  function runWorkerSearch(query) {
    stopSearchWorker();
    if (!("Worker" in window)) {
      renderSearchError("Regex worker unavailable", "This browser cannot isolate regular-expression searches safely.");
      return;
    }
    var requestId = ++searchRequestId;
    var worker;
    try { worker = new Worker("assets/search-worker.js"); }
    catch (error) {
      renderSearchError("Regex worker unavailable", "This browser blocked the isolated regular-expression worker.");
      return;
    }
    searchWorker = worker;
    var status = byId("search-status");
    if (status) status.textContent = "Searching in an isolated worker…";
    var timeout = setTimeout(function () {
      if (requestId !== searchRequestId) return;
      stopSearchWorker();
      renderSearchError("Search timed out", "The expression exceeded the 1.2 second safety limit. Try a more specific pattern.");
    }, 1200);
    worker.addEventListener("message", function (event) {
      var result = event.data || {};
      if (requestId !== searchRequestId || result.requestId !== requestId) return;
      clearTimeout(timeout);
      stopSearchWorker();
      if (result.error) {
        renderSearchError("Invalid regular expression", result.error);
        return;
      }
      var info = new Map();
      (result.matches || []).forEach(function (item) { info.set(item.slug, item); });
      var matches = (result.matches || []).map(function (item) {
        return state.docBySlug.get(item.slug);
      }).filter(Boolean);
      renderSearchMatches(matches, null, info);
    });
    worker.addEventListener("error", function () {
      if (requestId !== searchRequestId) return;
      clearTimeout(timeout);
      stopSearchWorker();
      renderSearchError("Search worker failed", "The isolated regex worker could not complete the search.");
    });
    try {
      worker.postMessage({
        type: "search",
        requestId: requestId,
        query: query,
        options: {
          regex: state.regex,
          wholeWord: state.wholeWord,
          caseSensitive: state.caseSensitive,
          flags: state.regexFlags
        },
        filters: state.filters,
        filterMode: state.filterMode,
        documents: state.docs.map(function (doc) {
          return {
            slug: doc.slug,
            title: doc.title,
            path: doc.path,
            category: doc.category,
            format: doc.format,
            content: doc.content
          };
        })
      });
    } catch (error) {
      clearTimeout(timeout);
      stopSearchWorker();
      renderSearchError("Search worker failed", "The isolated regex worker could not start the search.");
    }
  }

  function performSearch(updateRoute) {
    var resultsPanel = byId("search-results");
    var article = byId("doc-article");
    var status = byId("search-status");
    var list = byId("search-result-list");
    var query = state.query.trim();
    var matcher = null;
    var error = "";
    searchRequestId++;
    stopSearchWorker();
    persistSearch();
    try {
      validateFilterRules(state.filters);
      matcher = compileSearch(query, {
        regex: state.regex,
        wholeWord: state.wholeWord,
        caseSensitive: state.caseSensitive,
        flags: state.regexFlags
      });
    } catch (problem) { error = problem.message; }

    if (error) {
      stopSearchWorker();
      renderSearchError("Invalid regular expression", error);
      return;
    }

    if (!query && !state.filters.length) {
      stopSearchWorker();
      state.lastResultSlugs = [];
      if (resultsPanel) resultsPanel.hidden = true;
      if (article) article.hidden = false;
      if (status) status.textContent = "Type to search all documentation";
      return;
    }

    if (updateRoute !== false && location.hash !== "#wiki") {
      history.pushState(null, "", "#wiki");
      document.title = LANDING_TITLE;
    }

    if (searchNeedsWorker(query)) {
      if (resultsPanel) resultsPanel.hidden = false;
      if (article) article.hidden = true;
      if (list) list.innerHTML = '<div class="empty-state"><strong>Searching safely…</strong><p>The expression is running in an isolated, time-limited worker.</p></div>';
      runWorkerSearch(query);
      return;
    }

    var matches = state.docs.filter(function (doc) {
      if (!passesFilters(doc)) return false;
      return !matcher || regexTest(matcher, [doc.title, doc.path, doc.category, doc.format, doc.content].join("\n"));
    }).slice(0, 150);
    renderSearchMatches(matches, matcher, null);
  }

  var debouncedSearch = debounce(performSearch, 110);
  function persistSearch() {
    saveStored(STORAGE.search, {
      query: state.query,
      regex: state.regex,
      caseSensitive: state.caseSensitive,
      wholeWord: state.wholeWord,
      regexFlags: state.regexFlags,
      filters: state.filters,
      filterMode: state.filterMode
    });
  }

  function renderFilterChips() {
    var target = byId("active-filter-chips");
    if (!target) return;
    target.innerHTML = state.filters.map(function (rule, index) {
      return '<button type="button" data-remove-filter="' + index + '" title="Remove filter">'
        + escapeHtml((rule.negate ? "not " : "") + (rule.field || "all") + " "
        + (rule.operator || "contains") + " " + (rule.value || "")) + " ×</button>";
    }).join("");
  }

  function filterRuleMarkup(rule, index) {
    var fieldOptions = FILTER_FIELDS.map(function (option) {
      return '<option value="' + option[0] + '"' + (rule.field === option[0] ? " selected" : "") + ">"
        + option[1] + "</option>";
    }).join("");
    var operatorOptions = FILTER_OPERATORS.map(function (option) {
      return '<option value="' + option[0] + '"' + (rule.operator === option[0] ? " selected" : "") + ">"
        + option[1] + "</option>";
    }).join("");
    return '<div class="filter-rule" data-filter-index="' + index + '"><label><span>Field</span><select data-filter-field>'
      + fieldOptions + '</select></label><label><span>Condition</span><select data-filter-operator>'
      + operatorOptions + '</select></label><label class="filter-rule__value"><span>Value</span><input data-filter-value type="text" value="'
      + escapeHtml(rule.value || "") + '" placeholder="e.g. installer"></label><label class="toggle-chip"><input data-filter-negate type="checkbox"'
      + (rule.negate ? " checked" : "") + "><span>!</span> Negate</label>"
      + '<button class="icon-button remove-filter-rule" type="button" data-remove-rule="' + index
      + '" aria-label="Remove rule">×</button></div>';
  }

  function renderFilterRules() {
    var container = byId("filter-rules");
    if (!container) return;
    if (!filterDraft.length) filterDraft.push({ field: "all", operator: "contains", value: "", negate: false });
    container.innerHTML = filterDraft.map(filterRuleMarkup).join("");
    var match = document.querySelector('input[name="filter-match"][value="' + state.filterMode + '"]');
    if (match) match.checked = true;
  }

  function readFilterRules() {
    return all("[data-filter-index]", byId("filter-rules")).map(function (row) {
      return {
        field: row.querySelector("[data-filter-field]").value,
        operator: row.querySelector("[data-filter-operator]").value,
        value: row.querySelector("[data-filter-value]").value.trim(),
        negate: row.querySelector("[data-filter-negate]").checked
      };
    }).filter(function (rule) { return rule.value; });
  }

  function stopPreviewWorker() {
    if (previewWorker) previewWorker.terminate();
    previewWorker = null;
  }

  function renderRegexPreview(sample, result) {
    var preview = byId("regex-preview");
    if (!preview) return;
    var sampleUsed = sample.slice(0, Number(result.sampleLength) || 0);
    var matches = result.matches || [];
    var cursor = 0;
    var highlighted = "";
    matches.forEach(function (item) {
      highlighted += escapeHtml(sampleUsed.slice(cursor, item.index))
        + "<mark>" + escapeHtml(item.text || "∅") + "</mark>";
      cursor = item.index + item.text.length;
    });
    highlighted += escapeHtml(sampleUsed.slice(cursor));
    var groups = [];
    matches.forEach(function (item, matchIndex) {
      (item.groups || []).forEach(function (group, groupIndex) {
        groups.push("match " + (matchIndex + 1) + " · group " + (groupIndex + 1) + ": "
          + (group == null ? "undefined" : group));
      });
    });
    preview.classList.remove("is-error");
    preview.innerHTML = "<span>" + matches.length + " match" + (matches.length === 1 ? "" : "es")
      + (groups.length ? " · " + groups.length + " capture groups" : "")
      + (result.truncated ? " · sample truncated safely" : "") + "</span><code>"
      + (highlighted || "No matches in sample text") + "</code>"
      + (groups.length ? "<small>" + escapeHtml(groups.slice(0, 12).join(" | ")) + "</small>" : "");

    // Compact match list with positions.
    var listHost = byId("regex-match-list");
    if (listHost) {
      if (!matches.length) {
        listHost.hidden = true;
      } else {
        listHost.hidden = false;
        listHost.innerHTML = "<span>Matches</span>" + matches.slice(0, 30).map(function (item, i) {
          var named = item.namedGroups && Object.keys(item.namedGroups).length
            ? " · " + Object.keys(item.namedGroups).map(function (k) {
                return k + "=" + (item.namedGroups[k] == null ? "∅" : item.namedGroups[k]);
              }).join(", ")
            : "";
          return '<div class="regex-match-row"><b>' + (i + 1) + '</b><code>'
            + escapeHtml(item.text || "∅") + '</code><small>@' + item.index + escapeHtml(named) + '</small></div>';
        }).join("") + (matches.length > 30 ? '<div class="regex-match-row regex-match-row--more">+ '
          + (matches.length - 30) + ' more</div>' : "");
      }
    }

    // Replacement preview (only when a replacement string is set).
    var replaceHost = byId("regex-replace-preview");
    if (replaceHost) {
      if (typeof result.replaced === "string") {
        replaceHost.hidden = false;
        replaceHost.querySelector("code").textContent = result.replaced || "(empty result)";
      } else {
        replaceHost.hidden = true;
      }
    }
  }

  function updateRegexPreview() {
    var patternInput = byId("regex-pattern");
    var flagsInput = byId("regex-flags");
    var sampleInput = byId("regex-sample");
    var preview = byId("regex-preview");
    if (!patternInput || !preview) return;
    var pattern = patternInput.value;
    var flags = flagsInput ? flagsInput.value : "gi";
    var sample = sampleInput ? sampleInput.value : "";
    var replaceInput = byId("regex-replace");
    var replacement = replaceInput ? replaceInput.value : "";
    var requestId = ++previewRequestId;
    stopPreviewWorker();

    var explain = byId("regex-explain");
    if (explain) explain.innerHTML = "<span>Explanation</span><p>" + escapeHtml(explainPattern(pattern)) + "</p>";

    if (!pattern) {
      preview.classList.remove("is-error");
      preview.innerHTML = "<span>Pattern preview</span><code>No pattern entered</code>";
      var emptyList = byId("regex-match-list");
      if (emptyList) emptyList.hidden = true;
      var emptyReplace = byId("regex-replace-preview");
      if (emptyReplace) emptyReplace.hidden = true;
      return;
    }
    try {
      compileSearch(pattern, {
        regex: true,
        wholeWord: false,
        caseSensitive: false,
        flags: flags
      });
    } catch (error) {
      preview.classList.add("is-error");
      preview.innerHTML = "<span>Pattern error</span><code>" + escapeHtml(error.message) + "</code>";
      return;
    }
    if (!("Worker" in window)) {
      preview.classList.add("is-error");
      preview.innerHTML = "<span>Preview unavailable</span><code>This browser cannot isolate regex evaluation safely.</code>";
      return;
    }
    var worker;
    try { worker = new Worker("assets/search-worker.js"); }
    catch (error) {
      preview.classList.add("is-error");
      preview.innerHTML = "<span>Preview unavailable</span><code>This browser blocked the isolated regex worker.</code>";
      return;
    }
    previewWorker = worker;
    preview.classList.remove("is-error");
    preview.innerHTML = "<span>Testing safely…</span><code>The pattern is running in an isolated worker.</code>";
    var timeout = setTimeout(function () {
      if (requestId !== previewRequestId) return;
      stopPreviewWorker();
      preview.classList.add("is-error");
      preview.innerHTML = "<span>Pattern timed out</span><code>Preview exceeded the 600 ms safety limit.</code>";
    }, 600);
    worker.addEventListener("message", function (event) {
      var result = event.data || {};
      if (requestId !== previewRequestId || result.requestId !== requestId) return;
      clearTimeout(timeout);
      stopPreviewWorker();
      if (result.error) {
        preview.classList.add("is-error");
        preview.innerHTML = "<span>Pattern error</span><code>" + escapeHtml(result.error) + "</code>";
        return;
      }
      renderRegexPreview(sample, result);
    });
    worker.addEventListener("error", function () {
      if (requestId !== previewRequestId) return;
      clearTimeout(timeout);
      stopPreviewWorker();
      preview.classList.add("is-error");
      preview.innerHTML = "<span>Preview worker failed</span><code>The isolated regex preview could not finish.</code>";
    });
    try {
      worker.postMessage({
        type: "preview",
        requestId: requestId,
        pattern: pattern,
        flags: flags,
        caseSensitive: flags.indexOf("i") < 0,
        sample: sample,
        replacement: replacement
      });
    } catch (error) {
      clearTimeout(timeout);
      stopPreviewWorker();
      preview.classList.add("is-error");
      preview.innerHTML = "<span>Preview worker failed</span><code>The isolated regex preview could not start.</code>";
    }
  }

  function insertRegexToken(token) {
    var input = byId("regex-pattern");
    if (!input) return;
    var start = input.selectionStart == null ? input.value.length : input.selectionStart;
    var end = input.selectionEnd == null ? input.value.length : input.selectionEnd;
    input.value = input.value.slice(0, start) + token + input.value.slice(end);
    // Drop the caret inside bracketed/lookaround tokens so the next keystroke
    // types where you'd expect.
    var inner = { "( )": 1, "(?: )": 3, "(?= )": 3, "(?! )": 3, "(?<= )": 4, "(?<name> )": 8, "[a-z]": 1, "[^ ]": 2, "{2,4}": 1 };
    var caret = inner[token] != null ? start + inner[token] : start + token.length;
    input.focus();
    input.setSelectionRange(caret, caret);
    updateRegexPreview();
  }

  // ---- Regex builder: flags, explainer, and saved-pattern library ----------

  var REGEX_FLAG_ORDER = ["g", "i", "m", "s", "u", "y"];

  function getRegexFlags() {
    var input = byId("regex-flags");
    return input ? String(input.value || "") : "";
  }

  function setRegexFlags(value) {
    var cleaned = REGEX_FLAG_ORDER.filter(function (flag) { return value.indexOf(flag) >= 0; }).join("");
    var input = byId("regex-flags");
    if (input) input.value = cleaned;
    syncFlagChips();
  }

  function syncFlagChips() {
    var flags = getRegexFlags();
    var display = byId("regex-flags-display");
    if (display) display.textContent = flags || "—";
    document.querySelectorAll("[data-regex-flag]").forEach(function (chip) {
      chip.classList.toggle("is-on", flags.indexOf(chip.getAttribute("data-regex-flag")) >= 0);
    });
  }

  function toggleRegexFlag(flag) {
    var flags = getRegexFlags();
    setRegexFlags(flags.indexOf(flag) >= 0 ? flags.replace(flag, "") : flags + flag);
    updateRegexPreview();
  }

  var REGEX_SAMPLES = {
    version: "Version 5.3.0 shipped 2026-07-11. See v5.2.1, v5.3.0-rc.2, and build.14.423929a0.",
    paths: "src/quick/qml/shell/AppHeader.qml\ndocs/wiki.html\nsrc/base/torrentjournal/torrentjournal.cpp\n/home/user/Downloads/ubuntu-24.04.2-desktop-amd64.iso",
    dates: "2026-07-11, 11/07/2026, July 11 2026, 2026-01-31T14:32:00Z, and 07-04-1998.",
    mixed: "The Material design system defines reusable color, typography, shape, and motion tokens across Transfers, Search, RSS, and the Workspace."
  };

  // Heuristic plain-English explanation of a regex. Deliberately shallow — it
  // narrates the common tokens rather than fully parsing the grammar.
  function explainPattern(pattern) {
    if (!pattern) return "Type a pattern to see a plain-English explanation.";
    var parts = [];
    var rules = [
      [/^\^/, "anchored to the start"],
      [/\$$/, "anchored to the end"],
      [/\(\?:/, "a non-capturing group"],
      [/\(\?<[^>]+>/, "a named capture group"],
      [/\(\?=/, "a positive lookahead"],
      [/\(\?!/, "a negative lookahead"],
      [/\(\?<=/, "a positive lookbehind"],
      [/\(\?<!/, "a negative lookbehind"],
      [/\((?!\?)/, "a capture group"],
      [/\|/, "alternatives (or)"],
      [/\\d/, "digits"],
      [/\\w/, "word characters"],
      [/\\s/, "whitespace"],
      [/\\b/, "word boundaries"],
      [/\[[^\]]*-[^\]]*\]/, "a character range"],
      [/\{\d+,?\d*\}/, "a counted repetition"],
      [/\*/, "zero or more of the preceding"],
      [/\+/, "one or more of the preceding"],
      [/\?/, "an optional part"],
      [/\./, "any character"]
    ];
    rules.forEach(function (rule) {
      if (rule[0].test(pattern) && parts.indexOf(rule[1]) < 0) parts.push(rule[1]);
    });
    if (!parts.length) return "Matches the literal text “" + pattern + "”.";
    var flags = getRegexFlags();
    var flagText = [];
    if (flags.indexOf("i") >= 0) flagText.push("case-insensitively");
    if (flags.indexOf("g") >= 0) flagText.push("every occurrence");
    if (flags.indexOf("m") >= 0) flagText.push("across lines");
    return "Matches " + parts.slice(0, 6).join(", ")
      + (flagText.length ? " — " + flagText.join(", ") : "") + ".";
  }

  function loadRegexLibrary() {
    var list = loadStored(STORAGE.regexLibrary, []);
    return Array.isArray(list) ? list : [];
  }

  function renderRegexLibrary() {
    var host = byId("regex-lib-list");
    if (!host) return;
    var list = loadRegexLibrary();
    if (!list.length) {
      host.innerHTML = '<span class="regex-lib-empty">No saved patterns yet.</span>';
      return;
    }
    host.innerHTML = list.map(function (item, index) {
      return '<span class="regex-lib-item"><button type="button" data-regex-load="' + index
        + '" title="/' + escapeHtml(item.pattern) + '/' + escapeHtml(item.flags || "")
        + '">' + escapeHtml(item.name) + '</button><button type="button" class="regex-lib-remove" data-regex-remove="'
        + index + '" aria-label="Delete ' + escapeHtml(item.name) + '">×</button></span>';
    }).join("");
  }

  function saveRegexToLibrary() {
    var patternInput = byId("regex-pattern");
    var nameInput = byId("regex-lib-name");
    if (!patternInput || !patternInput.value) return showSnackbar("Enter a pattern before saving.");
    var name = (nameInput && nameInput.value.trim()) || ("pattern " + (loadRegexLibrary().length + 1));
    var list = loadRegexLibrary().filter(function (item) { return item.name !== name; });
    list.unshift({ name: name.slice(0, 60), pattern: patternInput.value.slice(0, 320), flags: getRegexFlags() });
    saveStored(STORAGE.regexLibrary, list.slice(0, 40));
    if (nameInput) nameInput.value = "";
    renderRegexLibrary();
    showSnackbar("Saved “" + name + "”.");
  }

  function downloadJson(filename, value) {
    var blob = new Blob([JSON.stringify(value, null, 2) + "\n"], { type: "application/json" });
    var url = URL.createObjectURL(blob);
    var anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = filename;
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
  }

  function exportedWiki() {
    return {
      type: "qbt-material-wiki",
      schemaVersion: 1,
      repository: "Ding-Ding-Projects/qbittorrent-material",
      exportedAt: new Date().toISOString(),
      documents: state.docs.map(function (doc) {
        return {
          slug: doc.slug,
          title: doc.title,
          path: doc.path,
          category: doc.category,
          format: doc.format,
          content: doc.content,
          imported: doc.imported
        };
      })
    };
  }

  function exportedSearch() {
    return {
      type: "qbt-material-search-profile",
      schemaVersion: 1,
      exportedAt: new Date().toISOString(),
      query: state.query,
      regex: state.regex,
      caseSensitive: state.caseSensitive,
      wholeWord: state.wholeWord,
      regexFlags: state.regexFlags,
      filterMode: state.filterMode,
      filters: state.filters,
      matchingDocumentSlugs: state.lastResultSlugs.slice()
    };
  }

  function applySearchProfile(profile) {
    if (!profile || typeof profile !== "object") throw new Error("Invalid search profile.");
    var nextFilters = normalizeFilters(profile.filters);
    var previousCase = state.caseSensitive;
    var previousFlags = state.regexFlags;
    state.caseSensitive = Boolean(profile.caseSensitive);
    state.regexFlags = String(profile.regexFlags || "gi").replace(/[^gimsu]/g, "") || "gi";
    try { validateFilterRules(nextFilters); }
    catch (error) {
      state.caseSensitive = previousCase;
      state.regexFlags = previousFlags;
      throw error;
    }
    state.query = String(profile.query || "").slice(0, 1000);
    state.regex = Boolean(profile.regex);
    state.wholeWord = Boolean(profile.wholeWord);
    state.filterMode = profile.filterMode === "any" ? "any" : "all";
    state.filters = nextFilters;
    syncSearchControls();
    renderFilterChips();
    performSearch();
  }

  function uniqueImportedSlug(title, path) {
    var base = "local-" + slugify(title || path);
    var slug = base;
    var index = 2;
    var used = new Set(state.imported.map(function (doc) { return doc.slug; }));
    while (used.has(slug)) slug = base + "-" + index++;
    return slug;
  }

  function addImportedDocument(doc) {
    if (!doc || typeof doc !== "object") return false;
    var title = String(doc.title || "Imported document").slice(0, 180);
    var path = String(doc.path || ("local/" + slugify(title) + ".md")).replace(/\\/g, "/");
    if (state.docs.some(function (existing) { return !existing.imported && existing.path.toLowerCase() === path.toLowerCase(); })) return false;
    state.imported.push({
      slug: uniqueImportedSlug(title, path),
      title: title,
      path: path,
      category: String(doc.category || "Imported"),
      format: doc.format === "json" ? "json" : "markdown",
      content: String(doc.content == null ? "" : doc.content).slice(0, 1000000),
      importedAt: new Date().toISOString()
    });
    return true;
  }

  async function importFiles(fileList) {
    var files = Array.prototype.slice.call(fileList || []);
    var added = 0;
    for (var i = 0; i < files.length; i++) {
      var file = files[i];
      if (file.size > 2097152) {
        showSnackbar(file.name + " exceeds the 2 MB import limit.");
        continue;
      }
      var text;
      try { text = await file.text(); }
      catch (error) {
        showSnackbar("Could not read " + file.name + ".");
        continue;
      }
      if (/\.json$/i.test(file.name)) {
        var parsed = safeJsonParse(text, null);
        if (parsed && parsed.type === "qbt-material-search-profile") {
          try {
            applySearchProfile(parsed);
            showSnackbar("Imported search profile " + file.name);
          } catch (error) {
            showSnackbar("Could not import " + file.name + ": " + error.message);
          }
          continue;
        }
        if (parsed && Array.isArray(parsed.documents)) {
          parsed.documents.slice(0, 500).forEach(function (doc) {
            if (addImportedDocument(doc)) added++;
          });
          continue;
        }
        if (parsed) {
          if (addImportedDocument({
            title: file.name.replace(/\.json$/i, ""),
            path: "local/" + file.name,
            format: "json",
            content: JSON.stringify(parsed, null, 2)
          })) added++;
          continue;
        }
        showSnackbar("Could not parse " + file.name + " as JSON.");
        continue;
      }
      if (addImportedDocument({
        title: file.name.replace(/\.(?:md|markdown|txt)$/i, "").replace(/[-_]+/g, " "),
        path: "local/" + file.name,
        format: "markdown",
        content: text
      })) added++;
    }
    if (added) {
      var persisted = saveStored(STORAGE.imported, state.imported);
      rebuildCorpus();
      renderNavigation();
      renderImportList();
      performSearch();
      if (persisted) {
        showSnackbar("Imported " + added + " local page" + (added === 1 ? "" : "s") + ".");
      } else {
        showSnackbar("Imported pages are session-only because browser storage is full; export them before closing.");
      }
    }
  }

  function renderImportList() {
    var list = byId("import-file-list");
    if (!list) return;
    list.innerHTML = state.imported.length ? state.imported.map(function (doc, index) {
      return '<span><strong>' + escapeHtml(doc.title) + '</strong><button type="button" data-remove-import="'
        + index + '" aria-label="Remove ' + escapeHtml(doc.title) + '">×</button></span>';
    }).join("") : "<small>No local pages imported.</small>";
  }

  function syncSearchControls() {
    var search = byId("global-search");
    var regex = byId("regex-toggle");
    var matchCase = byId("case-toggle");
    var wholeWord = byId("whole-word-toggle");
    if (search) search.value = state.query;
    if (regex) regex.checked = state.regex;
    if (matchCase) matchCase.checked = state.caseSensitive;
    if (wholeWord) wholeWord.checked = state.wholeWord;
  }

  function initializeTheme() {
    var stored = null;
    try { stored = localStorage.getItem(STORAGE.theme); } catch (error) {}
    var dark = stored ? stored === "dark" : window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
    document.documentElement.dataset.theme = dark ? "dark" : "light";
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.content = dark ? "#202124" : "#1a73e8";
  }

  function toggleTheme() {
    var dark = document.documentElement.dataset.theme !== "dark";
    document.documentElement.dataset.theme = dark ? "dark" : "light";
    try { localStorage.setItem(STORAGE.theme, dark ? "dark" : "light"); } catch (error) {}
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.content = dark ? "#202124" : "#1a73e8";
    showSnackbar((dark ? "Dark" : "Light") + " theme enabled.");
  }

  function bindEvents() {
    document.addEventListener("click", function (event) {
      var docButton = event.target.closest("[data-doc-slug]");
      if (docButton) {
        event.preventDefault();
        searchRequestId++;
        stopSearchWorker();
        navigateToDocument(docButton.getAttribute("data-doc-slug"), docButton.getAttribute("data-doc-anchor") || "");
        var panel = byId("search-results");
        var article = byId("doc-article");
        if (panel) panel.hidden = true;
        if (article) article.hidden = false;
        return;
      }
      var legacyDoc = event.target.closest("[data-doc]");
      if (legacyDoc) {
        var target = state.docByPath.get(String(legacyDoc.getAttribute("data-doc")).toLowerCase());
        if (target) navigateToDocument(target.slug);
      }
      var removeFilter = event.target.closest("[data-remove-filter]");
      if (removeFilter) {
        state.filters.splice(Number(removeFilter.getAttribute("data-remove-filter")), 1);
        renderFilterChips();
        performSearch();
      }
      var removeRule = event.target.closest("[data-remove-rule]");
      if (removeRule) {
        filterDraft.splice(Number(removeRule.getAttribute("data-remove-rule")), 1);
        renderFilterRules();
      }
      var token = event.target.closest("[data-regex-token]");
      if (token) insertRegexToken(token.getAttribute("data-regex-token"));
      var flag = event.target.closest("[data-regex-flag]");
      if (flag) toggleRegexFlag(flag.getAttribute("data-regex-flag"));
      var samplePreset = event.target.closest("[data-regex-sample]");
      if (samplePreset) {
        var sampleBox = byId("regex-sample");
        var key = samplePreset.getAttribute("data-regex-sample");
        if (sampleBox && REGEX_SAMPLES[key]) { sampleBox.value = REGEX_SAMPLES[key]; updateRegexPreview(); }
      }
      var libLoad = event.target.closest("[data-regex-load]");
      if (libLoad) {
        var loaded = loadRegexLibrary()[Number(libLoad.getAttribute("data-regex-load"))];
        if (loaded) {
          if (byId("regex-pattern")) byId("regex-pattern").value = loaded.pattern;
          setRegexFlags(loaded.flags || "gi");
          updateRegexPreview();
        }
      }
      var libRemove = event.target.closest("[data-regex-remove]");
      if (libRemove) {
        var libList = loadRegexLibrary();
        libList.splice(Number(libRemove.getAttribute("data-regex-remove")), 1);
        saveStored(STORAGE.regexLibrary, libList);
        renderRegexLibrary();
      }
      var removeImport = event.target.closest("[data-remove-import]");
      if (removeImport) {
        state.imported.splice(Number(removeImport.getAttribute("data-remove-import")), 1);
        saveStored(STORAGE.imported, state.imported);
        rebuildCorpus();
        renderNavigation();
        renderImportList();
        performSearch();
      }
      var copy = event.target.closest(".copy-code");
      if (copy) {
        var code = copy.parentElement.querySelector("code");
        if (code && navigator.clipboard) navigator.clipboard.writeText(code.textContent).then(function () {
          copy.textContent = "Copied";
          setTimeout(function () { copy.textContent = "Copy"; }, 1400);
        });
      }
      var gallery = event.target.closest("[data-lightbox]");
      if (gallery) {
        var image = byId("lightbox-image");
        var caption = byId("lightbox-caption");
        if (image) image.src = gallery.getAttribute("data-lightbox");
        if (image) image.alt = gallery.getAttribute("data-caption") || "Application screenshot";
        if (caption) caption.textContent = gallery.getAttribute("data-caption") || "Application screenshot";
        showDialog(byId("lightbox-dialog"));
      }
    });

    var search = byId("global-search");
    if (search) search.addEventListener("input", function () {
      state.query = search.value;
      debouncedSearch();
    });
    var searchForm = byId("global-search-form");
    if (searchForm) searchForm.addEventListener("submit", function (event) {
      event.preventDefault();
      state.query = search ? search.value : state.query;
      performSearch();
    });
    ["regex-toggle", "case-toggle", "whole-word-toggle"].forEach(function (id) {
      var control = byId(id);
      if (!control) return;
      control.addEventListener("change", function () {
        state.regex = Boolean(byId("regex-toggle") && byId("regex-toggle").checked);
        state.caseSensitive = Boolean(byId("case-toggle") && byId("case-toggle").checked);
        state.wholeWord = Boolean(byId("whole-word-toggle") && byId("whole-word-toggle").checked);
        performSearch();
      });
    });

    var filterDialog = byId("filter-dialog");
    var openFilters = byId("open-filter-builder");
    if (openFilters) openFilters.addEventListener("click", function () {
      filterDraft = state.filters.map(function (rule) { return Object.assign({}, rule); });
      renderFilterRules();
      showDialog(filterDialog);
    });
    var addRule = byId("add-filter-rule");
    if (addRule) addRule.addEventListener("click", function () {
      filterDraft.push({ field: "all", operator: "contains", value: "", negate: false });
      renderFilterRules();
    });
    var clearFilters = byId("clear-filters");
    if (clearFilters) clearFilters.addEventListener("click", function () {
      filterDraft = [];
      renderFilterRules();
    });
    var applyFilters = byId("apply-filters");
    if (applyFilters) applyFilters.addEventListener("click", function (event) {
      event.preventDefault();
      var nextFilters = readFilterRules();
      try { validateFilterRules(nextFilters); }
      catch (error) {
        showSnackbar(error.message);
        return;
      }
      state.filters = nextFilters;
      var selectedMode = document.querySelector('input[name="filter-match"]:checked');
      state.filterMode = selectedMode && selectedMode.value === "any" ? "any" : "all";
      renderFilterChips();
      performSearch();
      closeDialog(filterDialog);
    });

    var regexDialog = byId("regex-dialog");
    var openRegex = byId("open-regex-builder");
    if (openRegex) openRegex.addEventListener("click", function () {
      var pattern = byId("regex-pattern");
      var flags = byId("regex-flags");
      if (pattern) pattern.value = state.query;
      if (flags) {
        var effectiveFlags = state.regexFlags.replace(/i/g, "");
        if (!state.caseSensitive) effectiveFlags += "i";
        setRegexFlags(Array.from(new Set(effectiveFlags.split(""))).join(""));
      }
      renderRegexLibrary();
      updateRegexPreview();
      showDialog(regexDialog);
    });
    ["regex-pattern", "regex-sample", "regex-replace"].forEach(function (id) {
      var input = byId(id);
      if (input) input.addEventListener("input", updateRegexPreview);
    });
    var regexLibSave = byId("regex-lib-save");
    if (regexLibSave) regexLibSave.addEventListener("click", saveRegexToLibrary);
    var regexCopy = byId("regex-copy");
    if (regexCopy) regexCopy.addEventListener("click", function () {
      var pattern = byId("regex-pattern") ? byId("regex-pattern").value : "";
      if (!pattern) return showSnackbar("Enter a pattern to copy.");
      var text = "/" + pattern + "/" + getRegexFlags();
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function () { showSnackbar("Copied " + text); },
          function () { showSnackbar("Copy blocked by the browser."); });
      } else showSnackbar("Clipboard is unavailable in this browser.");
    });
    var clearRegex = byId("regex-clear");
    if (clearRegex) clearRegex.addEventListener("click", function () {
      if (byId("regex-pattern")) byId("regex-pattern").value = "";
      if (byId("regex-replace")) byId("regex-replace").value = "";
      setRegexFlags("gi");
      updateRegexPreview();
    });
    var applyRegex = byId("regex-apply");
    if (applyRegex) applyRegex.addEventListener("click", function (event) {
      event.preventDefault();
      var pattern = byId("regex-pattern") ? byId("regex-pattern").value : "";
      var flags = byId("regex-flags") ? byId("regex-flags").value : "gi";
      try {
        compileSearch(pattern, { regex: true, wholeWord: false, caseSensitive: false, flags: flags });
        state.query = pattern;
        state.regex = true;
        state.regexFlags = flags.replace(/[^gimsu]/g, "");
        state.caseSensitive = state.regexFlags.indexOf("i") < 0;
        syncSearchControls();
        performSearch();
        closeDialog(regexDialog);
      } catch (error) { showSnackbar(error.message); }
    });
    var regexExport = byId("regex-export");
    if (regexExport) regexExport.addEventListener("click", function () {
      downloadJson("qbt-material-regex.json", {
        type: "qbt-material-regex",
        schemaVersion: 1,
        pattern: byId("regex-pattern") ? byId("regex-pattern").value : "",
        flags: byId("regex-flags") ? byId("regex-flags").value : "gi",
        sample: byId("regex-sample") ? byId("regex-sample").value.slice(0, 200000) : ""
      });
    });
    var regexImport = byId("regex-import");
    if (regexImport) regexImport.addEventListener("click", function () {
      var input = document.createElement("input");
      input.type = "file";
      input.accept = ".json,application/json";
      input.addEventListener("change", async function () {
        if (!input.files || !input.files[0]) return;
        var file = input.files[0];
        if (file.size > 2097152) return showSnackbar("Regex profiles are limited to 2 MB.");
        var text;
        try { text = await file.text(); }
        catch (error) { return showSnackbar("Could not read the regex profile."); }
        var value = safeJsonParse(text, null);
        if (!value || typeof value.pattern !== "string") return showSnackbar("That file is not a regex profile.");
        if (value.pattern.length > 320) return showSnackbar("Regex patterns are limited to 320 characters.");
        if (byId("regex-pattern")) byId("regex-pattern").value = value.pattern;
        setRegexFlags(String(value.flags || "gi"));
        if (byId("regex-sample") && typeof value.sample === "string") byId("regex-sample").value = value.sample.slice(0, 200000);
        updateRegexPreview();
      });
      input.click();
    });

    var transferDialog = byId("import-export-dialog");
    var openTransfer = byId("open-import-export");
    if (openTransfer) openTransfer.addEventListener("click", function () {
      renderImportList();
      showDialog(transferDialog);
    });
    var importInput = byId("import-files");
    var chooseImport = byId("choose-import-files");
    if (chooseImport && importInput) chooseImport.addEventListener("click", function () {
      importInput.click();
    });
    if (importInput) importInput.addEventListener("change", function () {
      importFiles(importInput.files)
        .catch(function (error) { showSnackbar("Import failed: " + error.message); })
        .finally(function () { importInput.value = ""; });
    });
    var clearImports = byId("clear-imports");
    if (clearImports) clearImports.addEventListener("click", function () {
      state.imported = [];
      saveStored(STORAGE.imported, state.imported);
      rebuildCorpus();
      renderNavigation();
      renderImportList();
      performSearch();
      showSnackbar("Cleared local imported pages.");
    });
    var exportWiki = byId("export-wiki");
    if (exportWiki) exportWiki.addEventListener("click", function () {
      downloadJson("qbt-material-wiki.json", exportedWiki());
    });
    var exportSearch = byId("export-search");
    if (exportSearch) exportSearch.addEventListener("click", function () {
      downloadJson("qbt-material-search.json", exportedSearch());
    });

    var theme = byId("theme-toggle");
    if (theme) theme.addEventListener("click", toggleTheme);
    var mobile = byId("mobile-nav-toggle");
    var primary = byId("primary-navigation");
    if (mobile && primary) mobile.addEventListener("click", function () {
      var open = mobile.getAttribute("aria-expanded") === "true";
      mobile.setAttribute("aria-expanded", String(!open));
      primary.classList.toggle("is-open", !open);
    });
    var snackbarAction = byId("snackbar-action");
    if (snackbarAction) snackbarAction.addEventListener("click", function () {
      var bar = byId("snackbar");
      if (bar) bar.hidden = true;
    });
    document.addEventListener("keydown", function (event) {
      var tag = document.activeElement && document.activeElement.tagName;
      var typing = tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT";
      if ((event.key === "/" && !typing) || ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k")) {
        event.preventDefault();
        if (search) {
          byId("wiki").scrollIntoView({ behavior: "smooth", block: "start" });
          search.focus();
          search.select();
        }
      } else if (event.key === "Escape" && search && document.activeElement === search && search.value) {
        search.value = "";
        state.query = "";
        performSearch();
      }
    });
    window.addEventListener("hashchange", handleRoute);
  }

  function registerServiceWorker() {
    if ("serviceWorker" in navigator && location.protocol.indexOf("http") === 0) {
      navigator.serviceWorker.register("./sw.js").catch(function () {});
    }
  }

  // Point the download buttons straight at the newest Windows installer .exe.
  // Every push publishes a full release and is marked "latest" on creation,
  // but pushes on different branches can complete out of order, so the
  // releases LIST is queried and the newest "*-windows-x64.exe" asset chosen
  // rather than trusting /releases/latest. On any failure (offline, API rate
  // limit) the buttons keep their /releases fallback href.
  function resolveInstallerLink() {
    var links = document.querySelectorAll(".js-installer-link");
    if (!links.length || typeof fetch !== "function") return;
    var api = "https://api.github.com/repos/Ding-Ding-Projects/qbittorrent-material/releases?per_page=15";
    fetch(api, { headers: { Accept: "application/vnd.github+json" } })
      .then(function (response) {
        if (!response.ok) throw new Error("releases request failed: " + response.status);
        return response.json();
      })
      .then(function (releases) {
        if (!Array.isArray(releases)) return;
        var asset = null;
        var releaseTag = "";
        for (var i = 0; i < releases.length && !asset; i++) {
          var release = releases[i];
          if (release.draft) continue;
          var assets = release.assets || [];
          for (var j = 0; j < assets.length; j++) {
            if (/-windows-x64\.exe$/i.test(assets[j].name || "")) {
              asset = assets[j];
              releaseTag = release.tag_name || release.name || "";
              break;
            }
          }
        }
        if (!asset || !asset.browser_download_url) return;
        Array.prototype.forEach.call(links, function (link) {
          link.href = asset.browser_download_url;
          link.setAttribute("download", "");
          var label = link.getAttribute("data-installer-label") || "Download";
          link.title = "Download the Windows installer directly"
            + (releaseTag ? " · " + releaseTag : "");
          link.setAttribute("aria-label", label + " — direct .exe download"
            + (releaseTag ? " (" + releaseTag + ")" : ""));
        });
      })
      .catch(function () { /* keep the /releases fallback href */ });
  }

  function initialize() {
    // The documentation wiki lives on its own page (wiki.html). If a legacy
    // "#wiki/..." deep link lands on a page without the wiki shell (the
    // marketing landing page), forward it to the dedicated wiki page so old
    // bookmarks and shared links keep working.
    if (!byId("wiki-workspace") && /^#wiki(\/|$)/.test(location.hash)) {
      location.replace("wiki.html" + location.hash);
      return;
    }
    initializeTheme();
    rebuildCorpus();
    syncSearchControls();
    renderNavigation();
    renderFilterChips();
    renderImportList();
    bindEvents();
    var explicitDocumentRoute = handleRoute();
    if (!explicitDocumentRoute && (state.query || state.filters.length)) performSearch(false);
    registerServiceWorker();
    resolveInstallerLink();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", initialize);
  else initialize();
})();
