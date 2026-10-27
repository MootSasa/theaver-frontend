import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../l10n/app_localizations.dart';
import '../../services/chat_service.dart';
import '../../services/link_metadata_service.dart';
import '../../utils/entity_parser.dart';
import '../../utils/haptic_utils.dart';

/// Floating Link Preview Configuration Bar above the chat input field.
///
/// Gives the user full Telegram-like control over:
/// 1. Preview position (above or below text)
/// 2. Media size (large banner vs compact thumbnail)
/// 3. Selecting which URL to preview when multiple exist
/// 4. Disabling/removing the preview entirely
class LinkPreviewInputBar extends StatefulWidget {
  final LinkPreviewOptions options;
  final List<String> detectedUrls;
  final ValueChanged<LinkPreviewOptions> onOptionsChanged;
  final VoidCallback onRemove;

  const LinkPreviewInputBar({
    Key? key,
    required this.options,
    required this.detectedUrls,
    required this.onOptionsChanged,
    required this.onRemove,
  }) : super(key: key);

  @override
  State<LinkPreviewInputBar> createState() => _LinkPreviewInputBarState();
}

class _LinkPreviewInputBarState extends State<LinkPreviewInputBar> {
  LinkMetadata? _metadata;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  @override
  void didUpdateWidget(covariant LinkPreviewInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.url != widget.options.url ||
        oldWidget.detectedUrls != widget.detectedUrls) {
      _loadMetadata();
    }
  }

  String get _activeUrl =>
      widget.options.url ?? (widget.detectedUrls.isNotEmpty ? widget.detectedUrls.first : '');

  void _loadMetadata() {
    final url = _activeUrl;
    if (url.isEmpty) return;

    final cached = LinkMetadataService.instance.getCached(url);
    if (cached != null) {
      _metadata = cached;
    } else {
      LinkMetadataService.instance.fetchMetadata(url).then((meta) {
        if (mounted && meta != null && _activeUrl == url) {
          setState(() {
            _metadata = meta;
          });
        }
      });
    }
  }

  String _formatUrlDomain(String url) {
    try {
      final clean = EntityParser.cleanUrl(url);
      final uri = Uri.parse(clean);
      return uri.host.replaceFirst(RegExp(r'^www\.'), '');
    } catch (_) {
      return url;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    final activeUrl = _activeUrl;
    final domain = _formatUrlDomain(activeUrl);
    final thumbUrl = _metadata?.imageUrl;

    final bgColor = isDark
        ? const Color(0xFF1E293B).withValues(alpha: 0.95)
        : Colors.white.withValues(alpha: 0.95);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (thumbUrl != null && thumbUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: thumbUrl,
                    width: 20,
                    height: 20,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => iconoir.Link(
                      color: primaryColor,
                      width: 16,
                      height: 16,
                    ),
                    errorWidget: (_, __, ___) => iconoir.Link(
                      color: primaryColor,
                      width: 16,
                      height: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ] else ...[
                iconoir.Link(
                  color: primaryColor,
                  width: 16,
                  height: 16,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  'Превью ссылки: $domain',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
              ),
              if (widget.detectedUrls.length > 1) ...[
                PopupMenuButton<String>(
                  tooltip: 'Выбрать ссылку',
                  icon: iconoir.NavArrowDown(color: primaryColor, width: 20, height: 20),
                  onSelected: (url) {
                    HapticUtils.tap();
                    widget.onOptionsChanged(widget.options.copyWith(url: url));
                  },
                  itemBuilder: (ctx) => widget.detectedUrls.map((u) {
                    return PopupMenuItem<String>(
                      value: u,
                      child: Text(
                        _formatUrlDomain(u),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: u == activeUrl ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              IconButton(
                icon: iconoir.Xmark(
                  width: 18,
                  height: 18,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: context.l10n.translate('link_preview_remove'),
                onPressed: () {
                  HapticUtils.tap();
                  widget.onRemove();
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              // Position toggle
              _buildOptionChip(
                context: context,
                label: widget.options.showAboveText
                    ? context.l10n.translate('link_preview_above')
                    : context.l10n.translate('link_preview_below'),
                icon: widget.options.showAboveText
                    ? Icons.vertical_align_top
                    : Icons.vertical_align_bottom,
                onTap: () {
                  HapticUtils.tap();
                  widget.onOptionsChanged(
                    widget.options.copyWith(showAboveText: !widget.options.showAboveText),
                  );
                },
                theme: theme,
              ),
              const SizedBox(width: 8),
              // Media size toggle
              _buildOptionChip(
                context: context,
                label: widget.options.preferLargeMedia
                    ? context.l10n.translate('link_preview_large')
                    : context.l10n.translate('link_preview_small'),
                icon: widget.options.preferLargeMedia
                    ? Icons.photo_size_select_actual
                    : Icons.crop_original,
                onTap: () {
                  HapticUtils.tap();
                  widget.onOptionsChanged(
                    widget.options.copyWith(preferLargeMedia: !widget.options.preferLargeMedia),
                  );
                },
                theme: theme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOptionChip({
    required BuildContext context,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
