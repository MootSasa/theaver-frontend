import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../utils/swipe_back_route.dart';
import '../auth/login_screen.dart';
import 'about_theaver_screen.dart';
import 'accounts_screen.dart';
import 'badge_settings_screen.dart';
import 'blocked_users_screen.dart';
import 'bots_and_mini_apps_screen.dart';
import 'change_email_screen.dart';
import 'chat_settings_screen.dart';
import 'chat_type_notifications_screen.dart';
import 'devices_screen.dart';
import 'edit_profile_screen.dart';
import 'folder_edit_screen.dart';
import 'folders_screen.dart';
import 'language_screen.dart';
import 'notification_exceptions_screen.dart';
import 'notifications_screen.dart';
import 'passcode_screen.dart';
import 'power_saving_screen.dart';
import 'privacy_screen.dart';
import 'profile_customization_screen.dart';
import 'profile_screen.dart';
import 'security_screen.dart';
import 'storage_screen.dart';
import 'wallpaper_screen.dart';

/// Descriptor for a searchable item inside SettingsScreen.
class SettingsSearchEntry {
  final String id;
  final String titleKey;
  final String fallbackTitle;
  final String sectionKey;
  final String fallbackSection;
  final List<String> keywords;
  final IconData icon;
  final bool isWebHidden;
  final void Function(BuildContext context)? onSelect;

  const SettingsSearchEntry({
    required this.id,
    required this.titleKey,
    required this.fallbackTitle,
    required this.sectionKey,
    required this.fallbackSection,
    required this.keywords,
    required this.icon,
    this.isWebHidden = false,
    this.onSelect,
  });

  String resolveTitle(String Function(String)? translate) {
    final t = translate?.call(titleKey);
    if (t == null || t == titleKey || t.trim().isEmpty) return fallbackTitle;
    return t;
  }

  String resolveSection(String Function(String)? translate) {
    final t = translate?.call(sectionKey);
    if (t == null || t == sectionKey || t.trim().isEmpty) {
      return fallbackSection;
    }
    return t;
  }
}

/// Centralized settings search catalog supporting localized RU/EN queries
/// and platform filtering (e.g. hiding native update entries on Web).
class SettingsSearchIndex {
  SettingsSearchIndex._();

