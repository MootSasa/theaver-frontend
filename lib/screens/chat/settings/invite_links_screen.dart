import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:share_plus/share_plus.dart';

import '../../../services/chat_service.dart';
import '../../../services/glass_toast_service.dart';
import '../../../services/websocket_service.dart';
import '../../../utils/haptic_utils.dart';
import '../../../widgets/design_system/theav_design_system.dart';
import '../../../widgets/settings/settings_floating_header.dart';
import '../../../widgets/user/avatar_with_status.dart';

/// Invite link & join requests management screen: primary link actions,
/// pending join requests queue (live WS updated), custom secondary links,
/// and revocation.
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
  List<ChatJoinRequest> _joinRequests = [];
  StreamSubscription<WebSocketEvent>? _joinRequestsSub;
  bool _isLoading = true;
  bool _isBusy = false;

  bool get _isChannel => widget.chatType == 'channel';

  @override
  void initState() {
    super.initState();
    _primaryLink = (widget.primaryInviteLink ?? '').trim();
    unawaited(_loadLinks());
    _joinRequestsSub = WebSocketService().eventStream.listen((event) {
      if (!mounted) return;
      if (event.type == WebSocketEventType.joinRequestsUpdated &&
          event.data['chat_id']?.toString() == widget.chatId) {
        unawaited(_refreshJoinRequests());
      }
    });
  }

  @override
  void dispose() {
    _joinRequestsSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshJoinRequests() async {
    final requests = await ChatService.getJoinRequests(widget.chatId);
    if (!mounted) return;
    setState(() => _joinRequests = requests);
  }

  Future<void> _loadLinks() async {
    try {
      final results = await Future.wait([
        ChatService.getInviteLinks(widget.chatId),
        if (_primaryLink.isEmpty)
          ChatService.getGroupSettings(widget.chatId)
        else
          Future.value(const <String, dynamic>{}),
        ChatService.getJoinRequests(widget.chatId),
      ]);

      if (!mounted) return;
      final fetchedLinks = results[0] as List<InviteLinkItem>;
      final settingsRes = results[1] as Map<String, dynamic>;
      final fetchedRequests = results[2] as List<ChatJoinRequest>;

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
        _joinRequests = fetchedRequests;
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

  Future<void> _approveRequest(ChatJoinRequest req) async {
    if (_isBusy) return;
    HapticUtils.selection();
    setState(() => _isBusy = true);
    final ok = await ChatService.approveJoinRequest(
      chatId: widget.chatId,
      userId: req.userId,
    );
    if (!mounted) return;
    setState(() {
      _isBusy = false;
      if (ok) {
        _joinRequests.removeWhere((r) => r.userId == req.userId);
      }
    });
    if (ok) {
      GlassToastService().show(context, 'Заявка одобрена');
    } else {
      GlassToastService().showError(context, 'Не удалось одобрить заявку');
    }
  }

  Future<void> _declineRequest(ChatJoinRequest req) async {
    if (_isBusy) return;
    HapticUtils.selection();
    setState(() => _isBusy = true);
    final ok = await ChatService.declineJoinRequest(
      chatId: widget.chatId,
      userId: req.userId,
    );
    if (!mounted) return;
    setState(() {
      _isBusy = false;
      if (ok) {
        _joinRequests.removeWhere((r) => r.userId == req.userId);
      }
    });
    if (ok) {
      GlassToastService().show(context, 'Заявка отклонена');
    } else {
      GlassToastService().showError(context, 'Не удалось отклонить заявку');
    }
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
    final palette = context.theav;

    showTheavModalSheet<void>(
      context: context,
      title: (title != null && title.isNotEmpty) ? title : 'QR-код ссылки',
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isChannel
                  ? 'Отсканируйте QR-код, чтобы открыть канал'
                  : 'Отсканируйте QR-код, чтобы вступить в группу',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: palette.subtext),
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
                      color: Colors.black87,
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
                color: palette.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                link,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: palette.primary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TheavFloatingPillButton(
                    icon: iconoir.Copy(
                      width: 18,
                      height: 18,
                      color: palette.onSurface,
                    ),
                    label: 'Копировать',
                    onTap: () {
                      Navigator.pop(ctx);
                      _copyLink(link);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TheavFloatingPillButton(
                    isPrimary: true,
                    icon: iconoir.ShareIos(
                      width: 18,
                      height: 18,
                      color: palette.onPrimary,
                    ),
                    label: 'Поделиться',
                    onTap: () {
                      Navigator.pop(ctx);
                      _shareLink(link);
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
    final confirmed = await showTheavDialog<bool>(
      context: context,
      title: 'Сбросить основную ссылку?',
      message:
          'Текущая ссылка-приглашение перестанет работать, а вместо неё будет создана новая.',
      actions: const [
        TheavDialogAction<bool>(label: 'Отмена', result: false),
        TheavDialogAction<bool>(
          label: 'Сбросить',
          result: true,
          isDestructive: true,
        ),
      ],
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
      GlassToastService().showError(context, 'Не удалось сбросить ссылку');
    }
  }

  Future<void> _openCreateLinkSheet() async {
    final created = await showTheavModalSheet<InviteLinkItem?>(
      context: context,
      title: 'Новая ссылка-приглашение',
      builder: (_) => _CreateInviteLinkSheetContent(chatId: widget.chatId),
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
      GlassToastService().showError(context, 'Не удалось отозвать ссылку');
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
      GlassToastService().showError(context, 'Не удалось удалить ссылку');
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
    final palette = context.theav;
    final activeAdditional = _activeAdditionalLinks;
    final inactive = _inactiveLinks;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _primaryLink);
      },
      child: SettingsFloatingScaffold(
        title: 'Пригласительные ссылки',
        backgroundColor: palette.background,
        onBack: () => Navigator.pop(context, _primaryLink),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            0,
            SettingsFloatingHeader.topClearanceOf(context) + 12,
            0,
            MediaQuery.paddingOf(context).bottom + 36,
          ),
          children: [
            _buildPrimaryLinkGroup(context, palette: palette),
            const SizedBox(height: 8),
            TheavInsetGroup(
              children: [
                TheavListRow(
                  leading: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: palette.primary.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: iconoir.Plus(
                      width: 18,
                      height: 18,
                      color: palette.primary,
                    ),
                  ),
                  title: 'Создать новую ссылку',
                  subtitle: 'С ограничением по времени, количеству или заявкам',
                  enabled: !_isBusy,
                  onTap: _openCreateLinkSheet,
                ),
              ],
            ),
            if (_joinRequests.isNotEmpty) ...[
              const SizedBox(height: 8),
              TheavInsetGroup(
                header: 'ЗАЯВКИ НА ВСТУПЛЕНИЕ (${_joinRequests.length})',
                children: [
                  for (final req in _joinRequests)
                    TheavListRow(
                      leading: AvatarWithStatus(
                        userId: req.userId,
                        avatarUrl: req.avatarUrl,
                        name: req.displayName,
                        radius: 20,
                      ),
                      title: req.displayName.isNotEmpty
                          ? req.displayName
                          : '@${req.username}',
                      subtitle: req.username.isNotEmpty
                          ? '@${req.username}'
                          : 'Ожидает одобрения',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _isBusy ? null : () => _declineRequest(req),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: palette.error.withValues(alpha: 0.14),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: iconoir.Xmark(
                                width: 17,
                                height: 17,
                                color: palette.error,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _isBusy ? null : () => _approveRequest(req),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: palette.primary,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: iconoir.Check(
                                width: 17,
                                height: 17,
                                color: palette.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (activeAdditional.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildLinksGroup(
                  context,
                  header: 'ДОПОЛНИТЕЛЬНЫЕ ССЫЛКИ',
                  items: activeAdditional,
                  palette: palette,
                  allowRevoke: true,
                ),
              ],
              if (inactive.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildLinksGroup(
                  context,
                  header: 'ОТОЗВАННЫЕ И ИСТЁКШИЕ',
                  items: inactive,
                  palette: palette,
                  allowRevoke: false,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryLinkGroup(
    BuildContext context, {
    required TheavPalette palette,
  }) {
    final hasLink = _primaryLink.isNotEmpty;
    final primaryItem = _primaryLinkItem;

    return TheavInsetGroup(
      header: 'ОСНОВНАЯ ССЫЛКА',
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: palette.onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    iconoir.Link(width: 18, height: 18, color: palette.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        hasLink ? _primaryLink : 'Основная ссылка не создана',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: hasLink ? palette.onSurface : palette.subtext,
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
                  style: TextStyle(fontSize: 12.5, color: palette.subtext),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  _primaryActionBtn(
                    icon: iconoir.Copy(
                      width: 18,
                      height: 18,
                      color: palette.primary,
                    ),
                    label: 'Копировать',
                    textColor: palette.onSurface,
                    accentColor: palette.primary,
                    onTap: hasLink ? () => _copyLink(_primaryLink) : null,
                  ),
                  const SizedBox(width: 8),
                  _primaryActionBtn(
                    icon: iconoir.ShareIos(
                      width: 18,
                      height: 18,
                      color: palette.primary,
                    ),
                    label: 'Поделиться',
                    textColor: palette.onSurface,
                    accentColor: palette.primary,
                    onTap: hasLink ? () => _shareLink(_primaryLink) : null,
                  ),
                  const SizedBox(width: 8),
                  _primaryActionBtn(
                    icon: iconoir.QrCode(
                      width: 18,
                      height: 18,
                      color: palette.primary,
                    ),
                    label: 'QR-код',
                    textColor: palette.onSurface,
                    accentColor: palette.primary,
                    onTap: hasLink
                        ? () => _showQrBottomSheet(_primaryLink)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  _primaryActionBtn(
                    icon: iconoir.RefreshDouble(
                      width: 18,
                      height: 18,
                      color: palette.error,
                    ),
                    label: 'Сбросить',
                    textColor: palette.error,
                    accentColor: palette.error,
                    onTap: _isBusy ? null : _resetPrimaryLink,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
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

  Widget _buildLinksGroup(
    BuildContext context, {
    required String header,
    required List<InviteLinkItem> items,
    required TheavPalette palette,
    required bool allowRevoke,
  }) {
    return TheavInsetGroup(
      header: header,
      dividerIndent: 68,
      children: [
        for (final item in items)
          TheavListRow(
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: (item.isActive ? palette.primary : palette.subtext)
                    .withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: iconoir.Link(
                width: 18,
                height: 18,
                color: item.isActive ? palette.primary : palette.subtext,
              ),
            ),
            title: item.title.isNotEmpty ? item.title : item.link,
            subtitle: item.title.isNotEmpty
                ? '${item.link}\n${_describeLinkMeta(item)}'
                : _describeLinkMeta(item),
            trailing: PopupMenuButton<String>(
              icon: iconoir.MoreVert(
                width: 20,
                height: 20,
                color: palette.subtext,
              ),
              onSelected: (action) {
                switch (action) {
                  case 'copy':
                    _copyLink(item.link);
                    break;
                  case 'share':
                    _shareLink(item.link);
                    break;
                  case 'qr':
                    _showQrBottomSheet(item.link, title: item.title);
                    break;
                  case 'revoke':
                    _revokeLink(item);
                    break;
                  case 'delete':
                    _deleteLink(item);
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
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Удалить',
                    style: TextStyle(color: palette.error),
                  ),
                ),
              ],
            ),
            onTap: () => _copyLink(item.link),
          ),
      ],
    );
  }
}

class _CreateInviteLinkSheetContent extends StatefulWidget {
  final String chatId;

  const _CreateInviteLinkSheetContent({required this.chatId});

  @override
  State<_CreateInviteLinkSheetContent> createState() =>
      _CreateInviteLinkSheetContentState();
}

class _CreateInviteLinkSheetContentState
    extends State<_CreateInviteLinkSheetContent> {
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
    final palette = context.theav;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TheavInsetGroup(
              dividerIndent: 16,
              children: [
                TheavInlineTextField(
                  controller: _titleController,
                  label: 'Название (необязательно)',
                  placeholder: 'Например: Для подписчиков',
                  maxLength: 64,
                ),
                TheavListRow(
                  title: 'Одобрение администратором',
                  subtitle: 'Участники подают заявку на вступление',
                  trailing: TheavSwitch(
                    value: _requiresApproval,
                    onChanged: (v) => setState(() => _requiresApproval = v),
                  ),
                  onTap: () => setState(
                    () => _requiresApproval = !_requiresApproval,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                'СРОК ДЕЙСТВИЯ',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: palette.subtext,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final opt in _expiryOptions)
                    TheavFloatingPillButton(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      label: opt.label,
                      isPrimary: _selectedExpiry == opt.duration,
                      onTap: () =>
                          setState(() => _selectedExpiry = opt.duration),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                'ЛИМИТ ИСПОЛЬЗОВАНИЙ',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: palette.subtext,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final u in _usesOptions)
                    TheavFloatingPillButton(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      label: u == 0 ? 'Без лимита' : '$u',
                      isPrimary: _selectedMaxUses == u,
                      onTap: () => setState(() => _selectedMaxUses = u),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TheavFloatingPillButton(
                isPrimary: true,
                enabled: !_creating,
                label: _creating ? 'Создание...' : 'Создать ссылку',
                onTap: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
