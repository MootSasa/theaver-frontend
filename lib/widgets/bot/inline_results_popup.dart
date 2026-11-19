import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../models/theav_theme.dart';
import '../../services/bot_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../utils/blur_utils.dart';

/// Floating Liquid Glass / Material 3 popup displaying inline bot query results
/// above [ChatInputBar] when typing `@bot query`.
///
/// Strictly avoids FadeTransition/Opacity directly around [LiquidGlassLens].
class InlineResultsPopup extends StatefulWidget {
  final String botUsername;
  final String query;
  final BotInlineQueryResponse? response;
  final bool isLoading;
  final bool isLoadingMore;
  final ValueChanged<BotInlineResult> onSelectResult;
  final VoidCallback? onLoadMore;
  final ValueChanged<BotInlineResultsButton>? onTapHeaderButton;
  final VoidCallback? onClose;

  const InlineResultsPopup({
    super.key,
    required this.botUsername,
    required this.query,
    this.response,
    this.isLoading = false,
    this.isLoadingMore = false,
    required this.onSelectResult,
    this.onLoadMore,
    this.onTapHeaderButton,
    this.onClose,
  });

  @override
  State<InlineResultsPopup> createState() => _InlineResultsPopupState();
}

class _InlineResultsPopupState extends State<InlineResultsPopup> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 80 &&
        !widget.isLoadingMore &&
        (widget.response?.nextOffset.isNotEmpty ?? false)) {
      widget.onLoadMore?.call();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ext = theme.extension<TheavThemeExtension>();
    final cs = theme.colorScheme;
    final glassProvider = LiquidGlassProvider.maybeOf(context);
    final glassEnabled = glassProvider?.enabled ?? false;
    final isLite = glassProvider?.isLite ?? false;

    final results = widget.response?.results ?? const <BotInlineResult>[];
    final headerBtn = widget.response?.button;
    final errorCode = widget.response?.errorCode;

    final visualCount = results.where((r) => r.isVisualTile).length;
    final useGrid = results.isNotEmpty && visualCount * 2 >= results.length;

    double targetHeight;
    if (widget.isLoading && results.isEmpty) {
      targetHeight = 96.0;
    } else if (results.isEmpty) {
      targetHeight = headerBtn != null ? 104.0 : 72.0;
    } else if (useGrid) {
      final rows = (results.length / 3).ceil();
      targetHeight = math.min(268.0, (headerBtn != null ? 44.0 : 12.0) + rows * 96.0 + 16.0);
    } else {
      targetHeight = math.min(268.0, (headerBtn != null ? 44.0 : 8.0) + results.length * 60.0 + 16.0);
    }

    final Widget innerContent = SizedBox(
      height: targetHeight,
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          if (headerBtn != null)
            InkWell(
              onTap: () => widget.onTapHeaderButton?.call(headerBtn),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.28),
                      width: 0.7,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    iconoir.AppWindow(
                      width: 15,
                      height: 15,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        headerBtn.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    iconoir.NavArrowRight(
                      width: 15,
                      height: 15,
                      color: cs.primary,
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _buildBody(context, cs, results, useGrid, errorCode),
          ),
        ],
      ),
    );

    Widget surface;
    if (glassEnabled && glassProvider != null) {
      final style = glassProvider.createStyle(
        context: context,
        cornerRadius: 20,
        refractionIndex: 1.1,
        refractionWidth: 24,
        isLiteOverride: isLite,
      );
      surface = Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: targetHeight,
          child: LiquidGlassLens(style: style, child: innerContent),
        ),
      );
    } else {
      surface = Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter.grouped(
            filter: BlurUtils.createDownsampledBlur(15),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              height: targetHeight,
              decoration: BoxDecoration(
                color: ext?.glassSurfaceColor ??
                    cs.surfaceContainerLow.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: ext?.glassBorderColor ??
                      (isDark ? Colors.white12 : Colors.black12),
                  width: 0.8,
                ),
              ),
              child: innerContent,
            ),
          ),
        ),
      );
    }

    return Material(type: MaterialType.transparency, child: surface);
  }

  Widget _buildBody(
    BuildContext context,
    ColorScheme cs,
    List<BotInlineResult> results,
    bool useGrid,
    String? errorCode,
  ) {
    if (widget.isLoading && results.isEmpty) {
      return Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
            ),
            const SizedBox(width: 10),
            Text(
              '@${widget.botUsername}...',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    if (results.isEmpty) {
      final emptyMsg = errorCode == 'BOT_INLINE_DISABLED'
          ? 'У @${widget.botUsername} отключён inline-режим'
          : 'Нет результатов от @${widget.botUsername}';
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            emptyMsg,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    if (useGrid) {
      return GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: 1.0,
        ),
        itemCount: results.length,
        itemBuilder: (ctx, idx) {
          final item = results[idx];
          final preview = item.previewImageUrl;
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => widget.onSelectResult(item),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: cs.surfaceContainerHighest,
                    child: preview != null
                        ? Image.network(
                            preview,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: iconoir.MediaImage(
                                width: 24,
                                height: 24,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              item.displayTitle,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, color: cs.onSurface),
                            ),
                          ),
                  ),
                  if (item.type == 'gif' || item.type == 'mpeg4_gif')
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'GIF',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: results.length + (widget.isLoadingMore ? 1 : 0),
      separatorBuilder: (_, __) => Divider(
        height: 1,
        indent: 14,
        endIndent: 14,
        color: cs.outlineVariant.withValues(alpha: 0.2),
      ),
      itemBuilder: (ctx, idx) {
        if (idx >= results.length) {
          return const Padding(
            padding: EdgeInsets.all(10),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final item = results[idx];
        final preview = item.previewImageUrl;
        return InkWell(
          onTap: () => widget.onSelectResult(item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                if (preview != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      preview,
                      width: 42,
                      height: 42,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholderAvatar(cs, item),
                    ),
                  ),
                  const SizedBox(width: 10),
                ] else ...[
                  _placeholderAvatar(cs, item),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      if (item.displaySubtitle.isNotEmpty)
                        Text(
                          item.displaySubtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _placeholderAvatar(ColorScheme cs, BotInlineResult item) {
    final trimmedTitle = item.displayTitle.trim();
    final letter = trimmedTitle.isNotEmpty
        ? String.fromCharCode(trimmedTitle.runes.first).toUpperCase()
        : 'B';
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: cs.primary,
        ),
      ),
    );
  }
}

/// Shared debounced controller for `@bot query` inline mode across DM and Group chats.
class InlineQueryController extends ChangeNotifier {
  Timer? _debounce;
  int _requestSeq = 0;
  bool _disposed = false;

  String? activeBotUsername;
  String query = '';
  BotInlineQueryResponse? response;
  bool isLoading = false;
  bool isLoadingMore = false;

  bool get isActive => activeBotUsername != null;

  void onTextChanged(
    String text, {
    required String chatId,
    String chatType = 'private',
  }) {
    final parsed = BotService.parseInlineBotInput(text);
    if (parsed == null) {
      if (isActive || response != null || isLoading) {
        clear();
      }
      return;
    }

    final changed = activeBotUsername?.toLowerCase() !=
            parsed.botUsername.toLowerCase() ||
        query != parsed.query;
    if (!changed && (response != null || isLoading)) {
      return;
    }

    activeBotUsername = parsed.botUsername;
    query = parsed.query;
    isLoading = true;
    isLoadingMore = false;
    response = null;
    notifyListeners();

    _debounce?.cancel();
    final seq = ++_requestSeq;
    _debounce = Timer(const Duration(milliseconds: 320), () async {
      final res = await BotService.queryInlineBotDetailed(
        botId: parsed.botUsername,
        query: parsed.query,
        chatId: chatId,
        chatType: chatType,
      );
      if (_disposed || seq != _requestSeq) return;
      response = res;
      isLoading = false;
      notifyListeners();
    });
  }

  Future<void> loadMore({
    required String chatId,
    String chatType = 'private',
  }) async {
    final bot = activeBotUsername;
    final nextOff = response?.nextOffset ?? '';
    if (bot == null || nextOff.isEmpty || isLoadingMore) return;

    isLoadingMore = true;
    notifyListeners();
    final seq = _requestSeq;
    final more = await BotService.queryInlineBotDetailed(
      botId: bot,
      query: query,
      chatId: chatId,
      chatType: chatType,
      offset: nextOff,
    );
    if (_disposed || seq != _requestSeq) return;
    if (more != null && response != null) {
      response = BotInlineQueryResponse(
        inlineQueryId: more.inlineQueryId.isNotEmpty
            ? more.inlineQueryId
            : response!.inlineQueryId,
        results: [...response!.results, ...more.results],
        nextOffset: more.nextOffset,
        button: more.button ?? response!.button,
        botId: more.botId.isNotEmpty ? more.botId : response!.botId,
      );
    }
    isLoadingMore = false;
    notifyListeners();
  }

  Future<bool> sendSelectedResult({
    required String chatId,
    required BotInlineResult result,
    String? replyToMessageId,
    int? topicId,
  }) async {
    final targetBot = (response?.botId.isNotEmpty == true)
        ? response!.botId
        : (activeBotUsername ?? '');
    if (targetBot.isEmpty) return false;
    final res = await BotService.sendInlineResult(
      chatId: chatId,
      botId: targetBot,
      result: result,
      query: query,
      inlineQueryId: response?.inlineQueryId,
      replyToMessageId: replyToMessageId,
      topicId: topicId,
    );
    return res['success'] == true;
  }

  void clear() {
    _debounce?.cancel();
    _requestSeq++;
    activeBotUsername = null;
    query = '';
    response = null;
    isLoading = false;
    isLoadingMore = false;
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
