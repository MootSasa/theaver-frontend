import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:share_plus/share_plus.dart';

import '../../../models/theav_theme.dart';
import '../../../services/chat_service.dart';
import '../../../services/glass_toast_service.dart';
import '../../../services/liquid_glass_provider.dart';
import '../../../utils/haptic_utils.dart';
import '../../../widgets/settings/settings_floating_header.dart';

/// Invite link management screen: primary link actions (copy, share, QR, reset),
/// custom secondary invite links (title, max uses, expiry, approval), and revocation.
class InviteLinksScreen extends StatefulWidget {
  final String chatId;
  final String chatType;
  final String? primaryInviteLink;

  const InviteLinksScreen({
    super.key,
    required this.chatId,
    required this.chatType,
    this.primaryInviteLink,
  });

  @override
  State<InviteLinksScreen> createState() => _InviteLinksScreenState();
}

class _InviteLinksScreenState extends State<InviteLinksScreen> {
  String _primaryLink = '';
  List<InviteLinkItem> _links = [];
  bool _isLoading = true;
  bool _isBusy = false;

  bool get _isChannel => widget.chatType == 'channel';

  @override
  void initState() {
    super.initState();
    _primaryLink = (widget.primaryInviteLink ?? '').trim();
    unawaited(_loadLinks());
  }

