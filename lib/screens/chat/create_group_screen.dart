import 'package:flutter/material.dart';
import '../../services/search_service.dart';
import '../../services/chat_service.dart';
import '../../l10n/app_localizations.dart';
import 'group_chat_screen.dart';
import '../../widgets/common/adaptive_switch.dart';
import '../../utils/swipe_back_route.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({Key? key}) : super(key: key);

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  
  List<SearchResultUser> _allUsers = [];
  List<SearchResultUser> _filteredUsers = [];
  final List<SearchResultUser> _selectedMembers = [];
  bool _isLoading = false;
  String _searchQuery = '';
  
  // Group settings
  bool _isPublic = false;
  bool _allowInvites = true;
  bool _enableHistory = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadUsers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final newQuery = _searchController.text;
    if (newQuery != _searchQuery) {
      setState(() {
        _searchQuery = newQuery;
        _filterUsers();
      });
    }
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      // Load all users (empty query returns all or recent)
      final users = await SearchService.searchUsers(query: '');
      if (mounted) {
        setState(() {
          _allUsers = users;
          _filteredUsers = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _filterUsers() {
    if (_searchQuery.isEmpty) {
      setState(() {
        _filteredUsers = _allUsers;
      });
    } else {
      setState(() {
        _filteredUsers = _allUsers.where((user) {
          final nameLower = user.name.toLowerCase();
          final usernameLower = user.username.toLowerCase();
          final queryLower = _searchQuery.toLowerCase();
          return nameLower.contains(queryLower) || usernameLower.contains(queryLower);
        }).toList();
      });
    }
  }

  void _toggleMember(SearchResultUser user) {
    setState(() {
      if (_selectedMembers.contains(user)) {
        _selectedMembers.remove(user);
      } else {
        _selectedMembers.add(user);
      }
    });
  }

  void _removeMember(SearchResultUser user) {
    setState(() {
      _selectedMembers.remove(user);
    });
  }

  Future<void> _createGroup() async {
    final l10n = context.l10n;
    
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('group_name_required'))),
      );
      return;
    }

    if (_selectedMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('group_members_required'))),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Create group via API
      final participantIds = _selectedMembers.map((u) => u.id).toList();
      final result = await ChatService.createChat(
        chatType: 'group',
        name: _nameController.text.trim(),
        participantIds: participantIds,
      );

      if (mounted) {
        if (result['success'] == true) {
          final chat = result['chat'] as Chat;
          Navigator.pushReplacement(
            context,
            SwipeBackPageRoute(
              builder: (_) => GroupChatScreen(
                chatId: chat.id,
                groupName: chat.name,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'Failed to create group')),
          );
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('chat_new_group')),
        actions: [
          if (_selectedMembers.isNotEmpty)
            TextButton(
              onPressed: _isLoading ? null : _createGroup,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      l10n.translate('create'),
                      style: const TextStyle(color: Colors.white),
                    ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Group info section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Group avatar and name
                Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: const Color(0xFF0088CC),
                      child: IconButton(
                        icon: const Icon(Icons.camera_alt, color: Colors.white),
                        onPressed: () {
                          // TODO: Implement image picker
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          hintText: l10n.translate('group_name_hint'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    hintText: l10n.translate('group_description_hint'),
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                
                // Group settings
                _buildSettingsTile(
                  icon: Icons.public,
                  title: l10n.translate('group_public'),
                  subtitle: l10n.translate('group_public_desc'),
                  value: _isPublic,
                  onChanged: (value) => setState(() => _isPublic = value),
                ),
                _buildSettingsTile(
                  icon: Icons.person_add,
                  title: l10n.translate('group_allow_invites'),
                  subtitle: l10n.translate('group_allow_invites_desc'),
                  value: _allowInvites,
                  onChanged: (value) => setState(() => _allowInvites = value),
                ),
                _buildSettingsTile(
                  icon: Icons.history,
                  title: l10n.translate('group_enable_history'),
                  subtitle: l10n.translate('group_enable_history_desc'),
                  value: _enableHistory,
                  onChanged: (value) => setState(() => _enableHistory = value),
                ),
              ],
            ),
          ),
          
          const Divider(),
          
          // Selected members
          if (_selectedMembers.isNotEmpty) ...[
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: _selectedMembers.length,
                itemBuilder: (context, index) {
                  final member = _selectedMembers[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              backgroundColor: const Color(0xFF0088CC),
                              child: Text(
                                member.name.isNotEmpty
                                    ? member.name[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: GestureDetector(
                                onTap: () => _removeMember(member),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 60,
                          child: Text(
                            member.name,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(),
          ],
          
          // Search and member list
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.translate('search_user_hint'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: _buildUsersList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: const Color(0xFF0088CC)),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: AdaptiveSwitch(
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF0088CC),
      ),
    );
  }

  Widget _buildUsersList() {
    final l10n = context.l10n;

    if (_isLoading && _allUsers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredUsers.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isEmpty
              ? l10n.translate('no_users_available')
              : l10n.translate('search_no_users').replaceAll('{query}', _searchQuery),
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: _filteredUsers.length,
      itemBuilder: (context, index) {
        final user = _filteredUsers[index];
        final isSelected = _selectedMembers.contains(user);
        
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: isSelected ? const Color(0xFF0088CC) : Colors.grey[300],
            child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
              style: TextStyle(color: isSelected ? Colors.white : Colors.black87),
            ),
          ),
          title: Text(user.name),
          subtitle: Text('@${user.username}'),
          trailing: isSelected
              ? const Icon(Icons.check_circle, color: Color(0xFF0088CC))
              : const Icon(Icons.circle_outlined, color: Colors.grey),
          onTap: () => _toggleMember(user),
        );
      },
    );
  }
}
