import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/profile_theme_provider.dart';
import '../../utils/image_utils.dart';
import '../../widgets/profile/liquid_glass_info_panel.dart';
import '../../widgets/profile/liquid_glass_profile_buttons.dart';

/// Виджет интерактивного предпросмотра профиля с текущим пресетом цвета.
class ProfileColorPreviewCard extends StatelessWidget {
  final ProfileColorPreset preset;
  final String displayName;
  final String? avatarUrl;
  final bool glassEnabled;
  final bool isLite;

  const ProfileColorPreviewCard({
    Key? key,
    required this.preset,
    required this.displayName,
    this.avatarUrl,
    this.glassEnabled = false,
    this.isLite = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final cardBg = isDark
        ? const Color.fromARGB(240, 28, 28, 30)
        : const Color.fromARGB(240, 245, 245, 247);

    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            l10n.translate('profile_color_preview_title'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFE5E5EA) : const Color(0xFF1C1C1E),
            ),
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: preset.backgroundColor.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: preset.backgroundColor.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Градиентное свечение в верхней части
              Positioned(
                top: -40,
                left: 0,
                right: 0,
                height: 160,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        preset.backgroundColor.withValues(alpha: 0.35),
                        preset.ringColor.withValues(alpha: 0.1),
                        Colors.transparent,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Mini avatar
                    Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: preset.isGradient
                                ? preset.gradientColors!
                                : [preset.backgroundColor, preset.ringColor],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: preset.backgroundColor.withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(3.0),
                          child: Builder(
                            builder: (_) {
                              final ImageProvider? resolvedAvatar =
                                  (avatarUrl != null && avatarUrl!.isNotEmpty)
                                      ? (avatarUrl!.startsWith('assets/')
                                          ? AssetImage(avatarUrl!)
                                          : avatarImageProvider(
                                              avatarUrl,
                                              maxDecodeDimension: 240,
                                            ))
                                      : null;
                              return CircleAvatar(
                                backgroundColor: isDark
                                    ? const Color(0xFF2C2C2E)
                                    : Colors.white,
                                backgroundImage: resolvedAvatar,
                                child: resolvedAvatar == null
                                    ? Text(
                                        displayName.isNotEmpty
                                            ? displayName[0].toUpperCase()
                                            : 'M',
                                        style: TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.bold,
                                          color: preset.backgroundColor,
                                        ),
                                      )
                                    : null,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Display name & status
                    Text(
                      displayName.isNotEmpty ? displayName : 'User',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 300),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: preset.statusColor,
                      ),
                      child: Text(l10n.translate('profile_online')),
                    ),
                    const SizedBox(height: 14),
                    // Mini buttons
                    LiquidGlassProfileButtons(
                      enabled: glassEnabled,
                      isLite: isLite,
                      hasAvatar: true,
                      choosePhotoLabel: l10n.translate('profile_choose_photo'),
                      qrCodeLabel: l10n.translate('profile_qr_code'),
                      editLabel: l10n.translate('profile_edit_btn'),
                      deletePhotoLabel: l10n.translate('profile_delete_photo'),
                    ),
                    const SizedBox(height: 10),
                    // Mini info panel
                    LiquidGlassInfoPanel(
                      enabled: glassEnabled,
                      isLite: isLite,
                      phone: '+7 (999) 000-00-00',
                      username: 'username',
                      phoneLabel: l10n.translate('profile_phone'),
                      bioLabel: l10n.translate('profile_bio'),
                      usernameLabel: l10n.translate('profile_username'),
                      birthdayLabel: l10n.translate('profile_birthday'),
                      ageLabel: l10n.translate('profile_age'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