  static void _push(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      SwipeBackPageRoute(builder: (_) => screen),
    );
  }

  static List<SettingsSearchEntry> defaultEntries() {
    return [
      SettingsSearchEntry(
        id: 'profile',
        titleKey: 'settings_profile',
        fallbackTitle: 'Мой профиль',
        sectionKey: 'accounts_title',
        fallbackSection: 'Профиль и аккаунт',
        keywords: const ['profile', 'профиль', 'аватар', 'био', 'имя', 'юзернейм'],
        icon: Icons.person_outline,
        onSelect: (c) => _push(c, const ProfileScreen()),
      ),
      SettingsSearchEntry(
        id: 'edit_profile',
        titleKey: 'edit_profile',
        fallbackTitle: 'Редактировать профиль',
        sectionKey: 'settings_profile',
        fallbackSection: 'Профиль и аккаунт',
        keywords: const ['edit', 'name', 'birthday', 'редактировать', 'день рождения', 'имя', 'о себе'],
        icon: Icons.edit_outlined,
        onSelect: (c) => _push(c, const EditProfileScreen()),
      ),
      SettingsSearchEntry(
        id: 'accounts',
        titleKey: 'accounts_title',
        fallbackTitle: 'Аккаунты',
        sectionKey: 'accounts_title',
        fallbackSection: 'Профиль и аккаунт',
        keywords: const ['accounts', 'switch', 'аккаунты', 'переключить', 'несколько'],
        icon: Icons.manage_accounts_outlined,
        onSelect: (c) => _push(c, const AccountsScreen()),
      ),
      SettingsSearchEntry(
        id: 'add_account',
        titleKey: 'settings_add_account',
        fallbackTitle: 'Добавить аккаунт',
        sectionKey: 'accounts_title',
        fallbackSection: 'Профиль и аккаунт',
        keywords: const ['add', 'login', 'войти', 'добавить аккаунт'],
        icon: Icons.person_add_outlined,
        onSelect: (c) => _push(c, const LoginScreen()),
      ),
      SettingsSearchEntry(
        id: 'privacy',
        titleKey: 'settings_privacy',
        fallbackTitle: 'Конфиденциальность',
        sectionKey: 'settings_privacy',
        fallbackSection: 'Приватность и безопасность',
        keywords: const ['privacy', 'last seen', 'birthday', 'приватность', 'был в сети', 'фото'],
        icon: Icons.shield_outlined,
        onSelect: (c) => _push(c, const PrivacyScreen()),
      ),
      SettingsSearchEntry(
        id: 'security_2fa',
        titleKey: 'security_title',
        fallbackTitle: 'Безопасность и 2FA',
        sectionKey: 'settings_privacy',
        fallbackSection: 'Приватность и безопасность',
        keywords: const ['2fa', 'two-factor', 'password', 'recovery', 'двухфакторная', 'пароль', 'облачный'],
        icon: Icons.security_outlined,
        onSelect: (c) => _push(c, const SecurityScreen()),
      ),
      SettingsSearchEntry(
        id: 'passcode_lock',
        titleKey: 'passcode_title',
        fallbackTitle: 'Код-пароль и блокировка',
        sectionKey: 'settings_privacy',
        fallbackSection: 'Приватность и безопасность',
        keywords: const ['pin', 'passcode', 'biometric', 'lock', 'код', 'пин', 'биометрия', 'блокировка'],
        icon: Icons.pin_outlined,
        onSelect: (c) => _push(c, const PasscodeScreen()),
      ),
      SettingsSearchEntry(
        id: 'recovery_email',
        titleKey: 'email_verify_title',
        fallbackTitle: 'Почта и смена e-mail',
        sectionKey: 'settings_privacy',
        fallbackSection: 'Приватность и безопасность',
        keywords: const ['email', 'mail', 'otp', 'почта', 'сменить почту', 'подтвердить'],
        icon: Icons.mail_outline,
        onSelect: (c) => _push(c, const ChangeEmailScreen()),
      ),
      SettingsSearchEntry(
        id: 'blocked_users',
        titleKey: 'blocked_users_title',
        fallbackTitle: 'Чёрный список',
        sectionKey: 'settings_privacy',
        fallbackSection: 'Приватность и безопасность',
        keywords: const ['blocked', 'ban', 'чёрный список', 'заблокированные'],
        icon: Icons.block_outlined,
        onSelect: (c) => _push(c, const BlockedUsersScreen()),
      ),
      SettingsSearchEntry(
        id: 'delete_account',
        titleKey: 'security_delete_account_title',
        fallbackTitle: 'Удалить аккаунт',
        sectionKey: 'settings_privacy',
        fallbackSection: 'Приватность и безопасность',
        keywords: const ['delete account', 'remove account', 'удалить аккаунт', 'удаление'],
        icon: Icons.delete_outline,
        onSelect: (c) => _push(c, const SecurityScreen()),
      ),
      SettingsSearchEntry(
        id: 'devices',
        titleKey: 'settings_devices',
        fallbackTitle: 'Устройства и QR-вход',
        sectionKey: 'settings_devices',
        fallbackSection: 'Сессии и устройства',
        keywords: const ['devices', 'sessions', 'qr', 'устройства', 'сессии', 'подключить'],
        icon: Icons.devices_outlined,
        onSelect: (c) => _push(c, const DevicesScreen()),
      ),
      SettingsSearchEntry(
        id: 'notifications',
        titleKey: 'settings_notifications',
        fallbackTitle: 'Уведомления и звуки',
        sectionKey: 'settings_notifications',
        fallbackSection: 'Уведомления',
        keywords: const ['notifications', 'sound', 'keywords', 'archived', 'уведомления', 'звук', 'ключевые слова'],
        icon: Icons.notifications_none_outlined,
        onSelect: (c) => _push(c, const NotificationsScreen()),
      ),
      SettingsSearchEntry(
        id: 'notif_private',
        titleKey: 'notifications_private_chats',
        fallbackTitle: 'Уведомления: Личные чаты',
        sectionKey: 'settings_notifications',
        fallbackSection: 'Уведомления',
        keywords: const ['private', 'личные', 'звонки', 'уведомления'],
        icon: Icons.person_outline,
        onSelect: (c) => _push(
          c,
          const ChatTypeNotificationsScreen(
            category: ChatCategory.privateChats,
          ),
        ),
      ),
      SettingsSearchEntry(
        id: 'notif_groups',
        titleKey: 'notifications_groups',
        fallbackTitle: 'Уведомления: Группы',
        sectionKey: 'settings_notifications',
        fallbackSection: 'Уведомления',
        keywords: const ['groups', 'группы', 'упоминания', 'уведомления'],
        icon: Icons.group_outlined,
        onSelect: (c) => _push(
          c,
          const ChatTypeNotificationsScreen(
            category: ChatCategory.groupChats,
          ),
        ),
      ),
      SettingsSearchEntry(
        id: 'notif_channels',
        titleKey: 'notifications_channels',
        fallbackTitle: 'Уведомления: Каналы',
        sectionKey: 'settings_notifications',
        fallbackSection: 'Уведомления',
        keywords: const ['channels', 'каналы', 'уведомления'],
        icon: Icons.campaign_outlined,
        onSelect: (c) => _push(
          c,
          const ChatTypeNotificationsScreen(
            category: ChatCategory.channels,
          ),
        ),
      ),
      SettingsSearchEntry(
        id: 'notif_badges',
        titleKey: 'notifications_badges',
        fallbackTitle: 'Счётчик и бейджи',
        sectionKey: 'settings_notifications',
        fallbackSection: 'Уведомления',
        keywords: const ['badge', 'counter', 'unread', 'бейдж', 'счётчик', 'непрочитанные'],
        icon: Icons.mark_chat_unread_outlined,
        onSelect: (c) => _push(c, const BadgeSettingsScreen()),
      ),
      SettingsSearchEntry(
        id: 'notif_exceptions',
        titleKey: 'notifications_exceptions',
        fallbackTitle: 'Исключения уведомлений',
        sectionKey: 'settings_notifications',
        fallbackSection: 'Уведомления',
        keywords: const ['exceptions', 'mute', 'исключения', 'чаты', 'без звука'],
        icon: Icons.tune_outlined,
        onSelect: (c) => _push(c, const NotificationExceptionsScreen()),
      ),
      SettingsSearchEntry(
        id: 'chat_settings',
        titleKey: 'settings_chat_settings',
        fallbackTitle: 'Оформление и настройки чатов',
        sectionKey: 'settings_chat_settings',
        fallbackSection: 'Оформление',
        keywords: const [
          'theme',
          'dark mode',
          'schedule',
          'font size',
          'bubble',
          'glass',
          'swipe',
          'тема',
          'тёмная',
          'расписание',
          'размер шрифта',
          'стекло',
          'свайп',
        ],
        icon: Icons.palette_outlined,
        onSelect: (c) => _push(c, const ChatSettingsScreen()),
      ),
      SettingsSearchEntry(
        id: 'in_app_browser',
        titleKey: 'settings_in_app_browser_title',
        fallbackTitle: 'Встроенный браузер',
        sectionKey: 'settings_chat_settings',
        fallbackSection: 'Оформление',
        keywords: const [
          'browser',
          'links',
          'webview',
          'cookies',
          'history',
          'браузер',
          'ссылки',
          'история',
          'куки',
        ],
        icon: Icons.public_outlined,
        isWebHidden: true,
        onSelect: (c) => _push(c, const ChatSettingsScreen()),
      ),
      SettingsSearchEntry(
        id: 'profile_customization',
        titleKey: 'customizationTitle',
        fallbackTitle: 'Кастомизация профиля',
        sectionKey: 'settings_profile',
        fallbackSection: 'Профиль',
        keywords: const [
          'customization',
          'frame',
          'status',
          'banner',
          'badge',
          'color',
          'рамка',
          'статус',
          'баннер',
          'бейдж',
          'кастомизация',
          'профиль',
        ],
        icon: Icons.auto_awesome_outlined,
        onSelect: (c) => _push(c, const ProfileCustomizationScreen()),
      ),
      SettingsSearchEntry(
        id: 'wallpaper',
        titleKey: 'wallpaper_title',
        fallbackTitle: 'Обои чатов',
        sectionKey: 'settings_chat_settings',
        fallbackSection: 'Оформление',
        keywords: const ['wallpaper', 'background', 'обои', 'фон', 'паттерн'],
        icon: Icons.wallpaper_outlined,
        onSelect: (c) => _push(c, const WallpaperScreen()),
      ),
      SettingsSearchEntry(
        id: 'folders',
        titleKey: 'settings_folders',
        fallbackTitle: 'Папки с чатами',
        sectionKey: 'settings_folders',
        fallbackSection: 'Папки',
        keywords: const ['folders', 'tabs', 'папки', 'вкладки', 'фильтры'],
        icon: Icons.folder_outlined,
        onSelect: (c) => _push(c, const FoldersScreen()),
      ),
      SettingsSearchEntry(
        id: 'bots_mini_apps',
        titleKey: 'settings_bots_mini_apps',
        fallbackTitle: 'Боты и Mini Apps',
        sectionKey: 'settings_bots_mini_apps',
        fallbackSection: 'Боты и приложения',
        keywords: const [
          'bots',
          'botmother',
          'mini app',
          'webapp',
          'inline',
          'боты',
          'мини-приложения',
          'приложения',
          'инлайн',
        ],
        icon: Icons.apps_outlined,
        onSelect: (c) => _push(c, const BotsAndMiniAppsScreen()),
      ),
      SettingsSearchEntry(
        id: 'new_folder',
        titleKey: 'folders_new_folder',
        fallbackTitle: 'Создать папку чатов',
        sectionKey: 'settings_folders',
        fallbackSection: 'Папки',
        keywords: const ['new folder', 'create folder', 'новая папка', 'создать папку'],
        icon: Icons.create_new_folder_outlined,
        onSelect: (c) => _push(c, const FolderEditScreen()),
      ),
      SettingsSearchEntry(
        id: 'storage',
        titleKey: 'settings_data_storage',
        fallbackTitle: 'Данные и память',
        sectionKey: 'settings_data_storage',
        fallbackSection: 'Память',
        keywords: const ['storage', 'cache', 'clear', 'память', 'кэш', 'очистить', 'автозагрузка'],
        icon: Icons.storage_outlined,
        onSelect: (c) => _push(c, const StorageScreen()),
      ),
      SettingsSearchEntry(
        id: 'power_saving',
        titleKey: 'settings_power_saving',
        fallbackTitle: 'Энергосбережение',
        sectionKey: 'settings_power_saving',
        fallbackSection: 'Питание и производительность',
        keywords: const ['power', 'battery', 'animations', 'blur', 'энергия', 'батарея', 'анимации'],
        icon: Icons.battery_charging_full_outlined,
        onSelect: (c) => _push(c, const PowerSavingScreen()),
      ),
      SettingsSearchEntry(
        id: 'language',
        titleKey: 'settings_language',
        fallbackTitle: 'Язык',
        sectionKey: 'settings_language',
        fallbackSection: 'Язык',
        keywords: const ['language', 'locale', 'russian', 'english', 'язык', 'локализация'],
        icon: Icons.language_outlined,
        onSelect: (c) => _push(c, const LanguageScreen()),
      ),
      SettingsSearchEntry(
        id: 'about',
        titleKey: 'settings_about_theaver',
        fallbackTitle: 'О Theaver',
        sectionKey: 'settings_about_theaver',
        fallbackSection: 'О приложении',
        keywords: const ['about', 'version', 'changelog', 'версия', 'о приложении'],
        icon: Icons.info_outline,
        onSelect: (c) => _push(c, const AboutTheaverScreen()),
      ),
      SettingsSearchEntry(
        id: 'app_updates',
        titleKey: 'about_updates_title',
        fallbackTitle: 'Обновления приложения',
        sectionKey: 'settings_about_theaver',
        fallbackSection: 'О приложении',
        keywords: const ['update', 'version', 'channel', 'beta', 'обновление', 'версия', 'канал'],
        icon: Icons.system_update_outlined,
        isWebHidden: true,
        onSelect: (c) => _push(c, const AboutTheaverScreen()),
      ),
    ];
  }

  /// Filters [entries] using tokenized substring matching on localized title,
  /// section, fallback text, and keywords, hiding [isWebHidden] rows on Web.
  static List<SettingsSearchEntry> filter(
    List<SettingsSearchEntry> entries,
    String query, {
    String Function(String key)? translate,
    bool isWeb = kIsWeb,
  }) {
    final normalized = query.trim().toLowerCase();
    final visible = entries.where((e) => !(isWeb && e.isWebHidden));
    if (normalized.isEmpty) {
      return visible.toList();
    }

    final tokens =
        normalized.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    return visible.where((entry) {
      final haystack = <String>[
        entry.resolveTitle(translate).toLowerCase(),
        entry.fallbackTitle.toLowerCase(),
        entry.resolveSection(translate).toLowerCase(),
        entry.fallbackSection.toLowerCase(),
        ...entry.keywords.map((k) => k.toLowerCase()),
      ].join(' ');
      return tokens.every((token) => haystack.contains(token));
    }).toList();
  }
}
