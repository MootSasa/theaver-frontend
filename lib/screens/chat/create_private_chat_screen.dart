import 'package:flutter/material.dart';
import '../../services/search_service.dart';
import '../../services/chat_service.dart';
import '../../services/tiling_layout_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/image_utils.dart';
import 'private_chat_screen.dart';
import '../../utils/swipe_back_route.dart';

class CreatePrivateChatScreen extends StatefulWidget {
  const CreatePrivateChatScreen({Key? key}) : super(key: key);

  @override
  State<CreatePrivateChatScreen> createState() => _CreatePrivateChatScreenState();
}

class _CreatePrivateChatScreenState extends State<CreatePrivateChatScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<SearchResultUser> _users = [];
  bool _isLoading = false;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final newQuery = _searchController.text;
    if (newQuery != _searchQuery) {
      setState(() {
        _searchQuery = newQuery;
      });
      _performSearch();
    }
  }

  Future<void> _performSearch() async {
    if (_searchQuery.isEmpty) {
      setState(() {
        _users = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final users = await SearchService.searchUsers(query: _searchQuery);
      if (mounted) {
        setState(() {
          _users = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _onUserTap(SearchResultUser user) async {
    if (_isCreating) return;

    setState(() => _isCreating = true);

    try {
      // Create or get existing private chat
      final result = await ChatService.createChat(
        chatType: 'private',
        participantIds: [user.id],
      );

      if (mounted) {
        if (result['success'] == true) {
          final chat = result['chat'] as Chat;
          if (TilingLayoutController.instance.isWorkspaceMounted) {
            Navigator.of(context).pop();
            TilingLayoutController.instance.openChatInActiveTile(
              chatId: chat.id,
              chatType: 'private',
              chatName: user.name,
              avatarUrl: user.avatarUrl,
              otherUserId: user.id,
            );
            return;
          }
          Navigator.pushReplacement(
            context,
            SwipeBackPageRoute(
              builder: (_) => PrivateChatScreen(
                chatId: chat.id,
                otherUserName: user.name,
                otherUserAvatar: user.avatarUrl,
                otherUserId: user.id,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'Failed to create chat')),
          );
          setState(() => _isCreating = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('chat_new_private')),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: l10n.translate('search_user_hint'),
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                  ),
                  autofocus: true,
                ),
              ),
              Expanded(
                child: _buildUsersList(),
              ),
            ],
          ),
          if (_isCreating)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUsersList() {
    final l10n = context.l10n;

    if (_searchQuery.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_search,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              l10n.translate('search_user_start_typing'),
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_off,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              l10n.translate('search_no_users').replaceAll('{query}', _searchQuery),
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _users.length,
      itemBuilder: (context, index) {
        final user = _users[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF0088CC),
            backgroundImage: getValidAvatarUrl(user.avatarUrl) != null
                ? avatarImageProvider(user.avatarUrl)
                : null,
            child: getValidAvatarUrl(user.avatarUrl) == null
                ? Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white),
                  )
                : null,
          ),
          title: Text(user.name),
          subtitle: Text('@${user.username}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _isCreating ? null : () => _onUserTap(user),
        );
      },
    );
  }
}
