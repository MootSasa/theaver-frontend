import 'dart:convert';

/// Block types produced by [BrowserReaderModeScript.buildExtractArticleScript].
enum BrowserReaderBlockType {
  heading,
  paragraph,
  quote,
  code,
  list,
  image,
}

/// Structured content block within a [BrowserReaderArticle].
class BrowserReaderBlock {
  final BrowserReaderBlockType type;
  final String text;
  final int headingLevel;
  final List<String> items;
  final String? imageUrl;
  final String? caption;

  const BrowserReaderBlock({
    required this.type,
    this.text = '',
    this.headingLevel = 2,
    this.items = const <String>[],
    this.imageUrl,
    this.caption,
  });

  static BrowserReaderBlockType _parseType(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'heading':
        return BrowserReaderBlockType.heading;
      case 'quote':
        return BrowserReaderBlockType.quote;
      case 'code':
        return BrowserReaderBlockType.code;
      case 'list':
        return BrowserReaderBlockType.list;
      case 'image':
        return BrowserReaderBlockType.image;
      case 'paragraph':
      default:
        return BrowserReaderBlockType.paragraph;
    }
  }

  factory BrowserReaderBlock.fromJson(Map<String, dynamic> json) {
    final type = _parseType(json['type']?.toString() ?? 'paragraph');
    final rawLevel = (json['headingLevel'] as num?)?.toInt() ?? 2;
    final headingLevel = rawLevel.clamp(1, 6);
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
            .map((e) => e?.toString().trim() ?? '')
            .where((s) => s.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    final rawImg = json['imageUrl']?.toString().trim();
    final imageUrl =
        (rawImg != null && rawImg.isNotEmpty) ? rawImg : null;
    final rawCaption = json['caption']?.toString().trim();
    final caption =
        (rawCaption != null && rawCaption.isNotEmpty) ? rawCaption : null;

    return BrowserReaderBlock(
      type: type,
      text: json['text']?.toString() ?? '',
      headingLevel: headingLevel,
      items: items,
      imageUrl: imageUrl,
      caption: caption,
    );
  }
}

/// Extracted clean article representation for Safari-style Reader Mode.
class BrowserReaderArticle {
  final String url;
  final String title;
  final String byline;
  final String siteName;
  final String publishedTime;
  final int estimatedReadMinutes;
  final List<BrowserReaderBlock> blocks;

  const BrowserReaderArticle({
    required this.url,
    required this.title,
    this.byline = '',
    this.siteName = '',
    this.publishedTime = '',
    this.estimatedReadMinutes = 1,
    required this.blocks,
  });

  factory BrowserReaderArticle.fromJson(Map<String, dynamic> json) {
    final rawBlocks = json['blocks'];
    final blocks = <BrowserReaderBlock>[];
    if (rawBlocks is List) {
      for (final item in rawBlocks) {
        if (item is Map) {
          final parsed = BrowserReaderBlock.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (parsed.type == BrowserReaderBlockType.image) {
            if (parsed.imageUrl != null && parsed.imageUrl!.isNotEmpty) {
              blocks.add(parsed);
            }
          } else if (parsed.type == BrowserReaderBlockType.list) {
            if (parsed.items.isNotEmpty) {
              blocks.add(parsed);
            }
          } else if (parsed.text.trim().isNotEmpty) {
            blocks.add(parsed);
          }
        }
      }
    }
    final rawMinutes = (json['estimatedReadMinutes'] as num?)?.toInt() ?? 1;
    return BrowserReaderArticle(
      url: json['url']?.toString() ?? '',
      title: json['title']?.toString().trim() ?? '',
      byline: json['byline']?.toString().trim() ?? '',
      siteName: json['siteName']?.toString().trim() ?? '',
      publishedTime: json['publishedTime']?.toString().trim() ?? '',
      estimatedReadMinutes: rawMinutes < 1 ? 1 : rawMinutes,
      blocks: List<BrowserReaderBlock>.unmodifiable(blocks),
    );
  }

  /// Safely decodes results returned by WKWebView or Android WebView
  /// `runJavaScriptReturningResult`, including double-encoded JSON strings.
  static BrowserReaderArticle? tryParseJsResult(dynamic raw) {
    dynamic current = raw;
    for (int i = 0; i < 3; i++) {
      if (current == null) return null;
      if (current is Map) {
        final map = Map<String, dynamic>.from(current);
        if (map.isEmpty) return null;
        final article = BrowserReaderArticle.fromJson(map);
        if (article.title.isEmpty && article.blocks.isEmpty) {
          return null;
        }
        return article;
      }
      if (current is String) {
        final trimmed = current.trim();
        if (trimmed.isEmpty || trimmed == 'null' || trimmed == 'undefined') {
          return null;
        }
        try {
          current = jsonDecode(trimmed);
        } catch (_) {
          return null;
        }
      } else {
        return null;
      }
    }
    return null;
  }
}

