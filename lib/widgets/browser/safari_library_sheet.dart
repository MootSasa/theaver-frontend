import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../services/browser_data_service.dart';
import '../../services/glass_toast_service.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/safari_url_safety.dart';
import '../design_system/theav_design_system.dart';
import 'safari_browser_dialogs.dart';

/// Active tab inside [SafariLibrarySheet].
enum SafariLibraryTab { bookmarks, history }

/// Opens the Safari iOS 26 styled "Закладки и история" modal sheet matching
/// Theaver's browser design system in both Liquid Glass and Material modes.
Future<void> showSafariLibrarySheet(
  BuildContext context, {
  required String currentUrl,
  required String currentTitle,
  required ValueChanged<String> onSelectUrl,
  SafariLibraryTab initialTab = SafariLibraryTab.bookmarks,
}) async {
  await BrowserDataService.instance.ensureLoaded();
  if (!context.mounted) return;

  await showTheavModalSheet<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    maxHeightFactor: 0.84,
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
    builder: (_) => SafariLibrarySheet(
      currentUrl: currentUrl,
      currentTitle: currentTitle,
      onSelectUrl: onSelectUrl,
      initialTab: initialTab,
    ),
  );
}

/// Dual-mode Safari iOS 26 library panel for bookmarks and chronologically
/// grouped browser history, featuring a sliding [TheavSegmentedControl],
/// transparent search bar, smooth horizontal [PageView] tab transition,
/// feathered scroll edges, and borderless [TheavInsetGroup] cards.
class SafariLibrarySheet extends StatefulWidget {
  final String currentUrl;
  final String currentTitle;
  final ValueChanged<String> onSelectUrl;
  final SafariLibraryTab initialTab;

  const SafariLibrarySheet({
    super.key,
    required this.currentUrl,
    required this.currentTitle,
    required this.onSelectUrl,
    this.initialTab = SafariLibraryTab.bookmarks,
  });

  @override
  State<SafariLibrarySheet> createState() => _SafariLibrarySheetState();
}

class _SafariLibrarySheetState extends State<SafariLibrarySheet> {
  static const List<String> _kMonthsRu = <String>[
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];

