import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../services/search_service.dart';

/// Shared modal dialog for picking a user via [SearchService.searchUsers].
Future<SearchResultUser?> showUserSearchPickerDialog(
  BuildContext context, {
  required String title,
  Set<String> excludeUserIds = const {},
}) {
  return showDialog<SearchResultUser>(
    context: context,
    builder: (_) => _UserSearchPickerDialog(
      title: title,
      excludeUserIds: excludeUserIds,
    ),
  );
}

class _UserSearchPickerDialog extends StatefulWidget {
  const _UserSearchPickerDialog({
    required this.title,
    required this.excludeUserIds,
  });

  final String title;
  final Set<String> excludeUserIds;

  @override
  State<_UserSearchPickerDialog> createState() =>
      _UserSearchPickerDialogState();
}

class _UserSearchPickerDialogState extends State<_UserSearchPickerDialog> {
  final _queryCtrl = TextEditingController();
  Timer? _debounce;
  List<SearchResultUser> _results = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _runSearch('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String query) async {
    setState(() => _loading = true);
    try {
      final list = await SearchService.searchUsers(query: query, limit: 25);
      if (!mounted) return;
      setState(() {
        _results = list
            .where((u) => !widget.excludeUserIds.contains(u.id))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      _runSearch(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        height: 340,
        child: Column(
          children: [
            TextField(
              controller: _queryCtrl,
              autofocus: true,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: l10n.translate('search_users_hint'),
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            l10n.translate('search_no_results'),
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (ctx, i) {
                            final user = _results[i];
                            final titleText = user.name.isNotEmpty
                                ? user.name
                                : (user.username.isNotEmpty
                                    ? '@${user.username}'
                                    : user.id);
                            return ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  titleText.isNotEmpty
                                      ? titleText[0].toUpperCase()
                                      : '?',
                                ),
                              ),
                              title: Text(titleText),
                              subtitle: user.username.isNotEmpty
                                  ? Text('@${user.username}')
                                  : null,
                              onTap: () => Navigator.pop(ctx, user),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.translate('common_cancel')),
        ),
      ],
    );
  }
}
