import 'dart:convert';

/// Current match position and total matches returned by the in-page finder.
class BrowserFindInPageResult {
  /// 1-based index of the active match, or `0` when [total] is `0`.
  final int current;

  /// Total number of visible matches on the page.
  final int total;

  const BrowserFindInPageResult({
    required this.current,
    required this.total,
  });

  static const BrowserFindInPageResult empty = BrowserFindInPageResult(
    current: 0,
    total: 0,
  );

  bool get hasMatches => total > 0 && current > 0;

  /// Parses raw return payloads from `WebViewController.runJavaScriptReturningResult`.
  ///
  /// Handles `Map` payloads as well as raw or double-encoded JSON strings from
  /// Android/iOS platform WebView channels.
  static BrowserFindInPageResult? tryParseJsResult(Object? rawResult) {
    if (rawResult == null) return null;
    dynamic decoded = rawResult;
    if (decoded is String) {
      var trimmed = decoded.trim();
      if (trimmed.isEmpty || trimmed == 'null' || trimmed == 'undefined') {
        return null;
      }
      try {
        decoded = jsonDecode(trimmed);
        if (decoded is String) {
          final inner = decoded.trim();
          if (inner.isEmpty || inner == 'null' || inner == 'undefined') {
            return null;
          }
          decoded = jsonDecode(inner);
        }
      } catch (_) {
        return null;
      }
    }
    if (decoded is! Map) return null;

    final int total = _parseInt(decoded['total']).clamp(0, 999999);
    int current = _parseInt(decoded['current']).clamp(0, total);
    if (total > 0 && current <= 0) {
      current = 1;
    } else if (total == 0) {
      current = 0;
    }
    return BrowserFindInPageResult(current: current, total: total);
  }

  static int _parseInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrowserFindInPageResult &&
          current == other.current &&
          total == other.total;

  @override
  int get hashCode => Object.hash(current, total);

  @override
  String toString() =>
      'BrowserFindInPageResult(current: $current, total: $total)';
}

/// Hook signature for executing find-in-page operations (and deterministic widget
/// testing without a platform WebView).
typedef BrowserFindInPageExecutor = Future<BrowserFindInPageResult> Function(
  String query, {
  required bool isStep,
  required bool backwards,
  required bool preserveViewportMatch,
});

/// Idempotent DOM `Range` + CSS Custom Highlight API finder for in-app pages.
abstract final class BrowserFindInPageScript {
  static String buildSearchScript({
    required String query,
    bool preserveViewportMatch = true,
  }) {
    return _wrapCall(
      'search(${jsonEncode(query)}, ${preserveViewportMatch ? 'true' : 'false'})',
    );
  }

  static String buildStepScript({
    required String query,
    required bool backwards,
  }) {
    return _wrapCall(
      'step(${jsonEncode(query)}, ${backwards ? 'true' : 'false'})',
    );
  }

  static String buildClearScript() => _wrapCall('clear()');

