import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../services/search_service.dart';
import '../../services/chat_service.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/image_utils.dart';
import '../../widgets/common/peer_badges_widget.dart';
import '../../widgets/settings/settings_group.dart';

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
      if (_searchQuery.trim().isEmpty) {
        setState(() {
          _result = UnifiedSearchResult.empty;
          _isLoading = false;
        });
        return;
      }
      _debounce = Timer(const Duration(milliseconds: 280), _performSearch);
    }
  }

  Future<void> _performSearch() async {
    final q = _searchQuery.trim();
    if (q.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final res = await SearchService.search(
        query: q,
        type: widget.initialChatId != null ? 'messages' : 'all',
        chatId: widget.initialChatId,
      );
      if (mounted && _searchQuery.trim() == q) {
        setState(() {
          _result = res;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: isInChatSearch
                ? 'Поиск в чате ${widget.initialChatName ?? ''}...'
                : l10n.translate('search_hint'),
            border: InputBorder.none,
            hintStyle: const TextStyle(color: Colors.white70),
          ),
          style: const TextStyle(color: Colors.white),
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
          if (!isInChatSearch) _buildFilterChips(context),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context) {
    final filters = const <(String, String)>[
      ('all', 'Все'),
      ('chats', 'Чаты'),
      ('users', 'Люди и боты'),
      ('groups', 'Группы'),
      ('channels', 'Каналы'),
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
    if (_searchQuery.trim().isEmpty) {
      return Center(
        child: Text(
          l10n.translate('search_start_typing'),
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final myPeers = _result.myPeers.where(_matchesPeerFilter).toList();
    final globalPeers = _result.globalPeers.where(_matchesPeerFilter).toList();
    final showMessages =
        _selectedFilter == 'all' || _selectedFilter == 'messages';
    final messages = showMessages ? _result.messages : <SearchResultMessage>[];

    if (myPeers.isEmpty && globalPeers.isEmpty && messages.isEmpty) {
      return Center(
        child: Text(
          l10n.translate('common_nothing_found'),
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView(
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
        (peer.type == 'group' || peer.type == 'channel');
    final isJoining = _joiningPeerIds.contains(peer.id);

    final subtitleParts = <String>[];
    if (peer.username.isNotEmpty) {
      subtitleParts.add('@${peer.username}');
    }
    if (peer.type == 'user' && peer.isBot) {
      subtitleParts.add('бот');
    } else if (peer.memberCount > 0) {
      subtitleParts.add(
        peer.type == 'channel'
            ? '${peer.memberCount} подписчиков'
            : '${peer.memberCount} участников',
      );
    } else if (peer.description.isNotEmpty) {
      subtitleParts.add(peer.description);
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
        backgroundImage:
            validAvatar != null ? avatarImageProvider(peer.avatarUrl) : null,
        child: validAvatar == null
            ? (peer.type == 'channel'
                ? Icon(Icons.campaign_rounded,
                    color: Theme.of(context).colorScheme.primary)
                : peer.type == 'group'
                    ? Icon(Icons.group_rounded,
                        color: Theme.of(context).colorScheme.primary)
                    : Text(
                        peer.title.isNotEmpty
                            ? peer.title[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
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
          PeerBadgesRow(isBot: peer.isBot, isVerified: peer.isVerified),
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
    }
  }
}
