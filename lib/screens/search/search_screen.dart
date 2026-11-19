import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../services/search_service.dart';
import '../../services/chat_service.dart';
import '../../services/community_service.dart';
import '../../services/groups_channels_parity_service.dart';
import '../../l10n/app_localizations.dart';
import '../../models/profile_customization.dart';
import '../../services/peer_customization_cache.dart';
import '../../utils/image_utils.dart';
import '../../widgets/common/peer_badges_widget.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/settings/settings_group.dart';
import '../../widgets/user/avatar_with_status.dart';
import '../../widgets/user/emoji_status_badge.dart';

class SearchScreen extends StatefulWidget {
  final String? initialChatId;
  final String? initialChatName;

  const SearchScreen({
    Key? key,
    this.initialChatId,
    this.initialChatName,
  }) : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  String _searchQuery = '';
  String _selectedFilter = 'all'; // all, chats, users, groups, channels, messages

  UnifiedSearchResult _result = UnifiedSearchResult.empty;
  bool _isLoading = false;
  final Set<String> _joiningPeerIds = {};

  // In-chat search filters
  String? _messageTypeFilter;
  String? _fromUserId;
  String? _fromUserName;
  DateTime? _minDate;
  DateTime? _maxDate;

  bool get _hasActiveInChatFilters =>
      _messageTypeFilter != null ||
      (_fromUserId != null && _fromUserId!.isNotEmpty) ||
      _minDate != null ||
      _maxDate != null;

  @override
  void initState() {
    super.initState();
    if (widget.initialChatId != null) {
      _selectedFilter = 'messages';
    }
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final newQuery = _searchController.text;
    if (newQuery != _searchQuery) {
      setState(() {
        _searchQuery = newQuery;
      });
      _debounce?.cancel();
      final trimmed = _searchQuery.trim();
      final bool allowFilterOnly =
          widget.initialChatId != null && _hasActiveInChatFilters;
      if (trimmed.isEmpty && !allowFilterOnly) {
        setState(() {
          _result = UnifiedSearchResult.empty;
          _isLoading = false;
        });
        return;
      }
      if (trimmed.isNotEmpty) {
        _performLocalSearch(trimmed);
      }
      _debounce = Timer(const Duration(milliseconds: 280), _performSearch);
    }
  }

  Future<void> _performLocalSearch(String q) async {
    final localRes = await SearchService.searchLocal(
      query: q,
      type: widget.initialChatId != null ? 'messages' : 'all',
      chatId: widget.initialChatId,
    );
    if (mounted && _searchQuery.trim() == q) {
      setState(() {
        _result = localRes;
      });
    }
  }

  Future<void> _performSearch() async {
    final q = _searchQuery.trim();
    final bool allowFilterOnly =
        widget.initialChatId != null && _hasActiveInChatFilters;
    if (q.isEmpty && !allowFilterOnly) return;

    setState(() => _isLoading = true);
    try {
      final res = await SearchService.search(
        query: q,
        type: widget.initialChatId != null ? 'messages' : 'all',
        chatId: widget.initialChatId,
        fromUserId: _fromUserId,
        messageType: _messageTypeFilter,
        minDate: _minDate?.toUtc().toIso8601String(),
        maxDate: _maxDate?.toUtc().toIso8601String(),
      );
      if (mounted && _searchQuery.trim() == q) {
        setState(() {
          _result = (q.isEmpty || _hasActiveInChatFilters)
              ? res
              : _result.mergeWithServer(res);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _triggerInChatFilterSearch() {
    _debounce?.cancel();
    if (_searchQuery.trim().isEmpty && !_hasActiveInChatFilters) {
      setState(() {
        _result = UnifiedSearchResult.empty;
        _isLoading = false;
      });
      return;
    }
    _performSearch();
  }

  Future<void> _pickSenderFilter() async {
    final cid = widget.initialChatId;
    if (cid == null || cid.isEmpty) return;
    final page = await GroupsChannelsParityService.getMembersFiltered(
      cid,
      limit: 50,
    );
    if (!mounted) return;
    final pickedId = await showTheavModalSheet<String>(
      context: context,
      title: 'Сообщения от участника',
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
        children: [
          TheavInsetGroup(
            children: [
              TheavListRow(
                leading: const iconoir.Group(width: 20, height: 20),
                title: 'Все участники',
                trailing: TheavCheckCircle(selected: _fromUserId == null),
                onTap: () => Navigator.pop(ctx, ''),
              ),
              for (final member in page.members)
                TheavListRow(
                  leading: AvatarWithStatus(
                    userId: member.id,
                    avatarUrl: member.avatarUrl,
                    name: member.displayName.isNotEmpty
                        ? member.displayName
                        : member.username,
                    radius: 18,
                    isOnline: member.isOnline,
                  ),
                  title: member.displayName.isNotEmpty
                      ? member.displayName
                      : '@${member.username}',
                  subtitle:
                      member.username.isNotEmpty ? '@${member.username}' : null,
                  trailing: TheavCheckCircle(
                    selected: _fromUserId == member.id,
                  ),
                  onTap: () => Navigator.pop(ctx, member.id),
                ),
            ],
          ),
        ],
      ),
    );
    if (!mounted || pickedId == null) return;
    if (pickedId.isEmpty) {
      setState(() {
        _fromUserId = null;
        _fromUserName = null;
      });
    } else {
      final matched = page.members.where((m) => m.id == pickedId).firstOrNull;
      setState(() {
        _fromUserId = pickedId;
        _fromUserName = matched == null
            ? pickedId
            : (matched.displayName.isNotEmpty
                  ? matched.displayName
                  : '@${matched.username}');
      });
    }
    _triggerInChatFilterSearch();
  }

  Future<void> _pickDateRangeFilter() async {
    if (_minDate != null || _maxDate != null) {
      setState(() {
        _minDate = null;
        _maxDate = null;
      });
      _triggerInChatFilterSearch();
      return;
    }
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _minDate != null && _maxDate != null
          ? DateTimeRange(start: _minDate!, end: _maxDate!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 7)),
              end: now,
            ),
    );
    if (!mounted || range == null) return;
    setState(() {
      _minDate = DateTime(
        range.start.year,
        range.start.month,
        range.start.day,
      );
      _maxDate = DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
        23,
        59,
        59,
      );
    });
    _triggerInChatFilterSearch();
  }