/// Main-frame-only JavaScript extractor and page zoom controller for Reader Mode.
abstract final class BrowserReaderModeScript {
  /// Fast (`<10ms`) main-frame readability availability check.
  static String buildCheckReaderAvailabilityScript() {
    return r'''
(function() {
  try {
    if (typeof window === 'undefined' || window !== window.top) return false;
    var proto = window.location && window.location.protocol;
    if (proto !== 'http:' && proto !== 'https:') return false;
    if (!document || !document.body) return false;

    function isHidden(el) {
      if (!el) return true;
      if (el.hidden) return true;
      var st = el.style || {};
      if (st.display === 'none' || st.visibility === 'hidden') return true;
      if (typeof window.getComputedStyle === 'function') {
        var cs = window.getComputedStyle(el);
        if (cs && (cs.display === 'none' || cs.visibility === 'hidden')) return true;
      }
      return false;
    }

    var noiseSel = 'nav, header, footer, aside, form, [role="navigation"], [role="banner"], [role="complementary"], [aria-hidden="true"]';
    function countSubstantialParagraphs(root) {
      if (!root || !root.querySelectorAll) return { count: 0, chars: 0 };
      var ps = root.querySelectorAll('p');
      var count = 0;
      var chars = 0;
      var limit = Math.min(ps.length, 80);
      for (var i = 0; i < limit; i++) {
        var p = ps[i];
        if (typeof p.closest === 'function' && p.closest(noiseSel)) continue;
        if (isHidden(p)) continue;
        var txt = (p.textContent || '').replace(/\s+/g, ' ').trim();
        if (txt.length >= 25) {
          count += 1;
          chars += txt.length;
          if (count >= 3 && chars >= 500) {
            return { count: count, chars: chars };
          }
        }
      }
      return { count: count, chars: chars };
    }

    var articleEl = document.querySelector('article, [role="article"]');
    var articleStats = articleEl ? countSubstantialParagraphs(articleEl) : { count: 0, chars: 0 };
    var hasSubstantialArticle = articleStats.count >= 3 && articleStats.chars >= 500;

    var pwds = document.querySelectorAll('input[type="password"]');
    for (var k = 0; k < pwds.length; k++) {
      if (!isHidden(pwds[k]) && !hasSubstantialArticle) {
        return false;
      }
    }

    var path = (window.location.pathname || '/').toLowerCase();
    if (/\/(login|signin|sign-in|signup|register|auth|checkout|cart|basket|search)(\/|$)/i.test(path)) {
      if (!hasSubstantialArticle) return false;
    }
    if (path === '/' || path === '') {
      if (!hasSubstantialArticle) return false;
    }

    var hasSignal = !!articleEl || !!document.querySelector('[role="main"], main');
    if (!hasSignal) {
      var ogType = document.querySelector('meta[property="og:type"]');
      if (ogType && /article/i.test(ogType.getAttribute('content') || '')) {
        hasSignal = true;
      }
    }
    if (!hasSignal) {
      var ldScripts = document.querySelectorAll('script[type="application/ld+json"]');
      for (var s = 0; s < ldScripts.length; s++) {
        var rawLd = ldScripts[s].textContent || '';
        if (/"@(type)"\s*:\s*"?(Article|NewsArticle|BlogPosting)"?/i.test(rawLd) ||
            /\b(Article|NewsArticle|BlogPosting)\b/.test(rawLd)) {
          hasSignal = true;
          break;
        }
      }
    }
    if (!hasSignal) return false;

    if (hasSubstantialArticle) return true;
    var docStats = countSubstantialParagraphs(document.querySelector('main, [role="main"]') || document.body);
    return docStats.count >= 3 && docStats.chars >= 500;
  } catch (_) {
    return false;
  }
})();
''';
  }

