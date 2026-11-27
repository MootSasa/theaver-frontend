import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../models/theav_theme.dart';
import '../../utils/image_utils.dart';

/// Resolves the accent color and crisp icon for a community channel kind
/// (`text`, `voice`, `stage`, `announcement`, `forum`, `whiteboard`).
class CommunityChannelIcon extends StatelessWidget {
  final String channelType;
  final double size;
  final Color? colorOverride;
  final bool isSelected;

  const CommunityChannelIcon({
    super.key,
    required this.channelType,
    this.size = 18.0,
    this.colorOverride,
    this.isSelected = false,
  });

  static Color resolveColor(
    String channelType, {
    required Color primaryColor,
    required Color secondaryTextColor,
    bool isSelected = false,
  }) {
    if (isSelected) return primaryColor;
    switch (channelType) {
      case 'voice':
        return const Color(0xFF10B981);
      case 'stage':
        return const Color(0xFFF59E0B);
      case 'whiteboard':
        return const Color(0xFF8B5CF6);
      case 'announcement':
      case 'forum':
        return primaryColor;
      default:
        return secondaryTextColor;
    }
  }

  static String describeType(String channelType) {
    switch (channelType) {
      case 'voice':
        return 'Голосовой канал • Go Live до 144 FPS';
      case 'stage':
        return 'Трибуна (Stage)';
      case 'announcement':
        return 'Канал объявлений';
      case 'forum':
        return 'Форум (ветки обсуждений)';
      case 'whiteboard':
        return 'Интерактивная доска';
      default:
        return 'Текстовый канал';
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final color = colorOverride ??
        resolveColor(
          channelType,
          primaryColor: palette.primary,
          secondaryTextColor: palette.subtext,
          isSelected: isSelected,
        );

    switch (channelType) {
      case 'voice':
        return iconoir.SoundHigh(width: size, height: size, color: color);
      case 'stage':
        return iconoir.Microphone(width: size, height: size, color: color);
      case 'announcement':
        return iconoir.Megaphone(width: size, height: size, color: color);
      case 'forum':
        return iconoir.ChatLines(width: size, height: size, color: color);
      case 'whiteboard':
        return iconoir.EditPencil(width: size, height: size, color: color);
      default:
        return SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Text(
              '#',
              style: TextStyle(
                color: color,
                fontSize: size * 0.98,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
          ),
        );
    }
  }
}

/// Squircle community avatar (`borderRadius: size * 0.30`) matching Theaver's
/// visual hierarchy across main chat list tiles, headers, and creation flows.
class CommunityAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String name;
  final double size;
  final Color? accentColor;
  final double? fontSize;

  const CommunityAvatar({
    super.key,
    required this.avatarUrl,
    required this.name,
    this.size = 44.0,
    this.accentColor,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final Color base = accentColor ?? palette.primary;
    final ImageProvider? provider = avatarImageProvider(avatarUrl);
    final radius = BorderRadius.circular(size * 0.30);
    final trimmed = name.trim();
    final initial = trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: provider == null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [base, base.withValues(alpha: 0.74)],
              )
            : null,
        color: provider != null ? base.withValues(alpha: 0.14) : null,
        image: provider != null
            ? DecorationImage(image: provider, fit: BoxFit.cover)
            : null,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 0.5,
        ),
      ),
      alignment: Alignment.center,
      child: provider == null
          ? (initial.isNotEmpty
                ? Text(
                    initial,
                    style: TextStyle(
                      fontSize: fontSize ?? (size * 0.42),
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.0,
                    ),
                  )
                : iconoir.Community(
                    width: size * 0.52,
                    height: size * 0.52,
                    color: Colors.white,
                  ))
          : null,
    );
  }
}
