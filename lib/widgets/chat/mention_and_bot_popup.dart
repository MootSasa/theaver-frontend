import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../models/theav_theme.dart';
import '../../services/bot_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../utils/blur_utils.dart';
import '../../utils/image_utils.dart';

/// Candidate entry for `@` mention autocomplete (chat participant or bot).
class MentionCandidate {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final bool isBot;
  final bool supportsInlineQueries;
  final String? inlinePlaceholder;
  final String? roleLabel;

  const MentionCandidate({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.isBot = false,
    this.supportsInlineQueries = false,
    this.inlinePlaceholder,
    this.roleLabel,
  });

  String get effectiveName =>
      displayName.trim().isNotEmpty ? displayName.trim() : '@$username';
}

enum _MentionRowKind { participant, inlineBot }

class _MentionPopupRow {
  final _MentionRowKind kind;
  final MentionCandidate? candidate;
  final BotInfo? bot;

  const _MentionPopupRow.participant(this.candidate)
      : kind = _MentionRowKind.participant,
        bot = null;

  const _MentionPopupRow.inlineBot(this.bot)
      : kind = _MentionRowKind.inlineBot,
        candidate = null;

  String get username => kind == _MentionRowKind.participant
      ? (candidate?.username ?? '')
      : (bot?.username ?? '');
}

/// Dual-mode (Liquid Glass / Material 3) `@mention` & inline-bot autocomplete popup
/// rendered above `ChatInputBar` whenever typing `@` or `@prefix`.
///
/// Strictly avoids wrapping [LiquidGlassLens] in `Opacity` or `FadeTransition`.
class MentionAndBotPopup extends StatelessWidget {
  final String query;
  final bool isAtMessageStart;
  final List<MentionCandidate> participants;
  final List<BotInfo> inlineBots;
  final ValueChanged<MentionCandidate> onSelectMention;
  final ValueChanged<BotInfo> onSelectInlineBot;
  final VoidCallback? onClose;

  const MentionAndBotPopup({
    super.key,
    required this.query,
    this.isAtMessageStart = false,
    this.participants = const [],
    this.inlineBots = const [],
    required this.onSelectMention,
    required this.onSelectInlineBot,
    this.onClose,
  });

  static const double _kItemHeight = 50.0;
  static const double _kMaxHeight = 224.0;
  static const double _kCornerRadius = 20.0;

