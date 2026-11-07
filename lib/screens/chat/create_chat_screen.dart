import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/community_models.dart';
import '../../models/theav_theme.dart';
import '../../services/liquid_glass_provider.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../community/create_community_screen.dart';
import 'create_channel_screen.dart';
import 'create_group_screen.dart';
import 'create_private_chat_screen.dart';

/// Типы действий в панели создания чата на главном экране.
enum CreateChatOptionType {
  privateChat,
  groupChat,
  channel,
  community,
  joinByCode,
}

class CreateChatOptionSpec {
  final CreateChatOptionType type;
  final String title;
  final String subtitle;
  final Color accentColor;
  final bool isSquircleBadge;
  final Widget Function(Color color, double size) iconBuilder;

  const CreateChatOptionSpec({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    this.isSquircleBadge = false,
    required this.iconBuilder,
  });
}

List<CreateChatOptionSpec> buildCreateChatOptions(BuildContext context) {
  String tr(String key, String fallback) {
    try {
      final v = context.l10n.translate(key);
      if (v.isNotEmpty && v != key) return v;
    } catch (_) {}
    return fallback;
  }

  return [
    CreateChatOptionSpec(
      type: CreateChatOptionType.privateChat,
      title: tr('chat_new_private', 'Личный чат'),
      subtitle: 'Диалог один на один с человеком или ботом',
      accentColor: const Color(0xFF3B82F6),
      iconBuilder: (c, s) => iconoir.UserPlus(color: c, width: s, height: s),
    ),
    CreateChatOptionSpec(
      type: CreateChatOptionType.groupChat,
      title: tr('chat_new_group', 'Новая группа'),
      subtitle: 'Беседа компании, опросы и групповые звонки',
      accentColor: const Color(0xFF10B981),
      iconBuilder: (c, s) => iconoir.Group(color: c, width: s, height: s),
    ),
    CreateChatOptionSpec(
      type: CreateChatOptionType.channel,
      title: tr('chat_new_channel', 'Новый канал'),
      subtitle: 'Публикации и трансляции для подписчиков',
      accentColor: const Color(0xFF8B5CF6),
      iconBuilder: (c, s) => iconoir.Megaphone(color: c, width: s, height: s),
    ),
    CreateChatOptionSpec(
      type: CreateChatOptionType.community,
      title: 'Новое сообщество',
      subtitle: 'Категории, комнаты и стримы до 144 FPS',
      accentColor: const Color(0xFFF59E0B),
      isSquircleBadge: true,
      iconBuilder: (c, s) => Icon(Icons.hub_rounded, color: c, size: s),
    ),
    CreateChatOptionSpec(
      type: CreateChatOptionType.joinByCode,
      title: 'Войти по коду / ссылке',
      subtitle: 'Присоединиться к сообществу, группе или каналу',
      accentColor: const Color(0xFFEC4899),
      iconBuilder: (c, s) => Icon(Icons.link_rounded, color: c, size: s),
    ),
  ];
}

/// Панель выбора типа создаваемого чата, используемая при раскрытии кнопки «+»
/// на главном экране (в режимах Liquid Glass и Material Matte).
class CreateChatSelectorPanel extends StatelessWidget {
  static const double kPanelWidth = 304.0;
  static const double kPanelHeight = 342.0;

  final double width;
  final double height;
  final ValueChanged<CreateChatOptionType> onSelectOption;
  final VoidCallback onClose;

