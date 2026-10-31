import 'package:flutter/material.dart';

/// Model for a group member.
class GroupMember {
  final String userId;
  final String name;
  final String role; // 'owner', 'admin', 'member'
  final String? tag; // Optional tag

  GroupMember({
    required this.userId,
    required this.name,
    required this.role,
    this.tag,
  });
}

/// Screen for managing group members with role assignment.
class GroupMembersScreen extends StatefulWidget {
  final String groupId;

  const GroupMembersScreen({Key? key, required this.groupId}) : super(key: key);

  @override
  State<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends State<GroupMembersScreen> {
  late List<GroupMember> _members;
  bool _isLoading = true;
  String? _currentUserId; // In a real app, this would come from auth state
  String? _currentUserRole; // Computed from _members

  @override
  void initState() {
    super.initState();
    // Simulate loading group members
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() => _isLoading = true);
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));
    // Mock data - in real app, this would come from backend via gRPC
    _members = [
      GroupMember(
        userId: 'user1',
        name: 'Alice Owner',
        role: 'owner',
        tag: 'Founder',
      ),
      GroupMember(
        userId: 'user2',
        name: 'Bob Admin',
        role: 'admin',
        tag: 'Moderator',
      ),
      GroupMember(
        userId: 'user3',
        name: 'Charlie Member',
        role: 'member',
      ),
      GroupMember(
        userId: 'user4',
        name: 'Diana Member',
        role: 'member',
        tag: 'Newbie',
      ),
    ];
    // Assume current user is Bob (user2) for demo
    _currentUserId = 'user2';
    _currentUserRole = _members
        .firstWhere((m) => m.userId == _currentUserId, orElse: () => GroupMember(userId: '', name: '', role: 'member'))
        .role;
    setState(() => _isLoading = false);
  }

  bool _canManageMembers() {
    return _currentUserRole == 'owner' || _currentUserRole == 'admin';
  }

  bool _isOwner(String userId) {
    return _members.any((m) => m.userId == userId && m.role == 'owner');
  }

  void _showRoleChangeDialog(GroupMember member) {
    final List<String> roles = ['owner', 'admin', 'member'];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Change Role for ${member.name}'),
        content: SingleChildScrollView(
          child: ListBody(
            children: roles.map((role) => ListTile(
              title: Text(role.capitalize()),
              selected: role == member.role,
              onTap: () {
                Navigator.of(context).pop();
                _updateMemberRole(member, role);
              },
            )).toList(),
          ),
        ),
      ),
    );
  }

  void _updateMemberRole(GroupMember member, String newRole) {
    // Prevent changing owner's role unless you are the owner? Typically owner role is fixed.
    if (_isOwner(member.userId) && newRole != 'owner') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot change the owner\'s role')),
      );
      return;
    }
    // Prevent non-owners from assigning owner role
    if (newRole == 'owner' && _currentUserRole != 'owner') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only the owner can assign owner role')),
      );
      return;
    }
    setState(() {
      final index = _members.indexWhere((m) => m.userId == member.userId);
      if (index != -1) {
        _members[index] = member.copyWith(role: newRole);
      }
    });
    // In real app, send update to backend via gRPC
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Role updated to $newRole')),
    );
  }

  void _showRemoveConfirmDialog(GroupMember member) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Are you sure you want to remove ${member.name} from the group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _removeMember(member);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _removeMember(GroupMember member) {
    if (_isOwner(member.userId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot remove the group owner')),
      );
      return;
    }
    setState(() {
      _members.removeWhere((m) => m.userId == member.userId);
    });
    // In real app, send removal request to backend via gRPC
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${member.name} removed from group')),
    );
  }

  void _showAddMemberDialog() {
    final TextEditingController searchController = TextEditingController();
    List<Map<String, String>> searchResults = [];
    bool isSearching = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Member'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search users by name...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (query) async {
                    if (query.length < 2) {
                      setDialogState(() => searchResults = []);
                      return;
                    }
                    setDialogState(() => isSearching = true);
                    // Simulate search delay
                    await Future.delayed(const Duration(milliseconds: 300));
                    // TODO: Replace mock search results with real user search from backend via gRPC
                    final mockUsers = [
                      {'userId': 'user5', 'name': 'Eve NewUser'},
                      {'userId': 'user6', 'name': 'Frank NewUser'},
                      {'userId': 'user7', 'name': 'Grace NewUser'},
                    ].where((u) =>
                        u['name']!.toLowerCase().contains(query.toLowerCase()) &&
                        !_members.any((m) => m.userId == u['userId'])
                    ).toList();
                    setDialogState(() {
                      searchResults = mockUsers;
                      isSearching = false;
                    });
                  },
                ),
                const SizedBox(height: 16),
                if (isSearching)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  )
                else if (searchResults.isEmpty && searchController.text.length >= 2)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No users found'),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: searchResults.length,
                      itemBuilder: (context, index) {
                        final user = searchResults[index];
                        final isAlreadyMember = _members.any(
                          (m) => m.userId == user['userId'],
                        );
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              (user['name'] != null && user['name']!.trim().isNotEmpty)
                                  ? user['name']!.trim()[0].toUpperCase()
                                  : '?',
                            ),
                          ),
                          title: Text(user['name'] ?? ''),
                          trailing: isAlreadyMember
                              ? const Icon(Icons.check, color: Colors.green)
                              : IconButton(
                                  icon: const Icon(Icons.person_add),
                                  onPressed: () {
                                    Navigator.of(dialogContext).pop();
                                    _addMember(
                                      user['userId']!,
                                      user['name']!,
                                    );
                                  },
                                ),
                          enabled: !isAlreadyMember,
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  void _addMember(String userId, String name) {
    // Check if user is already a member
    if (_members.any((m) => m.userId == userId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User is already a member of this group')),
      );
      return;
    }

    setState(() {
      _members.add(GroupMember(
        userId: userId,
        name: name,
        role: 'member',
      ));
    });

    // In real app, send add member request to backend via gRPC
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name added to group')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Members'),
        actions: [
          if (_canManageMembers())
            IconButton(
              icon: const Icon(Icons.person_add),
              tooltip: 'Add Members',
              onPressed: _showAddMemberDialog,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _members.isEmpty
              ? const Center(child: Text('No members found'))
              : ListView.builder(
                  itemCount: _members.length,
                  itemBuilder: (context, index) {
                    final member = _members[index];
                    final bool isCurrentUser = member.userId == _currentUserId;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            member.name.trim().isNotEmpty
                                ? member.name.trim()[0].toUpperCase()
                                : '?',
                          ),
                        ),
                        title: Text(member.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Role: ${member.role.capitalize()}'),
                            if (member.tag != null) Text('Tag: ${member.tag}'),
                            if (isCurrentUser) const Text('(You)', style: TextStyle(color: Colors.blueGrey)),
                          ],
                        ),
                        trailing: _canManageMembers() && !_isOwner(member.userId)
                            ? PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'change_role') {
                                    _showRoleChangeDialog(member);
                                  } else if (value == 'remove') {
                                    _showRemoveConfirmDialog(member);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'change_role',
                                    child: ListTile(
                                      leading: Icon(Icons.person_outline),
                                      title: Text('Change Role'),
                                    ),
                                  ),
                                  if (!_isOwner(member.userId))
                                    const PopupMenuItem(
                                      value: 'remove',
                                      child: ListTile(
                                        leading: Icon(Icons.delete_outline, color: Colors.red),
                                        title: Text('Remove Member',
                                            style: TextStyle(color: Colors.red)),
                                      ),
                                    ),
                                ],
                                child: const Icon(Icons.more_vert),
                              )
                            : null,
                      ),
                    );
                  },
                ),
    );
  }
}

/// Extension to capitalize the first letter of a string.
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
  }
}

/// Extension to copy GroupMember with modifications.
extension GroupMemberExtension on GroupMember {
  GroupMember copyWith({
    String? userId,
    String? name,
    String? role,
    String? tag,
  }) {
    return GroupMember(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      role: role ?? this.role,
      tag: tag ?? this.tag,
    );
  }
}