  late SafariLibraryTab _activeTab;
  late final PageController _pageController;
  late final TextEditingController _searchCtrl;
  final ScrollController _bookmarksScrollCtrl = ScrollController();
  final ScrollController _historyScrollCtrl = ScrollController();
  String _searchQuery = '';
  int? _programmaticTargetPage;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    _pageController = PageController(initialPage: widget.initialTab.index);
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchCtrl.dispose();
    _bookmarksScrollCtrl.dispose();
    _historyScrollCtrl.dispose();
    super.dispose();
  }

  void _selectTab(SafariLibraryTab next) {
    if (_activeTab == next) return;
    setState(() {
      _activeTab = next;
      _programmaticTargetPage = next.index;
    });
    if (!_pageController.hasClients) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _pageController.jumpToPage(next.index);
      _programmaticTargetPage = null;
    } else {
      _pageController
          .animateToPage(
            next.index,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
        if (mounted) {
          _programmaticTargetPage = null;
        }
      });
    }
  }

  void _handlePageChanged(int idx) {
    if (idx < 0 || idx >= SafariLibraryTab.values.length) return;
    if (_programmaticTargetPage != null) {
      if (idx == _programmaticTargetPage) {
        _programmaticTargetPage = null;
      }
      return;
    }
    final nextTab = SafariLibraryTab.values[idx];
    if (_activeTab != nextTab) {
      HapticUtils.selection();
      setState(() => _activeTab = nextTab);
    }
  }

  void _clearSearch() {
    HapticUtils.selection();
    _searchCtrl.clear();
    if (_searchQuery.isNotEmpty) {
      setState(() => _searchQuery = '');
    }
  }

  void _selectAndOpen(String url) {
    HapticUtils.tap();
    Navigator.of(context).pop();
    widget.onSelectUrl(url);
  }

  Future<void> _copyEntryUrl(String url) async {
    HapticUtils.selection();
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      GlassToastService().show(
        context,
        'Ссылка скопирована',
        icon: Icons.check_rounded,
      );
    }
  }

  Future<void> _confirmClearHistory() async {
    HapticUtils.tap();
    final bool? confirmed = await showSafariWebAlert<bool>(
      context: context,
      dialogKey: const ValueKey('safari_clear_history_confirm_dialog'),
      tone: SafariAlertTone.securityWarning,
      iconOverride: Icons.delete_sweep_rounded,
      title: 'Очистить историю и данные?',
      message:
          'История просмотров и файлы cookie встроенного браузера будут удалены. Закладки сохранятся.',
      actions: const [
        SafariAlertAction<bool>(
          label: 'Отмена',
          result: false,
          buttonKey: ValueKey('safari_clear_history_cancel_btn'),
        ),
        SafariAlertAction<bool>(
          label: 'Очистить',
          result: true,
          isDestructive: true,
          buttonKey: ValueKey('safari_clear_history_confirm_btn'),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;
    await BrowserDataService.instance.clearHistoryAndCookies();
    if (mounted) {
      GlassToastService().show(
        context,
        'История браузера очищена',
        icon: Icons.check_rounded,
      );
    }
  }

  bool _matchesQuery(String title, String url, String query) {
    if (query.isEmpty) return true;
    final safety = SafariUrlSafetyAnalyzer.analyzeUrl(url);
    return title.toLowerCase().contains(query) ||
        url.toLowerCase().contains(query) ||
        safety.displayHost.toLowerCase().contains(query);
  }

  String _formatDateHeader(DateTime dt, DateTime nowLocal) {
    final DateTime local = dt.toLocal();
    final DateTime today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final DateTime target = DateTime(local.year, local.month, local.day);
    final int diffDays = today.difference(target).inDays;
    if (diffDays == 0) return 'Сегодня';
    if (diffDays == 1) return 'Вчера';
    final String month = _kMonthsRu[(local.month - 1).clamp(0, 11)];
    if (local.year == nowLocal.year) {
      return '${local.day} $month';
    }
    return '${local.day} $month ${local.year}';
  }

  String _formatTime(DateTime dt) {
    final DateTime local = dt.toLocal();
    final String hh = local.hour.toString().padLeft(2, '0');
    final String mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _formatCompactUrl(String rawUrl, SafariHostSafetyInfo safety) {
    final String baseHost = safety.displayHost.isNotEmpty
        ? safety.displayHost
        : BrowserDataService.extractHost(rawUrl);
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.path.isEmpty || uri.path == '/') {
      return baseHost;
    }
    return '$baseHost${uri.path}';
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final mq = MediaQuery.of(context);
    final double contentHeight = math.min(
      430.0,
      math.max(180.0, mq.size.height * 0.54 - mq.viewInsets.bottom * 0.45),
    );
    final String cleanCurrentUrl = widget.currentUrl.trim();
    final String currentLower = cleanCurrentUrl.toLowerCase();
    final bool canBookmarkCurrent = currentLower.startsWith('http://') ||
        currentLower.startsWith('https://');
    final String query = _searchQuery.trim().toLowerCase();

    return AnimatedBuilder(
      animation: BrowserDataService.instance,
      builder: (context, _) {
        final bookmarks = BrowserDataService.instance.bookmarks;
        final history = BrowserDataService.instance.history;
        final filteredBookmarks = query.isEmpty
            ? bookmarks
            : bookmarks
                .where((b) => _matchesQuery(b.title, b.url, query))
                .toList();
        final filteredHistory = query.isEmpty
            ? history
            : history
                .where((h) => _matchesQuery(h.title, h.url, query))
                .toList();

        final Widget headerRow = Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Tooltip(
                message: 'Закрыть',
                child: GestureDetector(
                  key: const ValueKey('safari_library_close_btn'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticUtils.tap();
                    Navigator.of(context).maybePop();
                  },
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Icon(
                        Icons.close_rounded,
                        size: 22,
                        color: palette.subtext,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Закладки и история',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.onSurface,
                    fontSize: 17.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.25,
                  ),
                ),
              ),
              if (_activeTab == SafariLibraryTab.history &&
                  history.isNotEmpty) ...[
                const SizedBox(width: 8),
                Material(
                  key: const ValueKey('safari_library_clear_history_btn'),
                  color: palette.error.withValues(
                    alpha: style.isDark ? 0.14 : 0.08,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _confirmClearHistory,
                    child: SizedBox(
                      height: 30,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.delete_sweep_rounded,
                              size: 15,
                              color: palette.error,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Очистить',
                              style: TextStyle(
                                color: palette.error,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );

        final Widget segmentedBar = TheavSegmentedControl<SafariLibraryTab>(
          key: const ValueKey('safari_library_segmented_control'),
          height: 40.0,
          options: const [
            TheavSegmentOption(
              value: SafariLibraryTab.bookmarks,
              label: 'Закладки',
              icon: Icon(Icons.bookmarks_rounded),
            ),
            TheavSegmentOption(
              value: SafariLibraryTab.history,
              label: 'История',
              icon: Icon(Icons.history_rounded),
            ),
          ],
          selected: _activeTab,
          onChanged: _selectTab,
          margin: const EdgeInsets.only(top: 2, bottom: 8),
        );

        final Widget searchBar = SizedBox(
          key: const ValueKey('safari_library_search_bar'),
          height: 38.0,
          child: Row(
            children: [
              const SizedBox(width: 6),
              Icon(
                Icons.search_rounded,
                size: 18,
                color: palette.subtext,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const ValueKey('safari_library_search_input'),
                  controller: _searchCtrl,
                  cursorColor: palette.primary,
                  style: TextStyle(
                    color: palette.onSurface,
                    fontSize: 14.5,
                  ),
                  decoration: InputDecoration(
                    hintText: _activeTab == SafariLibraryTab.bookmarks
                        ? 'Поиск по закладкам...'
                        : 'Поиск в истории...',
                    hintStyle: TextStyle(
                      color: palette.subtext.withValues(alpha: 0.78),
                      fontSize: 14.5,
                    ),
                    filled: false,
                    fillColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              if (_searchQuery.isNotEmpty)
                GestureDetector(
                  key: const ValueKey('safari_library_search_clear_btn'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _clearSearch,
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: Center(
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: palette.subtext,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            headerRow,
            segmentedBar,
            searchBar,
            const SizedBox(height: 6),
            Flexible(
              fit: FlexFit.loose,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: contentHeight,
                  minHeight: math.min(200.0, contentHeight),
                ),
                child: SizedBox(
                  height: contentHeight,
                  child: PageView(
                    key: const ValueKey('safari_library_page_view'),
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: _handlePageChanged,
                    children: [
                      _buildBookmarksTab(
                        context,
                        style: style,
                        bookmarks: filteredBookmarks,
                        hasAnyBookmarks: bookmarks.isNotEmpty,
                        query: query,
                        canBookmarkCurrent: canBookmarkCurrent,
                        cleanCurrentUrl: cleanCurrentUrl,
                      ),
                      _buildHistoryTab(
                        context,
                        style: style,
                        entries: filteredHistory,
                        hasAnyHistory: history.isNotEmpty,
                        query: query,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBookmarksTab(
    BuildContext context, {
    required TheavSurfaceStyle style,
    required List<BrowserBookmark> bookmarks,
    required bool hasAnyBookmarks,
    required String query,
    required bool canBookmarkCurrent,
    required String cleanCurrentUrl,
  }) {
    final palette = style.palette;
    final bool showQuickCard = query.isEmpty && canBookmarkCurrent;
    final bool isCurrentSaved =
        canBookmarkCurrent && BrowserDataService.instance.isBookmarked(cleanCurrentUrl);
    final currentSafety = SafariUrlSafetyAnalyzer.analyzeUrl(cleanCurrentUrl);
    final String resolvedCurrentTitle = widget.currentTitle.trim().isNotEmpty
        ? widget.currentTitle.trim()
        : (currentSafety.displayHost.isNotEmpty
            ? currentSafety.displayHost
            : cleanCurrentUrl);

    if (!showQuickCard && bookmarks.isEmpty) {
      return SafariSheetEmptyState(
        icon: query.isNotEmpty
            ? Icons.search_off_rounded
            : Icons.bookmarks_outlined,
        title: query.isNotEmpty ? 'Ничего не найдено' : 'Нет сохранённых закладок',
        subtitle: query.isNotEmpty
            ? 'Попробуйте изменить запрос поиска.'
            : 'Сохраняйте нужные страницы, чтобы открывать их в одно касание.',
        actionLabel: query.isNotEmpty ? 'Сбросить поиск' : null,
        onAction: query.isNotEmpty ? _clearSearch : null,
      );
    }

    final Color cardFill = palette.onSurface.withValues(
      alpha: style.isDark ? 0.06 : 0.04,
    );
    final Color dividerTint = palette.onSurface.withValues(
      alpha: style.isDark ? 0.06 : 0.045,
    );

    return SafariFeatherScrollView(
      controller: _bookmarksScrollCtrl,
      edgeKeyPrefix: 'safari_bookmarks',
      child: ListView(
        controller: _bookmarksScrollCtrl,
        padding: const EdgeInsets.only(top: 6, bottom: 16),
        children: [
          if (showQuickCard) ...[
            Container(
              key: const ValueKey('safari_library_current_page_card'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cardFill,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  SafariDomainMonogramBadge(
                    host: currentSafety.displayHost.isNotEmpty
                        ? currentSafety.displayHost
                        : cleanCurrentUrl,
                    isSecure: currentSafety.securityLevel ==
                        SafariConnectionSecurityLevel.secureHttps,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Текущая страница',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: palette.primary,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          resolvedCurrentTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: palette.onSurface,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          currentSafety.displayHost.isNotEmpty
                              ? currentSafety.displayHost
                              : cleanCurrentUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.subtext,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    key: const ValueKey('safari_library_toggle_current_bookmark_btn'),
                    color: isCurrentSaved
                        ? palette.primary.withValues(
                            alpha: style.isDark ? 0.22 : 0.13,
                          )
                        : palette.primary,
                    borderRadius: BorderRadius.circular(17),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(17),
                      onTap: () {
                        HapticUtils.selection();
                        unawaited(
                          BrowserDataService.instance.toggleBookmark(
                            cleanCurrentUrl,
                            resolvedCurrentTitle,
                          ),
                        );
                      },
                      child: SizedBox(
                        height: 34,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isCurrentSaved
                                    ? Icons.bookmark_added_rounded
                                    : Icons.bookmark_add_rounded,
                                size: 16,
                                color: isCurrentSaved
                                    ? palette.primary
                                    : palette.onPrimary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                isCurrentSaved ? 'Сохранено' : 'Сохранить',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: isCurrentSaved
                                      ? palette.primary
                                      : palette.onPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (bookmarks.isEmpty)
            SafariSheetEmptyState(
              icon: query.isNotEmpty
                  ? Icons.search_off_rounded
                  : Icons.bookmarks_outlined,
              title: hasAnyBookmarks && query.isNotEmpty
                  ? 'Ничего не найдено'
                  : 'Нет сохранённых закладок',
              subtitle: hasAnyBookmarks && query.isNotEmpty
                  ? 'Попробуйте изменить запрос поиска.'
                  : 'Нажмите «Сохранить» выше или звёздочку в меню, чтобы добавить сайт.',
              actionLabel: query.isNotEmpty ? 'Сбросить поиск' : null,
              onAction: query.isNotEmpty ? _clearSearch : null,
            )
          else
            TheavInsetGroup(
              margin: EdgeInsets.zero,
              borderRadius: 20.0,
              dividerIndent: 64.0,
              showBorder: false,
              showShadow: false,
              backgroundColor: cardFill,
              dividerColor: dividerTint,
              header: 'Сохранённые сайты',
              children: [
                for (final item in bookmarks)
                  Dismissible(
                    key: ValueKey('safari_bookmark_dismiss_${item.url}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: palette.error.withValues(alpha: 0.14),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 18),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        color: palette.error,
                        size: 20,
                      ),
                    ),
                    onDismissed: (_) {
                      HapticUtils.selection();
                      unawaited(
                        BrowserDataService.instance.removeBookmark(item.url),
                      );
                    },
                    child: _SafariLibraryEntryRow(
                      title: item.title,
                      subtitle: _formatCompactUrl(
                        item.url,
                        SafariUrlSafetyAnalyzer.analyzeUrl(item.url),
                      ),
                      host: SafariUrlSafetyAnalyzer.analyzeUrl(item.url)
                          .displayHost,
                      isSecure: SafariUrlSafetyAnalyzer.analyzeUrl(item.url)
                              .securityLevel ==
                          SafariConnectionSecurityLevel.secureHttps,
                      isBookmarkedBadge: false,
                      removeButtonKey:
                          ValueKey('safari_bookmark_remove_${item.url}'),
                      removeIcon: Icons.close_rounded,
                      removeTooltip: 'Удалить из закладок',
                      onTap: () => _selectAndOpen(item.url),
                      onLongPress: () => unawaited(_copyEntryUrl(item.url)),
                      onRemove: () {
                        HapticUtils.selection();
                        unawaited(
                          BrowserDataService.instance.removeBookmark(item.url),
                        );
                      },
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(
    BuildContext context, {
    required TheavSurfaceStyle style,
    required List<BrowserHistoryEntry> entries,
    required bool hasAnyHistory,
    required String query,
  }) {
    if (entries.isEmpty) {
      return SafariSheetEmptyState(
        icon: (hasAnyHistory && query.isNotEmpty)
            ? Icons.search_off_rounded
            : Icons.history_rounded,
        title: (hasAnyHistory && query.isNotEmpty)
            ? 'Ничего не найдено'
            : 'История браузера пуста',
        subtitle: (hasAnyHistory && query.isNotEmpty)
            ? 'Попробуйте изменить запрос поиска.'
            : 'Посещённые страницы будут группироваться здесь по дням.',
        actionLabel: (hasAnyHistory && query.isNotEmpty)
            ? 'Сбросить поиск'
            : null,
        onAction: (hasAnyHistory && query.isNotEmpty) ? _clearSearch : null,
      );
    }

    final palette = style.palette;
    final Color cardFill = palette.onSurface.withValues(
      alpha: style.isDark ? 0.06 : 0.04,
    );
    final Color dividerTint = palette.onSurface.withValues(
      alpha: style.isDark ? 0.06 : 0.045,
    );
    final DateTime nowLocal = DateTime.now();
    final List<({String label, List<BrowserHistoryEntry> items})> sections = [];
    String? currentLabel;
    List<BrowserHistoryEntry>? currentBucket;

    for (final entry in entries) {
      final String label = _formatDateHeader(entry.visitedAt, nowLocal);
      if (label != currentLabel || currentBucket == null) {
        currentLabel = label;
        currentBucket = <BrowserHistoryEntry>[];
        sections.add((label: label, items: currentBucket));
      }
      currentBucket.add(entry);
    }

    return SafariFeatherScrollView(
      controller: _historyScrollCtrl,
      edgeKeyPrefix: 'safari_history',
      child: ListView.builder(
        controller: _historyScrollCtrl,
        padding: const EdgeInsets.only(top: 6, bottom: 16),
        itemCount: sections.length,
        itemBuilder: (context, sectionIdx) {
          final section = sections[sectionIdx];
          return TheavInsetGroup(
            margin: EdgeInsets.only(
              bottom: sectionIdx < sections.length - 1 ? 10 : 0,
            ),
            borderRadius: 20.0,
            dividerIndent: 64.0,
            showBorder: false,
            showShadow: false,
            backgroundColor: cardFill,
            dividerColor: dividerTint,
            header: section.label,
            headerTrailing: Text(
              '${section.items.length}',
              style: TextStyle(
                color: palette.subtext,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            children: [
              for (final entry in section.items)
                Dismissible(
                  key: ValueKey(
                    'safari_history_dismiss_${entry.url}_${entry.visitedAt.microsecondsSinceEpoch}',
                  ),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: palette.error.withValues(alpha: 0.14),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 18),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      color: palette.error,
                      size: 20,
                    ),
                  ),
                  onDismissed: (_) {
                    HapticUtils.selection();
                    unawaited(
                      BrowserDataService.instance.removeHistoryEntry(entry),
                    );
                  },
                  child: () {
                    final safety = SafariUrlSafetyAnalyzer.analyzeUrl(entry.url);
                    final String hostLabel =
                        _formatCompactUrl(entry.url, safety);
                    final bool isBookmarked =
                        BrowserDataService.instance.isBookmarked(entry.url);
                    return _SafariLibraryEntryRow(
                      title: entry.title,
                      subtitle: '$hostLabel • ${_formatTime(entry.visitedAt)}',
                      host: safety.displayHost,
                      isSecure: safety.securityLevel ==
                          SafariConnectionSecurityLevel.secureHttps,
                      isBookmarkedBadge: isBookmarked,
                      removeButtonKey: ValueKey(
                        'safari_history_remove_${entry.url}_${entry.visitedAt.microsecondsSinceEpoch}',
                      ),
                      removeIcon: Icons.close_rounded,
                      removeTooltip: 'Удалить из истории',
                      onTap: () => _selectAndOpen(entry.url),
                      onLongPress: () => unawaited(_copyEntryUrl(entry.url)),
                      onRemove: () {
                        HapticUtils.selection();
                        unawaited(
                          BrowserDataService.instance.removeHistoryEntry(entry),
                        );
                      },
                    );
                  }(),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Applies subtle top and bottom alpha feathering via [ShaderMask] together with
/// sibling [LiquidGlassScrollEdge] soft-blur overlays outside scrollables.
class SafariFeatherScrollView extends StatefulWidget {
  final ScrollController controller;
  final String edgeKeyPrefix;
  final bool enableShaderMask;
  final Widget child;

  const SafariFeatherScrollView({
    super.key,
    required this.controller,
    required this.edgeKeyPrefix,
    this.enableShaderMask = true,
    required this.child,
  });

  @override
  State<SafariFeatherScrollView> createState() =>
      _SafariFeatherScrollViewState();
}

class _SafariFeatherScrollViewState extends State<SafariFeatherScrollView> {
  double _topStrength = 0.0;
  double _bottomStrength = 0.0;
  bool _postFrameScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateEdgeStrengths);
    _scheduleEdgeSync();
  }

  @override
  void didUpdateWidget(covariant SafariFeatherScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_updateEdgeStrengths);
      widget.controller.addListener(_updateEdgeStrengths);
    }
    _scheduleEdgeSync();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateEdgeStrengths);
    super.dispose();
  }

  void _scheduleEdgeSync() {
    if (_postFrameScheduled) return;
    _postFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _postFrameScheduled = false;
      if (mounted) _updateEdgeStrengths();
    });
  }

  void _updateEdgeStrengths() {
    if (!widget.controller.hasClients) return;
    final pos = widget.controller.position;
    final double pixels = pos.pixels;
    final double maxExtent = pos.maxScrollExtent;
    final double nextTop =
        maxExtent > 1.0 ? (pixels / 22.0).clamp(0.0, 1.0) : 0.0;
    final double nextBottom = maxExtent > 1.0
        ? ((maxExtent - pixels) / 22.0).clamp(0.0, 1.0)
        : 0.0;
    if ((nextTop - _topStrength).abs() > 0.03 ||
        (nextBottom - _bottomStrength).abs() > 0.03) {
      setState(() {
        _topStrength = nextTop;
        _bottomStrength = nextBottom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final bool allowEdgeBlur = style.allowBlur || style.allowMaterialBlur;
    final Color sheetTint = style.overlayFill;
    final bool needsMask =
        widget.enableShaderMask && (_topStrength > 0.01 || _bottomStrength > 0.01);

    final Widget scrollChild = NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _scheduleEdgeSync();
        return false;
      },
      child: widget.child,
    );

    final Widget maskedContent = needsMask
        ? LayoutBuilder(
            builder: (context, constraints) {
              final double h = constraints.maxHeight.isFinite &&
                      constraints.maxHeight > 1.0
                  ? constraints.maxHeight
                  : 320.0;
              final double topFrac = (24.0 / h).clamp(0.02, 0.22);
              final double bottomFrac = (26.0 / h).clamp(0.02, 0.22);
              return ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: <double>[
                    0.0,
                    topFrac,
                    1.0 - bottomFrac,
                    1.0,
                  ],
                  colors: <Color>[
                    Colors.white.withValues(alpha: 1.0 - _topStrength * 0.85),
                    Colors.white,
                    Colors.white,
                    Colors.white.withValues(alpha: 1.0 - _bottomStrength * 0.85),
                  ],
                ).createShader(bounds),
                child: scrollChild,
              );
            },
          )
        : scrollChild;

    return Stack(
      fit: StackFit.expand,
      children: [
        maskedContent,
        if (_topStrength > 0.02)
          Positioned(
            key: ValueKey('${widget.edgeKeyPrefix}_top_scroll_edge'),
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: LiquidGlassScrollEdge(
                edge: LiquidGlassEdge.top,
                height: 24.0,
                style: LiquidGlassScrollEdgeStyle.soft,
                color: sheetTint.withValues(alpha: 0.22 * _topStrength),
                blur: allowEdgeBlur ? 4.2 * _topStrength : 0.0,
              ),
            ),
          ),
        if (_bottomStrength > 0.02)
          Positioned(
            key: ValueKey('${widget.edgeKeyPrefix}_bottom_scroll_edge'),
            bottom: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: LiquidGlassScrollEdge(
                edge: LiquidGlassEdge.bottom,
                height: 26.0,
                style: LiquidGlassScrollEdgeStyle.soft,
                color: sheetTint.withValues(alpha: 0.24 * _bottomStrength),
                blur: allowEdgeBlur ? 4.4 * _bottomStrength : 0.0,
              ),
            ),
          ),
      ],
    );
  }
}

/// Rounded monogram (or icon) badge matching Safari's domain cards.
class SafariDomainMonogramBadge extends StatelessWidget {
  final String host;
  final bool isSecure;
  final bool showBookmarkBadge;
  final IconData? iconOverride;

  const SafariDomainMonogramBadge({
    super.key,
    required this.host,
    required this.isSecure,
    this.showBookmarkBadge = false,
    this.iconOverride,
  });

  static const List<Color> _kDomainPalette = <Color>[
    Color(0xFF0A84FF),
    Color(0xFF30B0C7),
    Color(0xFF5856D6),
    Color(0xFF34C759),
    Color(0xFFFF9500),
    Color(0xFFAF52DE),
    Color(0xFFFF375F),
    Color(0xFF007AFF),
  ];

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final String clean = host.trim();
    int hash = 0;
    for (final int unit in clean.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    final Color tint =
        isSecure ? _kDomainPalette[hash % _kDomainPalette.length] : palette.error;
    final String letter = clean.isNotEmpty
        ? String.fromCharCode(clean.runes.first).toUpperCase()
        : 'W';

    final Widget box = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: style.isDark ? 0.20 : 0.12),
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: iconOverride != null
          ? Icon(iconOverride, size: 19, color: tint)
          : Text(
              letter,
              style: TextStyle(
                color: tint,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
    );

    if (!showBookmarkBadge) return box;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        box,
        Positioned(
          right: -3,
          bottom: -3,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: palette.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.bookmark_rounded,
              size: 9.5,
              color: palette.onPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _SafariLibraryEntryRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String host;
  final bool isSecure;
  final bool isBookmarkedBadge;
  final Key removeButtonKey;
  final IconData removeIcon;
  final String removeTooltip;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRemove;

  const _SafariLibraryEntryRow({
    required this.title,
    required this.subtitle,
    required this.host,
    required this.isSecure,
    required this.isBookmarkedBadge,
    required this.removeButtonKey,
    required this.removeIcon,
    required this.removeTooltip,
    required this.onTap,
    required this.onLongPress,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;

    return TheavListRow(
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      minHeight: 56.0,
      leading: SafariDomainMonogramBadge(
        host: host,
        isSecure: isSecure,
        showBookmarkBadge: isBookmarkedBadge,
      ),
      titleWidget: Text(
        title.trim().isNotEmpty ? title.trim() : host,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: palette.onSurface,
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
      ),
      subtitleWidget: Row(
        children: [
          Icon(
            isSecure ? Icons.lock_rounded : Icons.warning_amber_rounded,
            size: 11.5,
            color: isSecure ? palette.subtext : palette.error,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.subtext,
                fontSize: 12.2,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
      trailing: Tooltip(
        message: removeTooltip,
        child: GestureDetector(
          key: removeButtonKey,
          behavior: HitTestBehavior.opaque,
          onTap: onRemove,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Center(
              child: Icon(
                removeIcon,
                size: 18,
                color: palette.subtext.withValues(alpha: 0.78),
              ),
            ),
          ),
        ),
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// Centered empty / locked state shared across Safari browser sheets.
class SafariSheetEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionButtonKey;
  final IconData? actionIcon;
  final bool isPrimaryAction;

  const SafariSheetEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    this.actionButtonKey,
    this.actionIcon,
    this.isPrimaryAction = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final Color pillBg = isPrimaryAction
        ? (onAction != null
            ? palette.primary
            : palette.primary.withValues(alpha: 0.65))
        : palette.primary.withValues(
            alpha: style.isDark ? 0.18 : 0.11,
          );
    final Color pillFg = isPrimaryAction ? palette.onPrimary : palette.primary;
    final double pillHeight = isPrimaryAction ? 38.0 : 34.0;
    final double pillRadius = pillHeight / 2.0;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: palette.primary.withValues(
                  alpha: style.isDark ? 0.16 : 0.10,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 24,
                color: palette.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.onSurface,
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.subtext,
                fontSize: 13,
                height: 1.38,
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 14),
              Material(
                key: actionButtonKey,
                color: pillBg,
                borderRadius: BorderRadius.circular(pillRadius),
                child: InkWell(
                  borderRadius: BorderRadius.circular(pillRadius),
                  onTap: onAction,
                  child: SizedBox(
                    height: pillHeight,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isPrimaryAction ? 18 : 14,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (actionIcon != null) ...[
                            Icon(
                              actionIcon,
                              size: 16.5,
                              color: pillFg,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              actionLabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: pillFg,
                                fontSize: isPrimaryAction ? 13.5 : 13.0,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
