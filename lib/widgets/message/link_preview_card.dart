import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/glass_toast_service.dart';
import '../../services/link_metadata_service.dart';
import '../../utils/entity_parser.dart';
import '../../utils/haptic_utils.dart';

/// Interactive Link Preview Card Widget.
///
/// Supports large media banner layout vs compact side-thumbnail layout.
/// Automatically fetches Open Graph images, title, and description from website.
/// Tapping navigates to the URL externally.
class LinkPreviewCard extends StatefulWidget {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final bool preferLargeMedia;
  final VoidCallback? onRemove;
  final bool isDark;

  const LinkPreviewCard({
    Key? key,
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.preferLargeMedia = false,
    this.onRemove,
    this.isDark = false,
  }) : super(key: key);

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  LinkMetadata? _metadata;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  @override
  void didUpdateWidget(covariant LinkPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _loadMetadata();
    }
  }

  void _loadMetadata() {
    if (widget.url.isEmpty || EntityParser.isInternalStorageUrl(widget.url)) return;
    final cached = LinkMetadataService.instance.getCached(widget.url);
    if (cached != null) {
      _metadata = cached;
    } else {
      LinkMetadataService.instance.fetchMetadata(widget.url).then((meta) {
        if (mounted && meta != null) {
          setState(() {
            _metadata = meta;
          });
        }
      });
    }
  }

  String get _cleanUrl => EntityParser.normalizeUrl(widget.url);

  String get _domain {
    try {
      final uri = Uri.parse(_cleanUrl);
      if (uri.host.isNotEmpty) {
        return uri.host.replaceFirst(RegExp(r'^www\.'), '').toUpperCase();
      }
      return 'LINK';
    } catch (_) {
      return 'LINK';
    }
  }

  String get _displayTitle {
    if (widget.title != null && widget.title!.isNotEmpty) return widget.title!;
    if (_metadata?.title != null && _metadata!.title!.isNotEmpty) return _metadata!.title!;
    if (_metadata?.siteName != null && _metadata!.siteName!.isNotEmpty) return _metadata!.siteName!;
    try {
      final uri = Uri.parse(_cleanUrl);
      final path = uri.pathSegments.where((s) => s.isNotEmpty).join(' / ');
      return path.isNotEmpty ? path : uri.host.replaceFirst(RegExp(r'^www\.'), '');
    } catch (_) {
      return widget.url;
    }
  }

  String? get _effectiveDescription {
    if (widget.description != null && widget.description!.isNotEmpty) return widget.description;
    return _metadata?.description;
  }

  String? get _effectiveImageUrl {
    if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) return widget.imageUrl;
    return _metadata?.imageUrl;
  }

  Future<void> _handleTap() async {
    HapticUtils.tap();
    try {
      final uri = Uri.parse(_cleanUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        GlassToastService().show(context, 'Не удалось открыть ссылку', icon: Icons.error_outline);
      }
    } catch (e) {
      if (!mounted) return;
      GlassToastService().show(context, 'Ошибка открытия ссылки', icon: Icons.error_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final cardBgColor = widget.isDark
        ? Colors.black.withValues(alpha: 0.25)
        : Colors.black.withValues(alpha: 0.05);

    final imageUrl = _effectiveImageUrl;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: primaryColor,
            width: 3.5,
          ),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _handleTap,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: widget.preferLargeMedia && imageUrl != null
              ? _buildLargeLayout(theme, primaryColor, imageUrl)
              : _buildCompactLayout(theme, primaryColor, imageUrl),
        ),
      ),
    );
  }

  Widget _buildLargeLayout(ThemeData theme, Color primaryColor, String imageUrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            height: 140,
            width: double.infinity,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              height: 140,
              color: Colors.black12,
              child: const Center(child: CupertinoActivityIndicator()),
            ),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: 6),
        _buildTextInfo(theme, primaryColor),
      ],
    );
  }

  Widget _buildCompactLayout(ThemeData theme, Color primaryColor, String? imageUrl) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _buildTextInfo(theme, primaryColor)),
        if (imageUrl != null) ...[
          const SizedBox(width: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                width: 56,
                height: 56,
                color: Colors.black12,
              ),
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTextInfo(ThemeData theme, Color primaryColor) {
    final desc = _effectiveDescription;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _domain,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: primaryColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: widget.isDark ? Colors.white : const Color(0xFF1E293B),
          ),
        ),
        if (desc != null && desc.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            desc,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: widget.isDark ? Colors.white70 : Colors.black54,
              height: 1.25,
            ),
          ),
        ],
      ],
    );
  }
}