  Future<void> _loadLinks() async {
    try {
      final results = await Future.wait([
        ChatService.getInviteLinks(widget.chatId),
        if (_primaryLink.isEmpty)
          ChatService.getGroupSettings(widget.chatId)
        else
          Future.value(const <String, dynamic>{}),
      ]);

      if (!mounted) return;
      final fetchedLinks = results[0] as List<InviteLinkItem>;
      final settingsRes = results[1] as Map<String, dynamic>;

      var resolvedPrimary = _primaryLink;
      if (resolvedPrimary.isEmpty && settingsRes['success'] == true) {
        resolvedPrimary =
            (settingsRes['invite_link'] ?? '').toString().trim();
      }
      if (resolvedPrimary.isEmpty) {
        final active = fetchedLinks.where((l) => l.isActive).toList();
        if (active.isNotEmpty) {
          resolvedPrimary = active.first.link;
        }
      }

      setState(() {
        _links = fetchedLinks;
        _primaryLink = resolvedPrimary;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  InviteLinkItem? get _primaryLinkItem {
    if (_primaryLink.isEmpty) return null;
    return _links.where((l) => l.link == _primaryLink).firstOrNull;
  }

  List<InviteLinkItem> get _activeAdditionalLinks {
    return _links
        .where((l) => l.isActive && l.link != _primaryLink)
        .toList();
  }

  List<InviteLinkItem> get _inactiveLinks {
    return _links.where((l) => !l.isActive).toList();
  }

  void _copyLink(String link) {
    if (link.isEmpty) return;
    HapticUtils.selection();
    Clipboard.setData(ClipboardData(text: link));
    GlassToastService().show(
      context,
      'Ссылка скопирована',
      iconWidget: const iconoir.Copy(width: 18, height: 18),
    );
  }

  Future<void> _shareLink(String link) async {
    if (link.isEmpty) return;
    HapticUtils.tap();
    try {
      await SharePlus.instance.share(ShareParams(text: link));
    } catch (_) {
      _copyLink(link);
    }
  }

  void _showQrBottomSheet(String link, {String? title}) {
    if (link.isEmpty) return;
    HapticUtils.tap();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeExt = Theme.of(context).extension<TheavThemeExtension>();
    final accentColor = themeExt?.palette.primary ??
        (isDark ? const Color(0xFF64B5F6) : const Color(0xFF0088CC));
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.68)
        : const Color(0xFF475569);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SettingsAttachedSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              (title != null && title.isNotEmpty) ? title : 'QR-код ссылки',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isChannel
                  ? 'Отсканируйте QR-код, чтобы открыть канал'
                  : 'Отсканируйте QR-код, чтобы вступить в группу',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: subColor),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: SizedBox(
                width: 210,
                height: 210,
                child: PrettyQrView.data(
                  data: link,
                  errorCorrectLevel: QrErrorCorrectLevel.H,
                  decoration: const PrettyQrDecoration(
                    shape: PrettyQrSmoothSymbol(
                      color: Color(0xFF1C1C1E),
                      roundFactor: 1,
                    ),
                    background: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                link,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: accentColor,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _copyLink(link);
                    },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: iconoir.Copy(
                      width: 18,
                      height: 18,
                      color: accentColor,
                    ),
                    label: const Text('Копировать'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Builder(
                    builder: (_) {
                      final buttonFg = accentColor.computeLuminance() > 0.35
                          ? const Color(0xFF0F172A)
                          : Colors.white;
                      return FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _shareLink(link);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: buttonFg,
                          minimumSize: const Size(0, 46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: iconoir.ShareIos(
                          width: 18,
                          height: 18,
                          color: buttonFg,
                        ),
                        label: const Text('Поделиться'),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resetPrimaryLink() async {
    if (_isBusy) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        title: Text(
          'Сбросить основную ссылку?',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: Text(
          'Текущая ссылка-приглашение перестанет работать, а вместо неё будет создана новая.',
          style: TextStyle(
            color: isDark ? Colors.white70 : const Color(0xFF475569),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Сбросить',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    HapticUtils.tap();
    setState(() => _isBusy = true);

    final oldPrimary = _primaryLinkItem;
    if (oldPrimary != null && oldPrimary.id > 0) {
      await ChatService.updateInviteLink(
        chatId: widget.chatId,
        linkId: oldPrimary.id,
        isRevoked: true,
      );
    }
    final created = await ChatService.createInviteLink(
      chatId: widget.chatId,
      title: '',
    );

    if (!mounted) return;
    setState(() => _isBusy = false);

    if (created != null) {
      setState(() => _primaryLink = created.link);
      GlassToastService().show(context, 'Создана новая основная ссылка');
      await _loadLinks();
    } else {
      GlassToastService().show(context, 'Не удалось сбросить ссылку');
    }
  }

  Future<void> _openCreateLinkSheet() async {
    final created = await showModalBottomSheet<InviteLinkItem?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateInviteLinkSheet(chatId: widget.chatId),
    );

    if (created != null && mounted) {
      GlassToastService().show(context, 'Пригласительная ссылка создана');
      await _loadLinks();
    }
  }

  Future<void> _revokeLink(InviteLinkItem item) async {
    if (_isBusy) return;
    HapticUtils.tap();
    setState(() => _isBusy = true);
    final ok = await ChatService.updateInviteLink(
      chatId: widget.chatId,
      linkId: item.id,
      isRevoked: true,
    );
    if (!mounted) return;
    setState(() => _isBusy = false);
    if (ok) {
      GlassToastService().show(context, 'Ссылка отозвана');
      await _loadLinks();
    } else {
      GlassToastService().show(context, 'Не удалось отозвать ссылку');
    }
  }

  Future<void> _deleteLink(InviteLinkItem item) async {
    if (_isBusy) return;
    HapticUtils.tap();
    setState(() => _isBusy = true);
    final ok = await ChatService.deleteInviteLink(
      chatId: widget.chatId,
      linkId: item.id,
    );
    if (!mounted) return;
    setState(() => _isBusy = false);
    if (ok) {
      if (_primaryLink == item.link) {
        _primaryLink = '';
      }
      GlassToastService().show(context, 'Ссылка удалена');
      await _loadLinks();
    } else {
      GlassToastService().show(context, 'Не удалось удалить ссылку');
    }
  }

  String _describeLinkMeta(InviteLinkItem item) {
    final parts = <String>[];
    if (item.maxUses > 0) {
      parts.add('${item.uses}/${item.maxUses} вступлений');
    } else if (item.uses > 0) {
      parts.add('${item.uses} вступлений');
    } else {
      parts.add('Не использовалась');
    }
    if (item.isRevoked) {
      parts.add('Отозвана');
    } else if (item.isExpired) {
      parts.add('Истекла');
    } else if (item.isLimitReached) {
      parts.add('Лимит исчерпан');
    } else if (item.expiresAt != null) {
      final dt = item.expiresAt!.toLocal();
      final d = dt.day.toString().padLeft(2, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      parts.add('до $d.$m $hh:$mm');
    }
    if (item.requiresApproval) {
      parts.add('По заявкам');
    }
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeExt = theme.extension<TheavThemeExtension>();
    final glassProvider = maybeLiquidGlassProvider(context);
    final accentColor = themeExt?.palette.primary ??
        (isDark ? const Color(0xFF64B5F6) : const Color(0xFF0088CC));
    final bgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF5F5F7);
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.68)
        : const Color(0xFF475569);
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);

    final activeAdditional = _activeAdditionalLinks;
    final inactive = _inactiveLinks;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _primaryLink);
      },
      child: SettingsFloatingScaffold(
        title: 'Пригласительные ссылки',
        backgroundColor: bgColor,
        onBack: () => Navigator.pop(context, _primaryLink),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            SettingsFloatingHeader.topClearanceOf(context) + 12,
            16,
            36,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 14, bottom: 8),
              child: Text(
                'ОСНОВНАЯ ССЫЛКА',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: subColor,
                ),
              ),
            ),
            _buildPrimaryLinkCard(
              context,
              glassProvider: glassProvider,
              isDark: isDark,
              accentColor: accentColor,
              textColor: textColor,
              subColor: subColor,
            ),
            const SizedBox(height: 18),
            _buildSurfaceCard(
              context,
              glassProvider: glassProvider,
              isDark: isDark,
              child: ListTile(
                minTileHeight: 54,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: iconoir.Plus(
                    width: 20,
                    height: 20,
                    color: accentColor,
                  ),
                ),
                title: Text(
                  'Создать новую ссылку',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
                subtitle: Text(
                  'С ограничением по времени, количеству или заявкам',
                  style: TextStyle(fontSize: 12.5, color: subColor),
                ),
                onTap: _isBusy ? null : _openCreateLinkSheet,
              ),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (activeAdditional.isNotEmpty) ...[
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.only(left: 14, bottom: 8),
                  child: Text(
                    'ДОПОЛНИТЕЛЬНЫЕ ССЫЛКИ',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      color: subColor,
                    ),
                  ),
                ),
                _buildLinksListCard(
                  context,
                  items: activeAdditional,
                  glassProvider: glassProvider,
                  isDark: isDark,
                  accentColor: accentColor,
                  textColor: textColor,
                  subColor: subColor,
                  dividerColor: dividerColor,
                  allowRevoke: true,
                ),
              ],
              if (inactive.isNotEmpty) ...[
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.only(left: 14, bottom: 8),
                  child: Text(
                    'ОТОЗВАННЫЕ И ИСТЁКШИЕ',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      color: subColor,
                    ),
                  ),
                ),
                _buildLinksListCard(
                  context,
                  items: inactive,
                  glassProvider: glassProvider,
                  isDark: isDark,
                  accentColor: accentColor,
                  textColor: textColor,
                  subColor: subColor,
                  dividerColor: dividerColor,
                  allowRevoke: false,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryLinkCard(
    BuildContext context, {
    required LiquidGlassProvider? glassProvider,
    required bool isDark,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
  }) {
    final hasLink = _primaryLink.isNotEmpty;
    final primaryItem = _primaryLinkItem;

    return _buildSurfaceCard(
      context,
      glassProvider: glassProvider,
      isDark: isDark,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  iconoir.Link(width: 18, height: 18, color: accentColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasLink ? _primaryLink : 'Основная ссылка не создана',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: hasLink ? textColor : subColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (primaryItem != null) ...[
              const SizedBox(height: 8),
              Text(
                'Использований: ${primaryItem.uses}',
                style: TextStyle(fontSize: 12.5, color: subColor),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                _primaryActionBtn(
                  icon: iconoir.Copy(width: 18, height: 18, color: accentColor),
                  label: 'Копировать',
                  textColor: textColor,
                  accentColor: accentColor,
                  onTap: hasLink ? () => _copyLink(_primaryLink) : null,
                ),
                const SizedBox(width: 8),
                _primaryActionBtn(
                  icon: iconoir.ShareIos(
                    width: 18,
                    height: 18,
                    color: accentColor,
                  ),
                  label: 'Поделиться',
                  textColor: textColor,
                  accentColor: accentColor,
                  onTap: hasLink ? () => _shareLink(_primaryLink) : null,
                ),
                const SizedBox(width: 8),
                _primaryActionBtn(
                  icon: iconoir.QrCode(
                    width: 18,
                    height: 18,
                    color: accentColor,
                  ),
                  label: 'QR-код',
                  textColor: textColor,
                  accentColor: accentColor,
                  onTap: hasLink
                      ? () => _showQrBottomSheet(_primaryLink)
                      : null,
                ),
                const SizedBox(width: 8),
                _primaryActionBtn(
                  icon: const iconoir.RefreshDouble(
                    width: 18,
                    height: 18,
                    color: Colors.redAccent,
                  ),
                  label: 'Сбросить',
                  textColor: Colors.redAccent,
                  accentColor: Colors.redAccent,
                  onTap: _isBusy ? null : _resetPrimaryLink,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _primaryActionBtn({
    required Widget icon,
    required String label,
    required Color textColor,
    required Color accentColor,
    required VoidCallback? onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLinksListCard(
    BuildContext context, {
    required List<InviteLinkItem> items,
    required LiquidGlassProvider? glassProvider,
    required bool isDark,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
    required Color dividerColor,
    required bool allowRevoke,
  }) {
    return _buildSurfaceCard(
      context,
      glassProvider: glassProvider,
      isDark: isDark,
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            ListTile(
              minTileHeight: 62,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (items[i].isActive ? accentColor : subColor)
                      .withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: iconoir.Link(
                  width: 19,
                  height: 19,
                  color: items[i].isActive ? accentColor : subColor,
                ),
              ),
              title: Text(
                items[i].title.isNotEmpty ? items[i].title : items[i].link,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              subtitle: Text(
                items[i].title.isNotEmpty
                    ? '${items[i].link}\n${_describeLinkMeta(items[i])}'
                    : _describeLinkMeta(items[i]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: subColor),
              ),
              trailing: PopupMenuButton<String>(
                icon: iconoir.MoreVert(width: 20, height: 20, color: subColor),
                onSelected: (action) {
                  switch (action) {
                    case 'copy':
                      _copyLink(items[i].link);
                      break;
                    case 'share':
                      _shareLink(items[i].link);
                      break;
                    case 'qr':
                      _showQrBottomSheet(
                        items[i].link,
                        title: items[i].title,
                      );
                      break;
                    case 'revoke':
                      _revokeLink(items[i]);
                      break;
                    case 'delete':
                      _deleteLink(items[i]);
                      break;
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'copy',
                    child: Text('Копировать'),
                  ),
                  const PopupMenuItem(
                    value: 'share',
                    child: Text('Поделиться'),
                  ),
                  const PopupMenuItem(
                    value: 'qr',
                    child: Text('QR-код'),
                  ),
                  if (allowRevoke)
                    const PopupMenuItem(
                      value: 'revoke',
                      child: Text('Отозвать'),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Удалить',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
              onTap: () => _copyLink(items[i].link),
            ),
            if (i < items.length - 1)
              Divider(height: 1, indent: 68, color: dividerColor),
          ],
        ],
      ),
    );
  }

  Widget _buildSurfaceCard(
    BuildContext context, {
    required LiquidGlassProvider? glassProvider,
    required bool isDark,
    required Widget child,
  }) {
    if ((glassProvider?.enabled ?? false) && glassProvider != null) {
      final style = glassProvider.createStyle(
        context: context,
        shape: const LiquidGlassShape.continuousRoundedRectangle(
          cornerRadius: 20,
        ),
      );
      return LiquidGlassLens(
        style: style,
        child: Container(
          decoration: isDark
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                ),
          child: Material(type: MaterialType.transparency, child: child),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

class _CreateInviteLinkSheet extends StatefulWidget {
  final String chatId;

  const _CreateInviteLinkSheet({required this.chatId});

  @override
  State<_CreateInviteLinkSheet> createState() => _CreateInviteLinkSheetState();
}

class _CreateInviteLinkSheetState extends State<_CreateInviteLinkSheet> {
  static final List<({String label, Duration? duration})> _expiryOptions = [
    (label: 'Без срока', duration: null),
    (label: '1 час', duration: const Duration(hours: 1)),
    (label: '1 день', duration: const Duration(days: 1)),
    (label: '1 неделя', duration: const Duration(days: 7)),
    (label: '1 месяц', duration: const Duration(days: 30)),
  ];
  static const List<int> _usesOptions = [0, 1, 10, 50, 100];

  final TextEditingController _titleController = TextEditingController();
  Duration? _selectedExpiry;
  int _selectedMaxUses = 0;
  bool _requiresApproval = false;
  bool _creating = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_creating) return;
    setState(() => _creating = true);
    final expiresAt =
        _selectedExpiry != null ? DateTime.now().add(_selectedExpiry!) : null;
    final item = await ChatService.createInviteLink(
      chatId: widget.chatId,
      title: _titleController.text.trim(),
      maxUses: _selectedMaxUses,
      expiresAt: expiresAt,
      requiresApproval: _requiresApproval,
    );
    if (mounted) {
      Navigator.pop(context, item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeExt = Theme.of(context).extension<TheavThemeExtension>();
    final accentColor = themeExt?.palette.primary ??
        (isDark ? const Color(0xFF64B5F6) : const Color(0xFF0088CC));
    final buttonFg = accentColor.computeLuminance() > 0.35
        ? const Color(0xFF0F172A)
        : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.68)
        : const Color(0xFF475569);

    return SettingsAttachedSheet(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Новая ссылка-приглашение',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                maxLength: 64,
                style: TextStyle(color: textColor, fontSize: 15),
                decoration: InputDecoration(
                  labelText: 'Название (необязательно)',
                  hintText: 'Например: Для подписчиков',
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'СРОК ДЕЙСТВИЯ',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: subColor,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final opt in _expiryOptions)
                    ChoiceChip(
                      label: Text(opt.label),
                      selected: _selectedExpiry == opt.duration,
                      onSelected: (_) =>
                          setState(() => _selectedExpiry = opt.duration),
                      selectedColor: accentColor.withValues(alpha: 0.22),
                      labelStyle: TextStyle(
                        color: _selectedExpiry == opt.duration
                            ? accentColor
                            : textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'ЛИМИТ ИСПОЛЬЗОВАНИЙ',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: subColor,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final u in _usesOptions)
                    ChoiceChip(
                      label: Text(u == 0 ? 'Без лимита' : '$u'),
                      selected: _selectedMaxUses == u,
                      onSelected: (_) => setState(() => _selectedMaxUses = u),
                      selectedColor: accentColor.withValues(alpha: 0.22),
                      labelStyle: TextStyle(
                        color: _selectedMaxUses == u ? accentColor : textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                minTileHeight: 48,
                title: Text(
                  'Заявки на вступление',
                  style: TextStyle(color: textColor, fontSize: 15),
                ),
                subtitle: Text(
                  'Администраторы должны одобрить заявку',
                  style: TextStyle(color: subColor, fontSize: 12.5),
                ),
                trailing: Switch.adaptive(
                  value: _requiresApproval,
                  activeThumbColor: accentColor,
                  onChanged: (v) => setState(() => _requiresApproval = v),
                ),
                onTap: () =>
                    setState(() => _requiresApproval = !_requiresApproval),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _creating ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: buttonFg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _creating
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: buttonFg,
                          ),
                        )
                      : const Text(
                          'Создать ссылку',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