  List<_MentionPopupRow> _buildFilteredRows() {
    final q = query.trim().toLowerCase();
    final rows = <_MentionPopupRow>[];
    final seenInlineBots = <String>{};

    if (isAtMessageStart && inlineBots.isNotEmpty) {
      for (final bot in inlineBots) {
        final uname = (bot.username ?? '').trim();
        if (uname.isEmpty) continue;
        final unameLower = uname.toLowerCase();
        final dnameLower = bot.displayName.toLowerCase();
        if (q.isEmpty || unameLower.contains(q) || dnameLower.contains(q)) {
          if (seenInlineBots.add(unameLower)) {
            rows.add(_MentionPopupRow.inlineBot(bot));
          }
        }
      }
    }

    final seenParticipants = <String>{};
    for (final p in participants) {
      final uname = p.username.trim();
      if (uname.isEmpty) continue;
      final unameLower = uname.toLowerCase();
      if (isAtMessageStart && p.supportsInlineQueries && seenInlineBots.contains(unameLower)) {
        continue;
      }
      final dnameLower = p.displayName.toLowerCase();
      if (q.isEmpty || unameLower.contains(q) || dnameLower.contains(q)) {
        if (seenParticipants.add(unameLower)) {
          rows.add(_MentionPopupRow.participant(p));
        }
      }
    }

    if (!isAtMessageStart && inlineBots.isNotEmpty) {
      for (final bot in inlineBots) {
        final uname = (bot.username ?? '').trim();
        if (uname.isEmpty) continue;
        final unameLower = uname.toLowerCase();
        if (seenParticipants.contains(unameLower) || !seenInlineBots.add(unameLower)) {
          continue;
        }
        final dnameLower = bot.displayName.toLowerCase();
        if (q.isEmpty || unameLower.contains(q) || dnameLower.contains(q)) {
          rows.add(
            _MentionPopupRow.participant(
              MentionCandidate(
                id: bot.userId,
                username: uname,
                displayName: bot.displayName.isNotEmpty ? bot.displayName : uname,
                avatarUrl: bot.avatarUrl,
                isBot: true,
                supportsInlineQueries: bot.supportsInlineQueries,
                inlinePlaceholder: bot.inlinePlaceholder,
                roleLabel: 'BOT',
              ),
            ),
          );
        }
      }
    }

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _buildFilteredRows();
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ext = theme.extension<TheavThemeExtension>();
    final cs = theme.colorScheme;
    final glassProvider = LiquidGlassProvider.maybeOf(context);
    final glassEnabled = glassProvider?.enabled ?? false;
    final isLite = glassProvider?.isLite ?? false;

    final double height = math.min(
      _kMaxHeight,
      rows.length * _kItemHeight + 8.0,
    );

    final Widget listContent = SizedBox(
      height: height,
      width: double.infinity,
      child: ScrollConfiguration(
        behavior: const MaterialScrollBehavior().copyWith(overscroll: false),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: rows.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            indent: 56,
            endIndent: 14,
            color: cs.outlineVariant.withValues(alpha: 0.2),
          ),
          itemBuilder: (ctx, idx) {
            final row = rows[idx];
            return _buildRow(ctx, cs, row);
          },
        ),
      ),
    );

    Widget surface;
    if (glassEnabled && glassProvider != null) {
      final style = glassProvider.createStyle(
        context: context,
        cornerRadius: _kCornerRadius,
        refractionIndex: 1.1,
        refractionWidth: 24,
        isLiteOverride: isLite,
      );
      surface = Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        child: SizedBox(
          height: height,
          child: LiquidGlassLens(style: style, child: listContent),
        ),
      );
    } else {
      surface = Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_kCornerRadius),
          child: BackdropFilter.grouped(
            filter: BlurUtils.createDownsampledBlur(15),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: ext?.glassSurfaceColor ??
                    cs.surfaceContainerLow.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(_kCornerRadius),
                border: Border.all(
                  color: ext?.glassBorderColor ??
                      (isDark ? Colors.white12 : Colors.black12),
                  width: 0.8,
                ),
              ),
              child: listContent,
            ),
          ),
        ),
      );
    }

    return Material(type: MaterialType.transparency, child: surface);
  }

  Widget _buildRow(
    BuildContext context,
    ColorScheme cs,
    _MentionPopupRow row,
  ) {
    final isInlineBot = row.kind == _MentionRowKind.inlineBot;
    final String username = row.username;
    final String displayName = isInlineBot
        ? (row.bot!.displayName.isNotEmpty
            ? row.bot!.displayName
            : '@$username')
        : row.candidate!.effectiveName;
    final String? avatarUrl =
        isInlineBot ? row.bot!.avatarUrl : row.candidate!.avatarUrl;
    final bool isBot = isInlineBot || (row.candidate?.isBot ?? false);
    final String? badgeLabel = isInlineBot
        ? 'INLINE'
        : (row.candidate?.roleLabel?.isNotEmpty == true
            ? row.candidate!.roleLabel
            : (isBot ? 'BOT' : null));
    final String subtitleText = isInlineBot &&
            (row.bot!.inlinePlaceholder?.trim().isNotEmpty ?? false)
        ? '@$username · ${row.bot!.inlinePlaceholder!.trim()}'
        : '@$username';

    final avatarProvider = avatarImageProvider(avatarUrl);
    final initialSource =
        displayName.replaceFirst(RegExp(r'^@+'), '').trim();
    final initial = initialSource.isNotEmpty
        ? String.fromCharCode(initialSource.runes.first).toUpperCase()
        : 'U';

    return InkWell(
      onTap: () {
        if (isInlineBot && row.bot != null) {
          onSelectInlineBot(row.bot!);
        } else if (row.candidate != null) {
          onSelectMention(row.candidate!);
        }
      },
      child: SizedBox(
        height: _kItemHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: cs.primary.withValues(alpha: 0.16),
                backgroundImage: avatarProvider,
                child: avatarProvider == null
                    ? (isInlineBot
                        ? iconoir.Spark(
                            width: 17,
                            height: 17,
                            color: cs.primary,
                          )
                        : Text(
                            initial,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                            ),
                          ))
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        if (badgeLabel != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badgeLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: cs.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      subtitleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.primary.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              if (isInlineBot)
                iconoir.NavArrowRight(
                  width: 16,
                  height: 16,
                  color: cs.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
