import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../models/theav_theme.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';
import '../../widgets/profile/avatar_gallery_viewer.dart';
import '../../widgets/user/avatar_with_status.dart';

/// Полноценный, независимый экран профиля пользователя (собеседника в чате).
///
/// **Особенности**:
/// - Имеет собственный [Scaffold] и непрозрачный фон (не является стеклом поверх чата).
/// - Поддерживает жесты свайпа назад [SwipeBackPageRoute] и системную кнопку «Назад».
/// - Отображает аватарку с открытием в галерею [AvatarGalleryViewer], ник, статус, био,
///   кнопки звонков, поиска и управления уведомлениями.
class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String? initialName;
  final String? initialAvatarUrl;
  final bool? isOnline;
  final DateTime? lastSeen;
  final String? chatId;
  final VoidCallback? onVoiceCall;
  final VoidCallback? onVideoCall;

  const UserProfileScreen({
    super.key,
    required this.userId,
    this.initialName,
    this.initialAvatarUrl,
    this.isOnline,
    this.lastSeen,
    this.chatId,
    this.onVoiceCall,
    this.onVideoCall,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  bool _isLoading = false;
  String? _displayName;
  String? _username;
  String? _avatarUrl;
  String? _bio;
  bool _isOnline = false;
  DateTime? _lastSeen;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _displayName = widget.initialName;
    _avatarUrl = widget.initialAvatarUrl;
    _isOnline = widget.isOnline ?? false;
    _lastSeen = widget.lastSeen;
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    if (widget.userId.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final res = await AuthService.getUserProfile(widget.userId);
      if (res['success'] == true && res['user'] != null && mounted) {
        final u = res['user'] as Map<String, dynamic>;
        setState(() {
          _displayName = u['display_name']?.toString() ??
              u['name']?.toString() ??
              _displayName;
          _username = u['username']?.toString() ?? _username;
          _avatarUrl = u['avatar_url']?.toString() ?? _avatarUrl;
          _bio = u['bio']?.toString() ?? _bio;
          if (u['is_online'] != null) {
            _isOnline = u['is_online'] == true;
          }
        });
      }
    } catch (e) {
      debugPrint('[UserProfileScreen] Error loading user profile: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openAvatarViewer() {
    final effectiveUrl = _avatarUrl ?? widget.initialAvatarUrl;
    if (effectiveUrl == null || effectiveUrl.isEmpty) return;

    final resolved = getValidAvatarUrl(effectiveUrl) ?? effectiveUrl;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AvatarGalleryViewer(
          avatarUrls: [resolved],
          initialIndex: 0,
        ),
      ),
    );
  }

  void _copyToClipboard(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    HapticUtils.tap();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeExt = theme.extension<TheavThemeExtension>();
    final l10n = context.l10n;

    final primaryTextColor = themeExt?.palette.appBarForeground ??
        (isDark ? Colors.white : const Color(0xFF1C1C1E));
    final secondaryTextColor = themeExt?.palette.subtext ??
        (isDark
            ? Colors.white.withValues(alpha: 0.65)
            : const Color(0xFF8E8E93));
    final cardColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;

    final name = (_displayName != null && _displayName!.isNotEmpty)
        ? _displayName!
        : (widget.initialName ?? widget.userId);

    String statusText;
    Color statusColor = secondaryTextColor;
    if (_isOnline) {
      statusText = l10n.translate('chat_online');
      statusColor = const Color(0xFF34C759); // Apple Green
    } else if (_lastSeen != null) {
      statusText = DateTimeUtils.formatLastSeen(_lastSeen, context);
    } else {
      statusText = l10n.translate('chat_offline');
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: iconoir.NavArrowLeft(
            width: 24,
            height: 24,
            color: primaryTextColor,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: iconoir.ShareAndroid(
              width: 22,
              height: 22,
              color: primaryTextColor,
            ),
            onPressed: () {
              if (_username != null && _username!.isNotEmpty) {
                _copyToClipboard(
                  'https://t.me/$_username',
                  l10n.translate('link_copied'),
                );
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // 1. Аватарка, имя и статус
          Center(
            child: GestureDetector(
              onTap: _openAvatarViewer,
              child: AvatarWithStatus(
                avatarUrl: _avatarUrl ?? widget.initialAvatarUrl,
                name: name,
                radius: 54,
                isOnline: _isOnline,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: primaryTextColor,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 14,
                color: statusColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 2. Блок быстрых действий (Звонок, Видео, Поиск, Заглушить)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ActionButton(
                icon: const iconoir.Phone(width: 22, height: 22),
                label: l10n.translate('call'),
                onTap: widget.onVoiceCall ??
                    () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.translate('call_not_supported'))),
                      );
                    },
              ),
              _ActionButton(
                icon: const iconoir.VideoCamera(width: 22, height: 22),
                label: l10n.translate('video'),
                onTap: widget.onVideoCall ??
                    () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.translate('call_not_supported'))),
                      );
                    },
              ),
              _ActionButton(
                icon: const iconoir.Search(width: 22, height: 22),
                label: l10n.translate('search'),
                onTap: () {
                  Navigator.of(context).pop();
                },
              ),
              _ActionButton(
                icon: _isMuted
                    ? const iconoir.BellOff(width: 22, height: 22)
                    : const iconoir.Bell(width: 22, height: 22),
                label: _isMuted
                    ? l10n.translate('chat_menu_unmute')
                    : l10n.translate('chat_menu_mute'),
                onTap: () {
                  setState(() => _isMuted = !_isMuted);
                  HapticUtils.tap();
                },
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 3. Информационная карточка (Username, Bio, Телефон/ID)
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                if (_username != null && _username!.isNotEmpty) ...[
                  ListTile(
                    leading: const iconoir.AtSign(width: 22, height: 22),
                    title: Text(
                      '@$_username',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: primaryTextColor,
                      ),
                    ),
                    subtitle: Text(
                      l10n.translate('settings_username'),
                      style: TextStyle(fontSize: 12.5, color: secondaryTextColor),
                    ),
                    onTap: () => _copyToClipboard(
                      '@$_username',
                      l10n.translate('username_copied'),
                    ),
                  ),
                  const Divider(height: 1, indent: 56),
                ],
                if (_bio != null && _bio!.isNotEmpty) ...[
                  ListTile(
                    leading: const iconoir.Notes(width: 22, height: 22),
                    title: Text(
                      _bio!,
                      style: TextStyle(
                        fontSize: 15,
                        color: primaryTextColor,
                      ),
                    ),
                    subtitle: Text(
                      l10n.translate('settings_bio'),
                      style: TextStyle(fontSize: 12.5, color: secondaryTextColor),
                    ),
                  ),
                  const Divider(height: 1, indent: 56),
                ],
                ListTile(
                  leading: const iconoir.Fingerprint(width: 22, height: 22),
                  title: Text(
                    widget.userId,
                    style: TextStyle(
                      fontSize: 14,
                      color: primaryTextColor,
                    ),
                  ),
                  subtitle: Text(
                    'User ID',
                    style: TextStyle(fontSize: 12.5, color: secondaryTextColor),
                  ),
                  onTap: () => _copyToClipboard(
                    widget.userId,
                    'User ID copied',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4. Карточка действий с чатом
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const iconoir.MediaImage(width: 22, height: 22),
                  title: Text(
                    l10n.translate('media'),
                    style: TextStyle(color: primaryTextColor),
                  ),
                  trailing: const iconoir.NavArrowRight(width: 18, height: 18),
                  onTap: () {},
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const iconoir.Pin(width: 22, height: 22),
                  title: Text(
                    l10n.translate('pinned_messages'),
                    style: TextStyle(color: primaryTextColor),
                  ),
                  trailing: const iconoir.NavArrowRight(width: 18, height: 18),
                  onTap: () {},
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const iconoir.HandBrake(
                    width: 22,
                    height: 22,
                    color: Colors.redAccent,
                  ),
                  title: Text(
                    l10n.translate('block_user'),
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () {
                    // Block user action
                    HapticUtils.tap();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: cardColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(child: icon),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
