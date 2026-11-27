import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../models/profile_customization.dart';
import '../../services/auth_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/peer_customization_cache.dart';
import '../../utils/haptic_utils.dart';
import '../common/glass_modal_sheet.dart';
import '../common/peer_badges_widget.dart';

/// Signature for injecting badge updates in hermetic widget tests.
typedef BadgeUpdateHandler = Future<bool> Function(String? badgeId);

/// Bottom sheet available exclusively to [CREATOR] users when viewing another human user,
/// allowing them to assign/replace a single role badge or revoke the current badge.
class ManageUserBadgeSheet extends StatefulWidget {
  final String targetUserId;
  final String targetDisplayName;
  final UserBadge? currentBadge;
  final List<UserBadge>? catalogOverride;
  final BadgeUpdateHandler? onUpdateBadge;
  final ValueChanged<UserBadge?>? onCompleted;

  const ManageUserBadgeSheet({
    super.key,
    required this.targetUserId,
    required this.targetDisplayName,
    this.currentBadge,
    this.catalogOverride,
    this.onUpdateBadge,
    this.onCompleted,
  });

  static Future<UserBadge?> show(
    BuildContext context, {
    required String targetUserId,
    required String targetDisplayName,
    UserBadge? currentBadge,
    List<UserBadge>? catalogOverride,
    BadgeUpdateHandler? onUpdateBadge,
  }) async {
    UserBadge? result = currentBadge;
    await showTheavGlassModalSheet<void>(
      context: context,
      builder: (ctx) => ManageUserBadgeSheet(
        targetUserId: targetUserId,
        targetDisplayName: targetDisplayName,
        currentBadge: currentBadge,
        catalogOverride: catalogOverride,
        onUpdateBadge: onUpdateBadge,
        onCompleted: (updated) {
          result = updated;
        },
      ),
    );
    return result;
  }

  @override
  State<ManageUserBadgeSheet> createState() => _ManageUserBadgeSheetState();
}

class _ManageUserBadgeSheetState extends State<ManageUserBadgeSheet> {
  String? _selectedBadgeId;
  bool _isSubmitting = false;
  String? _errorText;

  List<UserBadge> get _assignableBadges {
    final source =
        widget.catalogOverride ?? PeerCustomizationCache.instance.badgesCatalog;
    return source
        .where((b) => b.isAssignableByCreator && b.id != 'creator')
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _selectedBadgeId = widget.currentBadge?.id;
  }

  Future<void> _submit(String? badgeId) async {
    if (_isSubmitting) return;
    HapticUtils.selection();
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    bool ok = false;
    UserBadge? resultingBadge;

    try {
      if (widget.onUpdateBadge != null) {
        ok = await widget.onUpdateBadge!(badgeId);
        if (ok && badgeId != null) {
          resultingBadge = _assignableBadges.firstWhere(
            (b) => b.id == badgeId,
            orElse: () => UserBadge.builtInDefaults.firstWhere((b) => b.id == badgeId),
          );
        }
      } else {
        final token = await AuthService.getToken();
        if (token == null || token.isEmpty) {
          ok = false;
        } else {
          final uri = Uri.parse(
            '${AppConfig.baseUrl}/api/users/${widget.targetUserId}/badge',
          );
          final headers = {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          };
          final http.Response response = badgeId == null
              ? await http.delete(uri, headers: headers)
              : await http.put(
                  uri,
                  headers: headers,
                  body: jsonEncode({'badge_id': badgeId}),
                );

          if (response.statusCode == 200) {
            ok = true;
            final decoded = jsonDecode(response.body);
            if (decoded is Map) {
              if (decoded['badge'] is Map) {
                resultingBadge = UserBadge.fromJson(
                  Map<String, dynamic>.from(decoded['badge'] as Map),
                );
              }
              if (decoded['peer_customization'] is Map) {
                PeerCustomizationCache.instance.mergeFromJson(
                  widget.targetUserId,
                  Map<String, dynamic>.from(
                    decoded['peer_customization'] as Map,
                  ),
                );
              } else {
                PeerCustomizationCache.instance.mergeFromJson(
                  widget.targetUserId,
                  {
                    'badge': resultingBadge?.toJson(),
                    'badge_is_displayed': resultingBadge != null,
                  },
                );
              }
            }
          } else {
            try {
              final decoded = jsonDecode(response.body);
              if (decoded is Map && decoded['message'] != null) {
                _errorText = decoded['message'].toString();
              }
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      ok = false;
      _errorText = e.toString();
    }

    if (!mounted) return;
    if (ok) {
      widget.onCompleted?.call(resultingBadge);
      final updatedMsg = translateOrFallback(
        context,
        'manageBadgeUpdated',
        'User badge updated',
      );
      Navigator.of(context).pop();
      if (context.mounted) {
        try {
          GlassToastService().show(context, updatedMsg);
        } catch (_) {}
      }
    } else {
      setState(() {
        _isSubmitting = false;
        _errorText ??= translateOrFallback(
          context,
          'error_generic',
          'Failed to update badge',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final badges = _assignableBadges;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            translateOrFallback(context, 'manageBadgeTitle', 'Assign Badge'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            widget.targetDisplayName,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                ...badges.map((badge) {
                  final selected = _selectedBadgeId == badge.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _isSubmitting
                          ? null
                          : () => setState(() => _selectedBadgeId = badge.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: selected
                              ? badge.accentColor.withValues(alpha: isDark ? 0.18 : 0.11)
                              : theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.35),
                          border: Border.all(
                            color: selected
                                ? badge.accentColor.withValues(alpha: 0.7)
                                : theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.35),
                            width: selected ? 1.5 : 0.8,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      PeerBadgesRow(
                                        badge: badge,
                                        interactiveBadge: false,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          translateOrFallback(
                                            context,
                                            badge.nameKey,
                                            badge.shortTag,
                                          ),
                                          style: theme.textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    translateOrFallback(
                                      context,
                                      badge.descKey,
                                      '',
                                    ),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected
                                      ? badge.accentColor
                                      : theme.colorScheme.outline,
                                  width: 2,
                                ),
                                color: selected
                                    ? badge.accentColor
                                    : Colors.transparent,
                              ),
                              child: selected
                                  ? const Icon(
                                      Icons.check,
                                      size: 13,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 4),
                Text(
                  translateOrFallback(
                    context,
                    'manageBadgeCreatorNote',
                    'The CREATOR role can only be changed via server admin',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              if (widget.currentBadge != null) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting ? null : () => _submit(null),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    child: Text(
                      translateOrFallback(
                        context,
                        'manageBadgeRevoke',
                        'Revoke Badge',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _isSubmitting || _selectedBadgeId == null
                      ? null
                      : () => _submit(_selectedBadgeId),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          translateOrFallback(
                            context,
                            'customizationSave',
                            'Save Changes',
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