  static String _wrapCall(String methodCall) {
    return '''
(function() {
  try {
    if (typeof document === 'undefined' || !document.body) {
      return JSON.stringify({ total: 0, current: 0 });
    }
    if (!window.__theaverFindEngine) {
      window.__theaverFindEngine = (function() {
        var MAX_RANGES = 2500;
        var STYLE_ID = '__theaver_find_highlight_style';
        var FALLBACK_ID = '__theaver_find_fallback_layer';
        var SKIP_TAGS = {
          SCRIPT: 1,
          STYLE: 1,
          NOSCRIPT: 1,
          TEMPLATE: 1,
          HEAD: 1,
          TITLE: 1,
          META: 1,
          LINK: 1,
          SVG: 1,
          CANVAS: 1,
          IFRAME: 1,
          OBJECT: 1,
          AUDIO: 1,
          VIDEO: 1,
          TEXTAREA: 1,
          SELECT: 1,
          INPUT: 1,
          OPTION: 1
        };
        var state = {
          query: '',
          ranges: [],
          activeIndex: -1,
          fallbackScrollBound: false,
          fallbackRaf: 0
        };

        function ensureHighlightStyle() {
          var parent = document.head || document.documentElement;
          if (!parent) return;
          var styleEl = document.getElementById(STYLE_ID);
          if (styleEl) return;
          styleEl = document.createElement('style');
          styleEl.id = STYLE_ID;
          styleEl.textContent =
            '::highlight(theaver-find-all) { background-color: rgba(255, 214, 10, 0.42); color: inherit; } ' +
            '::highlight(theaver-find-active) { background-color: rgba(255, 149, 0, 0.88); color: #000000; }';
          parent.appendChild(styleEl);
        }

        function hasCssHighlightApi() {
          return (
            typeof CSS !== 'undefined' &&
            CSS &&
            CSS.highlights &&
            typeof Highlight === 'function'
          );
        }

        function escapeRegExp(str) {
          return str.replace(/[.*+?^\${}()|[\\]\\\\]/g, '\\\\\$&');
        }

        function getSafeBounds() {
          var vw = (typeof window.innerWidth === 'number' && window.innerWidth > 0)
            ? window.innerWidth
            : (document.documentElement.clientWidth || 0);
          var vh = (typeof window.innerHeight === 'number' && window.innerHeight > 0)
            ? window.innerHeight
            : (document.documentElement.clientHeight || 0);
          var fvh = Number(window.__theaverFlutterVh) || 0;
          var scale = (fvh > 0 && vh > fvh * 1.15) ? (vh / fvh) : 1.0;
          var rawTop = Number(window.__theaverTopClear);
          var rawBottom = Number(window.__theaverBottomClear);
          var topClear = Math.round(
            Math.max(0, isFinite(rawTop) && rawTop > 0 ? rawTop : 110) * scale
          );
          var bottomClear = Math.round(
            Math.max(0, isFinite(rawBottom) && rawBottom > 0 ? rawBottom : 64) * scale
          );
          return { vw: vw, vh: vh, topClear: topClear, bottomClear: bottomClear };
        }

        function isElementHidden(el) {
          if (!el) return true;
          if (el.id === FALLBACK_ID || el.id === STYLE_ID) return true;
          if (SKIP_TAGS[el.tagName]) return true;
          if (el.hidden) return true;
          if (typeof el.getAttribute === 'function' && el.getAttribute('aria-hidden') === 'true') {
            return true;
          }
          if (typeof window.getComputedStyle === 'function') {
            var cs = window.getComputedStyle(el);
            if (cs) {
              if (cs.display === 'none') return true;
              if (cs.visibility === 'hidden' || cs.visibility === 'collapse') return true;
              if (parseFloat(cs.opacity) === 0) return true;
            }
          } else if (el.style) {
            if (el.style.display === 'none' || el.style.visibility === 'hidden') return true;
          }
          return false;
        }

        function isInlineDisplay(el) {
          if (!el || el === document.body) return false;
          var tag = el.tagName;
          if (tag === 'BR' || tag === 'HR') return false;
          var disp = '';
          if (typeof window.getComputedStyle === 'function') {
            var cs = window.getComputedStyle(el);
            disp = cs ? (cs.display || '') : '';
          } else if (el.style && el.style.display) {
            disp = el.style.display;
          } else {
            return (
              tag === 'SPAN' ||
              tag === 'B' ||
              tag === 'STRONG' ||
              tag === 'I' ||
              tag === 'EM' ||
              tag === 'U' ||
              tag === 'S' ||
              tag === 'A' ||
              tag === 'CODE' ||
              tag === 'MARK' ||
              tag === 'SMALL' ||
              tag === 'SUB' ||
              tag === 'SUP' ||
              tag === 'LABEL'
            );
          }
          return (
            disp === 'inline' ||
            disp === 'inline-block' ||
            disp === 'inline-flex' ||
            disp === 'inline-grid' ||
            disp === 'contents' ||
            disp === 'ruby' ||
            disp === 'ruby-text'
          );
        }

        function isRangeVisible(range) {
          if (!range) return false;
          if (typeof range.getClientRects === 'function') {
            var rects = range.getClientRects();
            if (!rects || rects.length === 0) return false;
            for (var i = 0; i < rects.length; i++) {
              var r = rects[i];
              if (r && (r.width > 0 || r.height > 0)) {
                return true;
              }
            }
            return false;
          }
          return true;
        }

        function findSegmentIndex(segments, offset) {
          var lo = 0;
          var hi = segments.length - 1;
          while (lo <= hi) {
            var mid = (lo + hi) >> 1;
            var seg = segments[mid];
            if (offset < seg.start) {
              hi = mid - 1;
            } else if (offset >= seg.end) {
              lo = mid + 1;
            } else {
              return mid;
            }
          }
          return -1;
        }

        function buildHighlightInstance(rangeList) {
          if (typeof Highlight !== 'function') return null;
          var hl = new Highlight();
          if (hl && typeof hl.add === 'function') {
            for (var i = 0; i < rangeList.length; i++) {
              hl.add(rangeList[i]);
            }
            return hl;
          }
          return Highlight.apply ? null : new Highlight();
        }

        function removeFallbackLayer() {
          var layer = document.getElementById(FALLBACK_ID);
          if (layer && layer.parentNode) {
            layer.parentNode.removeChild(layer);
          }
        }

        function renderFallbackLayer() {
          removeFallbackLayer();
          if (!state.ranges.length || !document.documentElement) return;
          var layer = document.createElement('div');
          layer.id = FALLBACK_ID;
          layer.style.position = 'fixed';
          layer.style.left = '0';
          layer.style.top = '0';
          layer.style.right = '0';
          layer.style.bottom = '0';
          layer.style.pointerEvents = 'none';
          layer.style.zIndex = '2147483640';
          layer.style.overflow = 'hidden';

          var activeIdx = state.activeIndex;
          var frag = document.createDocumentFragment ? document.createDocumentFragment() : layer;
          for (var i = 0; i < state.ranges.length; i++) {
            var rng = state.ranges[i];
            var rects = rng.getClientRects ? rng.getClientRects() : [];
            var isActive = (i === activeIdx);
            for (var j = 0; j < rects.length; j++) {
              var rect = rects[j];
              if (!rect || (rect.width <= 0 && rect.height <= 0)) continue;
              var box = document.createElement('div');
              box.style.position = 'fixed';
              box.style.left = rect.left + 'px';
              box.style.top = rect.top + 'px';
              box.style.width = rect.width + 'px';
              box.style.height = rect.height + 'px';
              box.style.borderRadius = '2px';
              box.style.pointerEvents = 'none';
              box.style.backgroundColor = isActive
                ? 'rgba(255, 149, 0, 0.55)'
                : 'rgba(255, 214, 10, 0.35)';
              frag.appendChild(box);
            }
          }
          if (frag !== layer) {
            layer.appendChild(frag);
          }
          (document.body || document.documentElement).appendChild(layer);
        }

        function onFallbackScroll() {
          if (!state.ranges.length || hasCssHighlightApi()) return;
          if (state.fallbackRaf) return;
          var raf = typeof window.requestAnimationFrame === 'function'
            ? window.requestAnimationFrame
            : function(cb) { return setTimeout(cb, 16); };
          state.fallbackRaf = raf(function() {
            state.fallbackRaf = 0;
            if (!state.ranges.length || hasCssHighlightApi()) return;
            renderFallbackLayer();
          });
        }

        function ensureFallbackScrollListener() {
          if (state.fallbackScrollBound) return;
          state.fallbackScrollBound = true;
          window.addEventListener('scroll', onFallbackScroll, { passive: true });
          document.addEventListener('scroll', onFallbackScroll, { passive: true, capture: true });
        }

        function collectRanges(query) {
          var re = new RegExp(escapeRegExp(query), 'gi');
          var ranges = [];
          var segments = [];
          var chunks = [];
          var totalLen = 0;

          function flushRun() {
            if (!segments.length || ranges.length >= MAX_RANGES) {
              segments = [];
              chunks = [];
              totalLen = 0;
              return;
            }
            var text = chunks.join('');
            re.lastIndex = 0;
            var match;
            while ((match = re.exec(text)) !== null) {
              if (!match[0] || match[0].length === 0) {
                re.lastIndex++;
                continue;
              }
              var startOff = match.index;
              var endOff = startOff + match[0].length;
              var sIdx = findSegmentIndex(segments, startOff);
              var eIdx = findSegmentIndex(segments, endOff - 1);
              if (sIdx >= 0 && eIdx >= 0) {
                var sSeg = segments[sIdx];
                var eSeg = segments[eIdx];
                try {
                  var rng = document.createRange();
                  rng.setStart(sSeg.node, startOff - sSeg.start);
                  rng.setEnd(eSeg.node, endOff - eSeg.start);
                  if (isRangeVisible(rng)) {
                    ranges.push(rng);
                    if (ranges.length >= MAX_RANGES) break;
                  }
                } catch (_) {}
              }
            }
            segments = [];
            chunks = [];
            totalLen = 0;
          }

          function walk(node) {
            if (!node || ranges.length >= MAX_RANGES) return;
            if (node.nodeType === 3) {
              var txt = node.nodeValue || '';
              if (txt.length > 0) {
                segments.push({ node: node, start: totalLen, end: totalLen + txt.length });
                chunks.push(txt);
                totalLen += txt.length;
              }
              return;
            }
            if (node.nodeType !== 1) return;
            if (isElementHidden(node)) return;
            var inline = isInlineDisplay(node);
            if (!inline) flushRun();
            var children = node.childNodes || [];
            for (var i = 0; i < children.length; i++) {
              walk(children[i]);
              if (ranges.length >= MAX_RANGES) break;
            }
            if (!inline) flushRun();
          }

          walk(document.body);
          flushRun();
          return ranges;
        }

        function applyHighlights() {
          ensureHighlightStyle();
          if (hasCssHighlightApi()) {
            removeFallbackLayer();
            if (!state.ranges.length) {
              CSS.highlights.delete('theaver-find-all');
              CSS.highlights.delete('theaver-find-active');
              return;
            }
            var allHl = buildHighlightInstance(state.ranges);
            if (allHl) {
              CSS.highlights.set('theaver-find-all', allHl);
            }
            if (state.activeIndex >= 0 && state.activeIndex < state.ranges.length) {
              var activeHl = buildHighlightInstance([state.ranges[state.activeIndex]]);
              if (activeHl) {
                CSS.highlights.set('theaver-find-active', activeHl);
              }
            } else {
              CSS.highlights.delete('theaver-find-active');
            }
          } else {
            ensureFallbackScrollListener();
            renderFallbackLayer();
          }
        }

        function scrollActiveIntoView() {
          if (state.activeIndex < 0 || state.activeIndex >= state.ranges.length) return;
          var rng = state.ranges[state.activeIndex];
          if (!rng || typeof rng.getBoundingClientRect !== 'function') return;
          var rect = rng.getBoundingClientRect();
          if (!rect) return;
          var b = getSafeBounds();
          var vh = b.vh || 800;
          var safeTop = b.topClear + 12;
          var safeBottom = Math.max(safeTop + 48, vh - b.bottomClear - 12);
          if (rect.top >= safeTop && rect.bottom <= safeBottom) return;

          var desiredTop = safeTop + Math.max(12, Math.min(72, (safeBottom - safeTop) * 0.22));
          var delta = rect.top - desiredTop;
          var node = rng.startContainer;
          var cur = node && node.nodeType === 1 ? node : (node ? node.parentElement : null);
          while (cur && cur !== document.body && cur !== document.documentElement) {
            if (Math.abs(delta) < 1) break;
            if (cur.scrollHeight > cur.clientHeight + 2 && typeof window.getComputedStyle === 'function') {
              var oy = window.getComputedStyle(cur).overflowY;
              if (oy === 'auto' || oy === 'scroll' || oy === 'overlay') {
                var prevScrollTop = cur.scrollTop || 0;
                cur.scrollTop = prevScrollTop + delta;
                var moved = (cur.scrollTop || 0) - prevScrollTop;
                delta -= moved;
              }
            }
            cur = cur.parentElement;
          }
          if (Math.abs(delta) >= 1 && typeof window.scrollBy === 'function') {
            window.scrollBy(0, delta);
          }
        }

        function buildOutput() {
          var total = state.ranges.length;
          var current = total > 0 && state.activeIndex >= 0 ? (state.activeIndex + 1) : 0;
          return JSON.stringify({ total: total, current: current });
        }

        function isNodeConnected(node) {
          return !!node && node.isConnected !== false;
        }

        function pickInitialIndex(ranges, prevNode, prevOffset, preserveViewportMatch) {
          if (!ranges.length) return -1;
          if (preserveViewportMatch && isNodeConnected(prevNode)) {
            for (var i = 0; i < ranges.length; i++) {
              if (ranges[i].startContainer === prevNode && ranges[i].startOffset === prevOffset) {
                return i;
              }
            }
          }
          if (preserveViewportMatch) {
            var b = getSafeBounds();
            var safeTop = b.topClear - 4;
            var safeBottom = Math.max(safeTop + 48, (b.vh || 800) - b.bottomClear + 4);
            var firstAtOrBelowTop = -1;
            for (var j = 0; j < ranges.length; j++) {
              if (typeof ranges[j].getBoundingClientRect !== 'function') break;
              var rect = ranges[j].getBoundingClientRect();
              if (!rect) continue;
              if (rect.top >= safeTop && rect.bottom <= safeBottom) {
                return j;
              }
              if (firstAtOrBelowTop < 0 && rect.top >= safeTop) {
                firstAtOrBelowTop = j;
              }
            }
            if (firstAtOrBelowTop >= 0) return firstAtOrBelowTop;
          }
          return 0;
        }

        return {
          search: function(rawQuery, preserveViewportMatch) {
            var clean = String(rawQuery || '').trim();
            if (!clean) {
              return this.clear();
            }
            var prevRange = (state.activeIndex >= 0 && state.activeIndex < state.ranges.length)
              ? state.ranges[state.activeIndex]
              : null;
            var prevNode = prevRange ? prevRange.startContainer : null;
            var prevOffset = prevRange ? prevRange.startOffset : -1;

            var ranges = collectRanges(clean);
            state.query = clean;
            state.ranges = ranges;
            state.activeIndex = pickInitialIndex(
              ranges,
              prevNode,
              prevOffset,
              preserveViewportMatch !== false
            );
            applyHighlights();
            scrollActiveIntoView();
            if (!hasCssHighlightApi() && state.ranges.length > 0) {
              renderFallbackLayer();
            }
            return buildOutput();
          },
          step: function(rawQuery, backwards) {
            var clean = String(rawQuery || '').trim();
            if (!clean) {
              return this.clear();
            }
            var stale =
              state.query !== clean ||
              !state.ranges.length ||
              !isNodeConnected(state.ranges[0].startContainer);
            if (stale) {
              return this.search(clean, false);
            }
            var total = state.ranges.length;
            var delta = backwards ? -1 : 1;
            state.activeIndex = (state.activeIndex + delta + total) % total;
            applyHighlights();
            scrollActiveIntoView();
            if (!hasCssHighlightApi()) {
              renderFallbackLayer();
            }
            return buildOutput();
          },
          clear: function() {
            state.query = '';
            state.ranges = [];
            state.activeIndex = -1;
            if (hasCssHighlightApi()) {
              CSS.highlights.delete('theaver-find-all');
              CSS.highlights.delete('theaver-find-active');
            }
            removeFallbackLayer();
            return JSON.stringify({ total: 0, current: 0 });
          }
        };
      })();
    }
    return window.__theaverFindEngine.$methodCall;
  } catch (e) {
    return JSON.stringify({ total: 0, current: 0 });
  }
})();
''';
  }
}
