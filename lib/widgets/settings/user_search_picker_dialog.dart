import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../l10n/app_localizations.dart';
import '../../services/search_service.dart';
import '../design_system/theav_design_system.dart';

/// Shared modal sheet for picking a user via [SearchService.searchUsers].
Future<SearchResultUser?> showUserSearchPickerDialog(
  BuildContext context, {
  required String title,
  Set<String> excludeUserIds = const {},
}) {
  return showTheavModalSheet<SearchResultUser>(
    context: context,
    title: title,
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
    final palette = context.theav;
    return SizedBox(
      height: 420,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          children: [
            TheavInsetGroup(
              children: [
                TheavInlineTextField(
                  controller: _queryCtrl,
                  autofocus: true,
                  onChanged: _onQueryChanged,
                  placeholder: l10n.translate('search_users_hint'),
                  prefix: iconoir.Search(
                    width: 18,
                    height: 18,
                    color: palette.subtext,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            l10n.translate('search_no_results'),
                            style: TextStyle(color: palette.subtext),
                          ),
                        )
                      : SingleChildScrollView(
                          child: TheavInsetGroup(
                            children: [
                              for (final user in _results)
                                () {
                                  final titleText = user.name.isNotEmpty
                                      ? user.name
                                      : (user.username.isNotEmpty
                                          ? '@${user.username}'
                                          : user.id);
                                  return TheavListRow(
                                    leading: CircleAvatar(
                                      backgroundColor: palette.primary
                                          .withValues(alpha: 0.14),
                                      child: Text(
                                        titleText.isNotEmpty
                                            ? titleText[0].toUpperCase()
                                            : '?',
                                        style: TextStyle(
                                          color: palette.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    title: titleText,
                                    subtitle: user.username.isNotEmpty
                                        ? '@${user.username}'
                                        : null,
                                    onTap: () => Navigator.pop(context, user),
                                  );
                                }(),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