  /// Extracts a clean, structured article JSON string from the top-level page.
  static String buildExtractArticleScript() {
    return r'''
(function() {
  try {
    if (typeof window === 'undefined' || window !== window.top) return 'null';
    var proto = window.location && window.location.protocol;
    if (proto !== 'http:' && proto !== 'https:') return 'null';
    if (!document || !document.body) return 'null';

    function cleanText(raw) {
      return String(raw || '').replace(/\s+/g, ' ').trim();
    }

    function firstText(selectors) {
      for (var i = 0; i < selectors.length; i++) {
        var el = document.querySelector(selectors[i]);
        if (!el) continue;
        var val = el.tagName === 'META'
            ? cleanText(el.getAttribute('content'))
            : cleanText(el.textContent);
        if (val) return val;
      }
      return '';
    }

    var title = firstText([
      'article h1',
      '[role="article"] h1',
      'main h1',
      '[role="main"] h1',
      'h1',
      'meta[property="og:title"]',
      'meta[name="twitter:title"]'
    ]) || cleanText(document.title);

    var byline = firstText([
      'meta[name="author"]',
      '[rel="author"]',
      '.byline',
      '.author',
      '[itemprop="author"]'
    ]);
    if (byline.length > 140) byline = byline.slice(0, 140);

    var siteName = firstText(['meta[property="og:site_name"]']) ||
        String(window.location.hostname || '').replace(/^www\./i, '');

    var publishedTime = '';
    var timeEl = document.querySelector('article time[datetime], time[datetime]');
    if (timeEl) {
      publishedTime = cleanText(timeEl.getAttribute('datetime')) || cleanText(timeEl.textContent);
    }
    if (!publishedTime) {
      publishedTime = firstText([
        'meta[property="article:published_time"]',
        'meta[name="pubdate"]',
        'meta[name="date"]'
      ]);
    }

    var noiseSelector = 'script, style, noscript, template, nav, header, footer, aside, form, button, svg, iframe, [role="navigation"], [role="banner"], [role="complementary"], [aria-hidden="true"], .ads, .advertisement, .cookie-banner, .comments, .related-posts, .share-buttons';

    function scoreContainer(el) {
      if (!el || !el.querySelectorAll) return 0;
      var ps = el.querySelectorAll('p');
      var score = 0;
      for (var i = 0; i < ps.length; i++) {
        var p = ps[i];
        if (typeof p.closest === 'function') {
          var noisyAncestor = p.closest(noiseSelector);
          if (noisyAncestor && noisyAncestor !== el && el.contains(noisyAncestor)) continue;
        }
        var txt = cleanText(p.textContent);
        if (txt.length >= 20) {
          score += txt.length;
        }
      }
      var tag = (el.tagName || '').toUpperCase();
      if (tag === 'ARTICLE' || (el.getAttribute && el.getAttribute('role') === 'article')) {
        score = Math.round(score * 1.4);
      } else if (tag === 'MAIN' || (el.getAttribute && el.getAttribute('role') === 'main')) {
        score = Math.round(score * 1.15);
      }
      return score;
    }

    var candidates = [];
    var primary = document.querySelectorAll('article, [role="article"], main, [role="main"]');
    for (var i = 0; i < primary.length; i++) {
      candidates.push(primary[i]);
    }
    var fallbackScope = document.querySelector('main, [role="main"]') || document.body;
    var subBlocks = fallbackScope.querySelectorAll('section, div');
    for (var j = 0; j < Math.min(subBlocks.length, 60); j++) {
      if (subBlocks[j].querySelectorAll('p').length >= 3) {
        candidates.push(subBlocks[j]);
      }
    }
    candidates.push(document.body);

    var bestEl = document.body;
    var bestScore = -1;
    for (var k = 0; k < candidates.length; k++) {
      var sc = scoreContainer(candidates[k]);
      if (sc > bestScore) {
        bestScore = sc;
        bestEl = candidates[k];
      }
    }

    var clone = bestEl.cloneNode(true);
    var noisyNodes = clone.querySelectorAll(noiseSelector);
    for (var n = 0; n < noisyNodes.length; n++) {
      var node = noisyNodes[n];
      if (node && node.parentNode) {
        node.parentNode.removeChild(node);
      }
    }

    function resolveImageUrl(imgEl) {
      if (!imgEl) return '';
      var rawSrc = (
        imgEl.getAttribute('src') ||
        imgEl.getAttribute('data-src') ||
        imgEl.getAttribute('data-original') ||
        ''
      ).trim();
      if (!rawSrc || /^data:/i.test(rawSrc) || /^javascript:/i.test(rawSrc)) return '';
      var absUrl = '';
      try {
        absUrl = new URL(rawSrc, document.baseURI).href;
      } catch (_) {
        return '';
      }
      if (!/^https?:\/\//i.test(absUrl)) return '';

      var natW = typeof imgEl.naturalWidth === 'number' ? imgEl.naturalWidth : 0;
      var attrW = parseInt(imgEl.getAttribute('width') || '0', 10) || 0;
      var knownW = natW || attrW;
      if (knownW > 0 && knownW < 120) return '';

      var natH = typeof imgEl.naturalHeight === 'number' ? imgEl.naturalHeight : 0;
      var attrH = parseInt(imgEl.getAttribute('height') || '0', 10) || 0;
      var knownH = natH || attrH;
      if (knownH > 0 && knownH < 48) return '';

      if (knownW === 0 && /(?:^|\/)(?:icon|favicon|emoji|avatar|pixel|spacer|badge|logo-small|1x1)(?:[._/-]|$)/i.test(absUrl)) {
        return '';
      }
      return absUrl;
    }

    var blocks = [];
    var seenTitleHeading = false;

    function pushImageFromEl(imgEl, captionText) {
      var url = resolveImageUrl(imgEl);
      if (!url) return;
      var cap = cleanText(captionText || imgEl.getAttribute('alt') || '');
      blocks.push({
        type: 'image',
        imageUrl: url,
        caption: cap || null
      });
    }

    function walk(node) {
      if (!node || node.nodeType !== 1) return;
      var tag = (node.tagName || '').toUpperCase();

      if (tag === 'H1' || tag === 'H2' || tag === 'H3' || tag === 'H4') {
        var hText = cleanText(node.textContent);
        if (!hText) return;
        if (tag === 'H1' && !seenTitleHeading && title && hText.toLowerCase() === title.toLowerCase()) {
          seenTitleHeading = true;
          return;
        }
        blocks.push({
          type: 'heading',
          headingLevel: parseInt(tag.charAt(1), 10),
          text: hText
        });
        return;
      }

      if (tag === 'P') {
        var imgsInP = node.querySelectorAll ? node.querySelectorAll('img') : [];
        for (var pi = 0; pi < imgsInP.length; pi++) {
          pushImageFromEl(imgsInP[pi], '');
        }
        var pText = cleanText(node.textContent);
        if (pText.length >= 20) {
          blocks.push({ type: 'paragraph', text: pText });
        }
        return;
      }

      if (tag === 'BLOCKQUOTE') {
        var qText = cleanText(node.textContent);
        if (qText.length >= 10) {
          blocks.push({ type: 'quote', text: qText });
        }
        return;
      }

      if (tag === 'PRE') {
        var preText = String(node.textContent || '').replace(/^\n+|\n+$/g, '').trim();
        if (preText) {
          blocks.push({ type: 'code', text: preText });
        }
        return;
      }

      if (tag === 'CODE') {
        var codeText = String(node.textContent || '').trim();
        if (codeText && (codeText.indexOf('\n') !== -1 || codeText.length >= 40)) {
          blocks.push({ type: 'code', text: codeText });
          return;
        }
      }

      if (tag === 'UL' || tag === 'OL') {
        var liNodes = node.querySelectorAll('li');
        var items = [];
        for (var liIdx = 0; liIdx < liNodes.length; liIdx++) {
          var liText = cleanText(liNodes[liIdx].textContent);
          if (liText) items.push(liText);
        }
        if (items.length > 0) {
          blocks.push({ type: 'list', items: items });
        }
        return;
      }

      if (tag === 'FIGURE') {
        var figImg = node.querySelector('img');
        var figCapEl = node.querySelector('figcaption');
        var figCap = figCapEl ? cleanText(figCapEl.textContent) : '';
        if (figImg) {
          pushImageFromEl(figImg, figCap);
          return;
        }
      }

      if (tag === 'IMG') {
        pushImageFromEl(node, '');
        return;
      }

      var children = node.children || [];
      for (var c = 0; c < children.length; c++) {
        walk(children[c]);
      }
    }

    walk(clone);

    if (blocks.length === 0) return 'null';

    var words = 0;
    for (var b = 0; b < blocks.length; b++) {
      var blk = blocks[b];
      if (blk.text) {
        var parts = blk.text.trim().split(/\s+/);
        if (parts[0]) words += parts.length;
      } else if (blk.items) {
        for (var it = 0; it < blk.items.length; it++) {
          var ip = blk.items[it].trim().split(/\s+/);
          if (ip[0]) words += ip.length;
        }
      }
    }
    var readMinutes = Math.max(1, Math.round(words / 200));

    return JSON.stringify({
      url: window.location.href,
      title: title,
      byline: byline,
      siteName: siteName,
      publishedTime: publishedTime,
      estimatedReadMinutes: readMinutes,
      blocks: blocks
    });
  } catch (_) {
    return 'null';
  }
})();
''';
  }

  /// Applies Safari-style text size zoom (`0.85..1.50`) to the page root.
  static String buildApplyPageTextZoomScript(double scale) {
    final clamped = scale.clamp(0.85, 1.50);
    final pct = (clamped * 100).round();
    return '''
(function() {
  try {
    if (typeof window === 'undefined' || window !== window.top) return false;
    var root = document.documentElement;
    if (!root || !root.style) return false;
    root.style.webkitTextSizeAdjust = '$pct%';
    root.style.textSizeAdjust = '$pct%';
    return $pct;
  } catch (_) {
    return false;
  }
})();
''';
  }
}