  void _insertHashtagPrefix() {
    final text = _searchController.text;
    if (text.trim().isEmpty) {
      _searchController.text = '#';
      _searchController.selection = const TextSelection.collapsed(offset: 1);
      return;
    }
    if (!text.startsWith('#')) {
      final updated = '#$text';
      _searchController.text = updated;
      _searchController.selection = TextSelection.collapsed(
        offset: updated.length,
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _joinPublicPeer(SearchPeer peer) async {
    if (_joiningPeerIds.contains(peer.id)) return;
    setState(() => _joiningPeerIds.add(peer.id));
    try {
      if (peer.type == 'community') {
        final joined = await CommunityService.joinCommunity(peer.id);
        if (!mounted) return;
        if (joined != null) {
          _onPeerTap(peer.copyWith(isMember: true));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось вступить в сообщество')),
          );
        }
        return;
      }
      final res = await ChatService.joinPublicChat(peer.id);
      if (!mounted) return;
      if (res['success'] == true) {
        _onPeerTap(peer.copyWith(isMember: true));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message']?.toString() ?? 'Не удалось вступить')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _joiningPeerIds.remove(peer.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isInChatSearch = widget.initialChatId != null;

    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: isInChatSearch
                ? 'Поиск в чате ${widget.initialChatName ?? ''}...'
                : l10n.translate('search_hint'),
            border: InputBorder.none,
            hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.55)),
          ),
          style: TextStyle(color: onSurface),
          autofocus: true,
        ),
        actions: [
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () => _searchController.clear(),
            ),
        ],
      ),
      body: Column(
        children: [
          if (!isInChatSearch)
            _buildFilterChips(context)
          else
            _buildInChatFilterBar(context),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildInChatFilterBar(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final unselectedBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    const typeChips = <(String?, String)>[
      (null, 'Все'),
      ('photo', 'Фото'),
      ('video', 'Видео'),
      ('file', 'Файлы'),
      ('audio', 'Аудио'),
      ('voice', 'Голосовые'),
      ('links', 'Ссылки'),
    ];

    final String dateLabel = (_minDate != null && _maxDate != null)
        ? '${_minDate!.day}.${_minDate!.month}–${_maxDate!.day}.${_maxDate!.month} ×'
        : 'Дата';
    final bool hasDate = _minDate != null || _maxDate != null;
    final bool hasSender = _fromUserId != null && _fromUserId!.isNotEmpty;

    Widget buildChip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
      Widget? icon,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? primary : unselectedBg,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[icon, const SizedBox(width: 5)],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? Colors.white : onSurface,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        children: [
          for (final (typeKey, label) in typeChips) ...[
            buildChip(
              label: label,
              selected: _messageTypeFilter == typeKey,
              onTap: () {
                setState(() => _messageTypeFilter = typeKey);
                _triggerInChatFilterSearch();
              },
            ),
            const SizedBox(width: 8),
          ],
          buildChip(
            label: hasSender ? '${_fromUserName ?? _fromUserId} ▾' : 'От кого',
            selected: hasSender,
            icon: iconoir.User(
              width: 14,
              height: 14,
              color: hasSender ? Colors.white : onSurface,
            ),
            onTap: _pickSenderFilter,
          ),
          const SizedBox(width: 8),
          buildChip(
            label: dateLabel,
            selected: hasDate,
            icon: iconoir.Calendar(
              width: 14,
              height: 14,
              color: hasDate ? Colors.white : onSurface,
            ),
            onTap: _pickDateRangeFilter,
          ),
          const SizedBox(width: 8),
          buildChip(
            label: '#хэштег',
            selected: _searchQuery.trim().startsWith('#'),
            onTap: _insertHashtagPrefix,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context) {
    const filters = <(String, String)>[
      ('all', 'Все'),
      ('chats', 'Чаты'),
      ('users', 'Люди и боты'),
      ('groups', 'Группы'),
      ('channels', 'Каналы'),
      ('communities', 'Сообщества'),
      ('messages', 'Сообщения'),
    ];
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (key, label) = filters[index];
          final selected = _selectedFilter == key;
          return GestureDetector(
            onTap: () => setState(() => _selectedFilter = key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? primary
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06)),
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = context.l10n;
    final bool isInChatSearch = widget.initialChatId != null;
    if (_searchQuery.trim().isEmpty &&
        !(isInChatSearch && _hasActiveInChatFilters)) {
      return Center(
        child: Text(
          l10n.translate('search_start_typing'),
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    final myPeers = _result.myPeers.where(_matchesPeerFilter).toList();
    final globalPeers = _result.globalPeers.where(_matchesPeerFilter).toList();
    final showMessages =
        _selectedFilter == 'all' || _selectedFilter == 'messages';
    final messages = showMessages ? _result.messages : <SearchResultMessage>[];

    if (myPeers.isEmpty && globalPeers.isEmpty && messages.isEmpty) {
      if (_isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Text(
          l10n.translate('common_nothing_found'),
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    return Column(
      children: [
        if (_isLoading)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              if (myPeers.isNotEmpty)
                SettingsGroup(
                  title: 'МОИ ЧАТЫ',
                  children: myPeers.map((p) => _buildPeerTile(context, p)).toList(),
                ),
              if (globalPeers.isNotEmpty)
                SettingsGroup(
                  title: 'ГЛОБАЛЬНЫЙ ПОИСК',
                  children:
                      globalPeers.map((p) => _buildPeerTile(context, p, isGlobal: true)).toList(),
                ),
              if (messages.isNotEmpty)
                SettingsGroup(
                  title: 'СООБЩЕНИЯ',
                  children: messages.map((m) => _buildMessageTile(context, m)).toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  bool _matchesPeerFilter(SearchPeer peer) {
    switch (_selectedFilter) {
      case 'all':
        return true;
      case 'chats':
        return peer.isMember;
      case 'users':
        return peer.type == 'user';
      case 'groups':
        return peer.type == 'group';
      case 'channels':
        return peer.type == 'channel';
      case 'communities':
        return peer.type == 'community';
      case 'messages':
        return false;
      default:
        return true;
    }
  }

  Widget _buildPeerTile(BuildContext context, SearchPeer peer,
      {bool isGlobal = false}) {
    final validAvatar = getValidAvatarUrl(peer.avatarUrl);
    final canJoin = isGlobal &&
        !peer.isMember &&
        (peer.type == 'group' || peer.type == 'channel' || peer.type == 'community');
    final isJoining = _joiningPeerIds.contains(peer.id);

    final subtitleParts = <String>[];
    if (peer.username.isNotEmpty) {
      subtitleParts.add('@${peer.username}');
    }
    if (peer.type == 'user' && peer.isBot) {
      subtitleParts.add('бот');
    } else if (peer.type == 'community') {
      subtitleParts.add(
        peer.memberCount > 0
            ? 'Сообщество • ${peer.memberCount} участн.'
            : 'Сообщество',
      );
      if (peer.description.isNotEmpty) {
        subtitleParts.add(peer.description);
      }
    } else if (peer.memberCount > 0) {
      subtitleParts.add(
        peer.type == 'channel'
            ? '${peer.memberCount} подписчиков'
            : '${peer.memberCount} участников',
      );
    } else if (peer.description.isNotEmpty) {
      subtitleParts.add(peer.description);
    }

    final PeerCustomization? cust = peer.type == 'user'
        ? (PeerCustomizationCache.instance.getSync(peer.id) ??
            peer.peerCustomization)
        : null;

    return ListTile(
      leading: peer.type == 'user'
          ? AvatarWithStatus(
              userId: peer.id,
              avatarUrl: validAvatar,
              name: peer.title,
              radius: 20,
              decorationOverride: cust?.avatarDecoration,
              showDecoration: true,
              animateDecoration: false,
            )
          : CircleAvatar(
              backgroundColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
              backgroundImage:
                  validAvatar != null ? avatarImageProvider(peer.avatarUrl) : null,
              child: validAvatar == null
                  ? (peer.type == 'channel'
                      ? Icon(Icons.campaign_rounded,
                          color: Theme.of(context).colorScheme.primary)
                      : peer.type == 'community'
                          ? Icon(Icons.hub_rounded,
                              color: Theme.of(context).colorScheme.primary)
                          : peer.type == 'group'
                              ? Icon(Icons.group_rounded,
                                  color: Theme.of(context).colorScheme.primary)
                              : Text(
                                  peer.title.isNotEmpty
                                      ? peer.title[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ))
                  : null,
            ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              peer.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (cust?.activeEmojiStatus != null) ...[
            const SizedBox(width: 4),
            EmojiStatusBadge(
              status: cust!.activeEmojiStatus,
              size: 15,
              interactive: false,
            ),
          ],
          PeerBadgesRow(
            isBot: peer.isBot,
            isVerified: peer.isVerified,
            badge: cust?.visibleBadge,
            interactiveBadge: false,
          ),
        ],
      ),
      subtitle: subtitleParts.isNotEmpty
          ? Text(
              subtitleParts.join(' • '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: canJoin
          ? SizedBox(
              height: 30,
              child: FilledButton.tonal(
                onPressed: isJoining ? null : () => _joinPublicPeer(peer),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  visualDensity: VisualDensity.compact,
                ),
                child: isJoining
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        peer.type == 'channel' ? 'Подписаться' : 'Вступить',
                        style: const TextStyle(fontSize: 12),
                      ),
              ),
            )
          : null,
      onTap: () => _onPeerTap(peer),
    );
  }

  Widget _buildMessageTile(BuildContext context, SearchResultMessage message) {
    final header = message.chatName.isNotEmpty
        ? message.chatName
        : (message.senderName.isNotEmpty ? message.senderName : message.userId);
    final senderPrefix = message.senderName.isNotEmpty &&
            message.senderName != message.chatName
        ? '${message.senderName}: '
        : '';

    return ListTile(
      leading: const iconoir.Message(width: 22, height: 22),
      title: Row(
        children: [
          Expanded(
            child: Text(
              header,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatDate(message.createdAt),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
      subtitle: _buildHighlightedSnippet(
        context,
        '$senderPrefix${message.content}',
        _searchQuery.trim(),
      ),
      onTap: () => Navigator.pop(context, {'type': 'message', 'data': message}),
    );
  }

  Widget _buildHighlightedSnippet(
      BuildContext context, String text, String query) {
    final baseStyle = TextStyle(
      fontSize: 13,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72),
    );
    if (query.isEmpty) {
      return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: baseStyle);
    }
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final matchIndex = lowerText.indexOf(lowerQuery);
    if (matchIndex == -1) {
      return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: baseStyle);
    }
    final primary = Theme.of(context).colorScheme.primary;
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: baseStyle,
        children: [
          if (matchIndex > 0) TextSpan(text: text.substring(0, matchIndex)),
          TextSpan(
            text: text.substring(matchIndex, matchIndex + query.length),
            style: baseStyle.copyWith(
              color: primary,
              fontWeight: FontWeight.w700,
              backgroundColor: primary.withValues(alpha: 0.14),
            ),
          ),
          if (matchIndex + query.length < text.length)
            TextSpan(text: text.substring(matchIndex + query.length)),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return '${l10n.translate('date_today')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return l10n.translate('date_yesterday');
    } else if (difference.inDays < 7) {
      return l10n.translate('date_days_ago').replaceAll('{days}', difference.inDays.toString());
    } else {
      return '${date.day}.${date.month}.${date.year}';
    }
  }

  void _onPeerTap(SearchPeer peer) {
    if (peer.type == 'user') {
      Navigator.pop(context, {'type': 'user', 'data': peer.toUser()});
    } else if (peer.type == 'group') {
      Navigator.pop(context, {'type': 'group', 'data': peer.toGroup()});
    } else if (peer.type == 'channel') {
      Navigator.pop(context, {'type': 'channel', 'data': peer.toChannel()});
    } else if (peer.type == 'community') {
      Navigator.pop(context, {'type': 'community', 'data': peer.toCommunity()});
    }
  }
}
