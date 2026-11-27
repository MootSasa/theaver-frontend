import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../models/community_models.dart';
import '../../screens/settings/profile_screen.dart';
import '../../services/contacts_service.dart';
import '../../utils/swipe_back_route.dart';
import '../common/peer_badges_widget.dart';
import '../design_system/theav_design_system.dart';
import '../user/avatar_with_status.dart';
import '../user/emoji_status_badge.dart';

/// Opens the Community Members modal sheet using dual-mode [showTheavModalSheet].
Future<void> showCommunityMembersSheet(
  BuildContext context, {
  required Community community,
  required List<CommunityMember> members,
  bool isLoading = false,
  VoidCallback? onRefresh,
  ValueChanged<CommunityMember>? onManageMember,
}) {
  return showTheavModalSheet<void>(
    context: context,
    title: 'Участники (${members.isNotEmpty ? members.length : community.memberCount})',
    showCloseButton: true,
    maxHeightFactor: 0.9,
    padding: EdgeInsets.zero,
    builder: (ctx) => CommunityMembersPane(
      community: community,
      members: members,
      isLoading: isLoading,
      onRefresh: onRefresh,
      onManageMember: onManageMember,
      onMemberOpenedProfile: () => Navigator.of(ctx).maybePop(),
    ),
  );
}

/// Telegram-styled member list grouped by hoisted Discord roles with role
/// colors, online status badges, and search filtering. Works both inside a
/// desktop right pane and inside [showCommunityMembersSheet].
class CommunityMembersPane extends StatefulWidget {
  final Community community;
  final List<CommunityMember> members;
  final bool isLoading;
  final VoidCallback? onRefresh;
  final ValueChanged<CommunityMember>? onManageMember;
  final VoidCallback? onMemberOpenedProfile;

  const CommunityMembersPane({
    super.key,
    required this.community,
    required this.members,
    this.isLoading = false,
    this.onRefresh,
    this.onManageMember,
    this.onMemberOpenedProfile,
  });

  @override
  State<CommunityMembersPane> createState() => _CommunityMembersPaneState();
}

class _CommunityMembersPaneState extends State<CommunityMembersPane> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    ContactsService.revisionNotifier.addListener(_onContactsRevisionChanged);
  }

  void _onContactsRevisionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ContactsService.revisionNotifier.removeListener(_onContactsRevisionChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  String _resolveMemberName(
    CommunityMember m, {
    String emptyFallback = '',
  }) {
    final resolved = ContactsService.resolvePeerName(
      m.userId,
      m.effectiveDisplayName,
      isBot: m.isBot,
    ).trim();
    if (resolved.isNotEmpty) return resolved;
    if (m.username.trim().isNotEmpty) return m.username.trim();
    return emptyFallback;
  }

  String? _resolveMemberAvatar(CommunityMember m) {
    return ContactsService.resolvePeerAvatarUrl(
      m.userId,
      m.avatarUrl,
      isBot: m.isBot,
    );
  }

  void _openMemberProfile(CommunityMember m) {
    final name = _resolveMemberName(m, emptyFallback: 'Пользователь');
    final avatarUrl = _resolveMemberAvatar(m);
    Navigator.of(context).push(
      SwipeBackPageRoute(
        builder: (_) => ProfileScreen(
          entityType: ProfileEntityType.user,
          userId: m.userId,
          initialName: name,
          initialAvatarUrl: avatarUrl,
          initialIsOnline: m.isOnline,
        ),
      ),
    );
    widget.onMemberOpenedProfile?.call();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final qLower = _query.trim().toLowerCase();
    final filtered = qLower.isEmpty
        ? widget.members
        : widget.members.where((m) {
            final resolvedName = _resolveMemberName(m).toLowerCase();
            return resolvedName.contains(qLower) ||
                m.effectiveDisplayName.toLowerCase().contains(qLower) ||
                m.displayName.toLowerCase().contains(qLower) ||
                (m.originalDisplayName?.toLowerCase().contains(qLower) ?? false) ||
                m.nickname.toLowerCase().contains(qLower) ||
                m.username.toLowerCase().contains(qLower);
          }).toList();
    final sections = groupMembersByHoistedRoles(
      filtered,
      widget.community.roles,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: TheavInsetGroup(
            margin: EdgeInsets.zero,
            borderRadius: 14,
            children: [
              TheavInlineTextField(
                controller: _searchCtrl,
                placeholder: 'Поиск участников...',
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                prefix: iconoir.Search(
                  width: 17,
                  height: 17,
                  color: palette.subtext,
                ),
                suffix: _query.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                        child: iconoir.Xmark(
                          width: 16,
                          height: 16,
                          color: palette.subtext,
                        ),
                      )
                    : null,
                onChanged: (v) => setState(() => _query = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: widget.isLoading && widget.members.isEmpty
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : sections.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            iconoir.Group(
                              width: 34,
                              height: 34,
                              color: palette.subtext.withValues(alpha: 0.6),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              qLower.isEmpty
                                  ? 'Список участников пуст'
                                  : 'Никого не найдено',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: palette.subtext,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(top: 4, bottom: 16),
                      itemCount: sections.length,
                      itemBuilder: (ctx, idx) {
                        final section = sections[idx];
                        return TheavInsetGroup(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          header:
                              '${section.title.toUpperCase()} — ${section.members.length}',
                          dividerIndent: 58,
                          children: section.members.map((m) {
                            final name = _resolveMemberName(m, emptyFallback: 'U');
                            final avatarUrl = _resolveMemberAvatar(m);
                            final canResolveIdentity =
                                ContactsService.shouldResolveUserIdentity(
                              m.userId,
                              isBot: m.isBot,
                            );
                            final topRole = highestColoredRoleForMember(
                              m,
                              widget.community.roles,
                            );
                            final isOwner = m.userId.isNotEmpty &&
                                m.userId == widget.community.ownerId;
                            final cust = m.peerCustomization;

                            return TheavListRow(
                              minHeight: 50,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              leading: AvatarWithStatus(
                                userId: m.userId,
                                avatarUrl: avatarUrl,
                                name: name,
                                radius: 18,
                                isOnline: m.isOnline,
                                decorationOverride: cust?.avatarDecoration,
                                showDecoration: true,
                                animateDecoration: false,
                                resolveContactOverride: canResolveIdentity,
                              ),
                              titleWidget: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: topRole?.parsedColor ??
                                            palette.onSurface,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (isOwner) ...[
                                    const SizedBox(width: 5),
                                    const iconoir.Crown(
                                      width: 14,
                                      height: 14,
                                      color: Color(0xFFF59E0B),
                                    ),
                                  ],
                                  if (cust?.activeEmojiStatus != null) ...[
                                    const SizedBox(width: 4),
                                    EmojiStatusBadge(
                                      status: cust!.activeEmojiStatus,
                                      size: 14,
                                      interactive: false,
                                    ),
                                  ],
                                  PeerBadgesRow(
                                    isBot: m.isBot,
                                    isVerified: m.isVerified,
                                    badge: cust?.visibleBadge,
                                    interactiveBadge: false,
                                    verifiedIconSize: 14,
                                  ),
                                ],
                              ),
                              subtitle: m.username.isNotEmpty
                                  ? '@${m.username}'
                                  : null,
                              trailing: widget.onManageMember != null && !isOwner
                                  ? GestureDetector(
                                      onTap: () => widget.onManageMember!(m),
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: iconoir.MoreVert(
                                          width: 17,
                                          height: 17,
                                          color: palette.subtext,
                                        ),
                                      ),
                                    )
                                  : null,
                              onTap: () => _openMemberProfile(m),
                            );
                          }).toList(),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