  const CreateChatSelectorPanel({
    super.key,
    this.width = kPanelWidth,
    this.height = kPanelHeight,
    required this.onSelectOption,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.62)
        : const Color(0xFF1C1C1E).withValues(alpha: 0.58);
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final options = buildCreateChatOptions(context);

    return SizedBox(
      width: width,
      height: height,
      child: OverflowBox(
        minWidth: width,
        maxWidth: width,
        minHeight: 0,
        maxHeight: height,
        alignment: Alignment.bottomRight,
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Шапка панели
                  SizedBox(
                    height: 38,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
                      child: Row(
                        children: [
                          Text(
                            'Создать или войти',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: titleColor,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onClose,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.10)
                                    : Colors.black.withValues(alpha: 0.06),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: iconoir.Xmark(
                                width: 16,
                                height: 16,
                                color: titleColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 6, thickness: 0.5, color: dividerColor),
                  for (final opt in options)
                    _CreateChatSelectorRow(
                      spec: opt,
                      titleColor: titleColor,
                      subtitleColor: subColor,
                      onTap: () => onSelectOption(opt.type),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateChatSelectorRow extends StatelessWidget {
  final CreateChatOptionSpec spec;
  final Color titleColor;
  final Color subtitleColor;
  final VoidCallback onTap;

  const _CreateChatSelectorRow({
    required this.spec,
    required this.titleColor,
    required this.subtitleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: spec.accentColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(
                    spec.isSquircleBadge ? 13 : 19,
                  ),
                ),
                alignment: Alignment.center,
                child: spec.iconBuilder(spec.accentColor, 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spec.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      spec.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              iconoir.NavArrowRight(
                width: 16,
                height: 16,
                color: subtitleColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Полноэкранный хаб выбора типа создаваемого чата.
class CreateChatScreen extends StatelessWidget {
  final ValueChanged<Community>? onCommunityCreated;

  const CreateChatScreen({
    Key? key,
    this.onCommunityCreated,
  }) : super(key: key);

  void _navigateToOption(BuildContext context, CreateChatOptionType type) {
    HapticUtils.tap();
    switch (type) {
      case CreateChatOptionType.privateChat:
        Navigator.push(
          context,
          SwipeBackPageRoute(
            builder: (_) => CreatePrivateChatScreen(
              onCommunityCreated: onCommunityCreated,
            ),
          ),
        );
        break;
      case CreateChatOptionType.groupChat:
        Navigator.push(
          context,
          SwipeBackPageRoute(builder: (_) => const CreateGroupScreen()),
        );
        break;
      case CreateChatOptionType.channel:
        Navigator.push(
          context,
          SwipeBackPageRoute(builder: (_) => const CreateChannelScreen()),
        );
        break;
      case CreateChatOptionType.community:
        Navigator.push(
          context,
          SwipeBackPageRoute(
            builder: (_) => CreateCommunityScreen(
              onCommunityCreated: onCommunityCreated,
            ),
          ),
        );
        break;
      case CreateChatOptionType.joinByCode:
        Navigator.push(
          context,
          SwipeBackPageRoute(
            builder: (_) => CreateCommunityScreen(
              initialJoinMode: true,
              onCommunityCreated: onCommunityCreated,
            ),
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = context.theav;
    final glassProvider = context.watch<LiquidGlassProvider>();
    final isGlass = glassProvider.enabled;
    final isLite = glassProvider.isLite;
    final options = buildCreateChatOptions(context);

    return Scaffold(
      backgroundColor: palette.bgBase,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: iconoir.NavArrowLeft(
            width: 24,
            height: 24,
            color: palette.textPrimary,
          ),
        ),
        title: Text(
          'Создать чат',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          for (final opt in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildOptionCard(
                context,
                spec: opt,
                isGlass: isGlass,
                isLite: isLite,
                isDark: isDark,
                palette: palette,
                onTap: () => _navigateToOption(context, opt.type),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOptionCard(
    BuildContext context, {
    required CreateChatOptionSpec spec,
    required bool isGlass,
    required bool isLite,
    required bool isDark,
    required TheavPalette palette,
    required VoidCallback onTap,
  }) {
    final content = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: spec.accentColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(
                  spec.isSquircleBadge ? 16 : 24,
                ),
              ),
              alignment: Alignment.center,
              child: spec.iconBuilder(spec.accentColor, 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spec.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    spec.subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            iconoir.NavArrowRight(
              width: 20,
              height: 20,
              color: palette.textTertiary,
            ),
          ],
        ),
      ),
    );

    if (isGlass) {
      final glassProvider = context.watch<LiquidGlassProvider>();
      final style = glassProvider.createStyle(
        context: context,
        isLiteOverride: isLite,
        shape: const LiquidGlassShape.continuousRoundedRectangle(
          cornerRadius: 20,
        ),
      );
      return LiquidGlassLens(
        style: style,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.08),
              width: 0.6,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: content,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.6,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: content,
      ),
    );
  }
}