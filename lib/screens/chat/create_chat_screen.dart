import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../l10n/app_localizations.dart';
import '../../models/community_models.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/settings/settings_floating_header.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../community/create_community_screen.dart';
import '../contacts/contacts_screen.dart';
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
  contacts,
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
      iconBuilder: (c, s) => iconoir.Community(color: c, width: s, height: s),
    ),
    CreateChatOptionSpec(
      type: CreateChatOptionType.joinByCode,
      title: 'Войти по коду / ссылке',
      subtitle: 'Присоединиться к сообществу, группе или каналу',
      accentColor: const Color(0xFFEC4899),
      iconBuilder: (c, s) => iconoir.Link(color: c, width: s, height: s),
    ),
    CreateChatOptionSpec(
      type: CreateChatOptionType.contacts,
      title: 'Контакты',
      subtitle: 'Список контактов и добавление по @username',
      accentColor: const Color(0xFF06B6D4),
      iconBuilder: (c, s) => iconoir.Book(color: c, width: s, height: s),
    ),
  ];
}

/// Панель выбора типа создаваемого чата, используемая при раскрытии кнопки «+»
/// на главном экране (в режимах Liquid Glass и Material Matte).
class CreateChatSelectorPanel extends StatelessWidget {
  static const double kPanelWidth = 304.0;
  static const double kPanelHeight = 404.0;

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
    final palette = context.theav;
    final titleColor = isDark ? Colors.white : palette.onSurface;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.62)
        : palette.subtext;
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
      case CreateChatOptionType.contacts:
        Navigator.push(
          context,
          SwipeBackPageRoute(builder: (_) => const ContactsScreen()),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final options = buildCreateChatOptions(context);

    return SettingsFloatingScaffold(
      title: 'Создать чат',
      backgroundColor: palette.bgBase,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          SettingsFloatingHeader.topClearanceOf(context) + 12,
          16,
          MediaQuery.paddingOf(context).bottom + 24,
        ),
        children: [
          TheavInsetGroup(
            margin: EdgeInsets.zero,
            dividerIndent: 76,
            children: [
              for (final opt in options)
                _buildOptionRow(
                  context,
                  spec: opt,
                  palette: palette,
                  onTap: () => _navigateToOption(context, opt.type),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOptionRow(
    BuildContext context, {
    required CreateChatOptionSpec spec,
    required TheavPalette palette,
    required VoidCallback onTap,
  }) {
    return TheavListRow(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: spec.accentColor.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(spec.isSquircleBadge ? 14 : 22),
        ),
        alignment: Alignment.center,
        child: spec.iconBuilder(spec.accentColor, 22),
      ),
      title: spec.title,
      subtitle: spec.subtitle,
      showChevron: true,
      onTap: onTap,
    );
  }
}
