import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:ios_color_picker/show_ios_color_picker.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../models/name_color_preset.dart';
import '../../models/profile_customization.dart';
import '../../services/account_manager.dart';
import '../../services/auth_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/name_color_sync_service.dart';
import '../../services/peer_customization_cache.dart';
import '../../services/profile_theme_provider.dart';
import '../../services/sticker_service.dart';
import '../../theme/theav_theme.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/common/adaptive_switch.dart';
import '../../widgets/common/glass_modal_sheet.dart';
import '../../widgets/common/peer_badges_widget.dart';
import '../../widgets/profile/color_palette_picker.dart';
import '../../widgets/profile/floating_emoji_status_menu.dart';
import '../../widgets/profile/name_color_picker.dart';
import '../../widgets/profile/profile_banner_layer.dart';
import '../../widgets/profile/profile_floating_top_switcher.dart';
import '../../widgets/profile/reply_message_preview_card.dart';
import '../../widgets/settings/settings_group.dart';
import '../../widgets/user/avatar_with_status.dart';
import '../../widgets/user/emoji_status_badge.dart';
import 'profile_banner_editor_screen.dart';

/// Экран «Оформление профиля», визуально совпадающий с реальным экраном профиля:
/// - Полноэкранный цветной/градиентный фон и растворяющийся баннер как на `ProfileScreen`;
/// - Компактная плавающая верхняя шапка с кнопкой `←` и анимированным переключателем
///   `Профиль / Имя в чатах` на базе `LiquidGlassTabBar.buildGlassPillBar` + `PageController`
///   (как в `EmojiStickerPanel`);
/// - Свободная прокрутка 120fps без лишних вложенных двойных панелей;
/// - Выбор эмодзи-статуса и длительности без текстовой заметки.
class ProfileCustomizationScreen extends StatefulWidget {
  final int initialTab;

  const ProfileCustomizationScreen({
    super.key,
    this.initialTab = 0,
  });

  @override
  State<ProfileCustomizationScreen> createState() =>
      _ProfileCustomizationScreenState();
}

class _ProfileCustomizationScreenState
    extends State<ProfileCustomizationScreen> {
  late int _activeTab; // 0 = Профиль, 1 = Имя в чатах
  late final PageController _pageController;
  bool _isAnimatingTabFromBar = false;

  Duration? _selectedDuration; // null = Навсегда
  final IOSColorPickerController _colorPickerController =
      IOSColorPickerController();
  final ScrollController _profileScrollController = ScrollController();
  final ScrollController _nameScrollController = ScrollController();
  final ValueNotifier<double> _bannerScrollOffset = ValueNotifier<double>(0.0);
  final GlobalKey _heroNameRowAnchorKey = GlobalKey();
  final GlobalKey _heroEmojiStatusAnchorKey = GlobalKey();
  final GlobalKey _emojiStatusRowAnchorKey = GlobalKey();

  ProfileColorPreset? _draftCoverPreset;
  NameColorPreset? _draftNamePreset;
  ReplyStripStyle? _draftStripStyle;

  Timer? _coverDebounce;
  Timer? _nameColorDebounce;

  bool _isUploadingBanner = false;
  String? _userId;

  static int _normalizeInitialTab(int raw) => raw == 1 ? 1 : 0;

  static double _computeCoverLuminance(ProfileColorPreset preset) {
    if (preset.isGradient &&
        preset.gradientColors != null &&
        preset.gradientColors!.isNotEmpty) {
      final sum = preset.gradientColors!.fold<double>(
        0.0,
        (acc, c) => acc + c.computeLuminance(),
      );
      return sum / preset.gradientColors!.length;
    }
    return preset.backgroundColor.computeLuminance();
  }

  @override
  void initState() {
    super.initState();
    _activeTab = _normalizeInitialTab(widget.initialTab);
    _pageController = PageController(initialPage: _activeTab);
    _profileScrollController.addListener(_onProfileScroll);

    _userId = AccountManager().currentAccount?.userId;
    if (_userId == null || _userId!.isEmpty) {
      AuthService.getUserId().then((uid) {
        if (mounted && uid != null && uid.isNotEmpty) {
          setState(() => _userId = uid);
        }
      });
    }

    PeerCustomizationCache.instance.refreshCatalogs();
    StickerService.instance.ensureInitialized();

    if (widget.initialTab == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final targetKey = _heroEmojiStatusAnchorKey.currentContext != null
              ? _heroEmojiStatusAnchorKey
              : _heroNameRowAnchorKey;
          _openEmojiStatusMenu(context, anchorKey: targetKey);
        }
      });
    }
  }

  void _onProfileScroll() {
    if (!_profileScrollController.hasClients) return;
    final next = _profileScrollController.offset.clamp(0.0, 260.0);
    if ((next - _bannerScrollOffset.value).abs() > 0.5) {
      _bannerScrollOffset.value = next;
    }
  }

  void _onTabSelectedFromBar(int index) {
    if (index < 0 || index > 1 || _activeTab == index) return;
    HapticUtils.selection();
    setState(() => _activeTab = index);
    if (_pageController.hasClients) {
      _isAnimatingTabFromBar = true;
      _pageController
          .animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
        _isAnimatingTabFromBar = false;
      });
    }
  }

  @override
  void dispose() {
    _flushPendingSync();
    _profileScrollController.removeListener(_onProfileScroll);
    _profileScrollController.dispose();
    _nameScrollController.dispose();
    _pageController.dispose();
    _bannerScrollOffset.dispose();
    _colorPickerController.dispose();
    super.dispose();
  }

  void _flushPendingSync() {
    if (_coverDebounce?.isActive == true) {
      _coverDebounce!.cancel();
      final pending = _draftCoverPreset;
      if (pending != null) {
        context.read<ProfileThemeProvider>().setPreset(pending);
      }
    }
    if (_nameColorDebounce?.isActive == true) {
      _nameColorDebounce!.cancel();
      final preset = _draftNamePreset;
      final style = _draftStripStyle;
      if (preset != null && style != null) {
        final provider = context.read<ProfileThemeProvider>();
        provider.setNameColorAndStyle(preset, style);
        NameColorSyncService().setNameColorAndStyle(
          preset: preset,
          style: style,
        );
      }
    }
  }

  String _displayName() {
    final acc = AccountManager().currentAccount;
    if (acc == null) return 'User';
    final full = '${acc.name ?? ''} ${acc.surname ?? ''}'.trim();
    if (full.isNotEmpty) return full;
    if (acc.username != null && acc.username!.isNotEmpty) {
      return '@${acc.username}';
    }
    return 'User';
  }

  String? _avatarUrl() => AccountManager().currentAccount?.avatarUrl;

  ProfileColorPreset _effectiveCoverPreset(ProfileThemeProvider provider) =>
      _draftCoverPreset ?? provider.currentPreset ?? ProfileColorPresets.blue;

  NameColorPreset _effectiveNamePreset(ProfileThemeProvider provider) =>
      _draftNamePreset ?? provider.currentNameColorPreset;

  ReplyStripStyle _effectiveStripStyle(ProfileThemeProvider provider) =>
      _draftStripStyle ?? provider.currentStripStyle;

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    try {
      GlassToastService().show(
        context,
        message,
        icon: isError
            ? Icons.error_outline_rounded
            : Icons.check_circle_outline_rounded,
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Мгновенные действия: Обложка, Баннер, Рамка, Бейдж
  // ---------------------------------------------------------------------------

  void _onCoverPresetSelected(ProfileColorPreset preset) {
    _coverDebounce?.cancel();
    setState(() => _draftCoverPreset = null);
    context.read<ProfileThemeProvider>().setPreset(preset);
  }

  void _onCoverPresetDragged(ProfileColorPreset preset) {
    setState(() => _draftCoverPreset = preset);
    _coverDebounce?.cancel();
    _coverDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final provider = context.read<ProfileThemeProvider>();
      provider.setPreset(preset);
      setState(() => _draftCoverPreset = null);
    });
  }

  void _pickCustomCoverColor() {
    HapticUtils.selection();
    final provider = context.read<ProfileThemeProvider>();
    final current = _effectiveCoverPreset(provider);
    _colorPickerController.showIOSCustomColorPicker(
      context: context,
      startingColor: current.backgroundColor.withValues(alpha: 1.0),
      onColorChanged: (c) {
        if (!mounted) return;
        _onCoverPresetDragged(
          ProfileColorPreset.fromCustomColor(c.withValues(alpha: 1.0)),
        );
      },
    );
  }

  void _resetCoverColor() {
    HapticUtils.selection();
    _coverDebounce?.cancel();
    setState(() => _draftCoverPreset = null);
    context.read<ProfileThemeProvider>().setPreset(ProfileColorPresets.blue);
  }

  Future<void> _selectDecoration(AvatarDecorationPreset? preset) async {
    final provider = context.read<ProfileThemeProvider>();
    final currentId = provider.currentAvatarDecoration?.id;
    if ((preset == null && (currentId == null || currentId.isEmpty)) ||
        (preset != null && currentId == preset.id)) {
      return;
    }
    HapticUtils.selection();
    final ok = await provider.updateCustomization(
      avatarDecorationId: preset?.id,
      optimisticDecoration: preset,
      clearAvatarDecoration: preset == null,
    );
    if (!ok && mounted) {
      _showToast(
        translateOrFallback(context, 'error', 'Failed to update'),
        isError: true,
      );
    }
  }

  Future<void> _toggleBadgeDisplayed(bool value) async {
    HapticUtils.selection();
    final ok = await context.read<ProfileThemeProvider>().updateCustomization(
          badgeIsDisplayed: value,
        );
    if (!ok && mounted) {
      _showToast(
        translateOrFallback(context, 'error', 'Failed to update'),
        isError: true,
      );
    }
  }

  Future<void> _pickAndUploadBanner() async {
    if (_isUploadingBanner) return;
    HapticUtils.tap();
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif'],
      withData: kIsWeb,
    );
    if (!mounted || picked == null || picked.files.isEmpty) return;

    final file = picked.files.first;
    const maxBytes = 15 * 1024 * 1024;
    if (file.size > maxBytes) {
      _showToast(
        translateOrFallback(
          context,
          'bannerHint',
          'Recommended 16:9 image, up to 15 MB',
        ),
        isError: true,
      );
      return;
    }

    final provider = context.read<ProfileThemeProvider>();
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ProfileBannerEditorScreen(
          initialFilePath: kIsWeb ? null : file.path,
          initialBytes: kIsWeb ? file.bytes : null,
          initialFileName: file.name,
          initialLayout: ProfileBannerLayout(
            heightMode: provider.currentBannerLayout.heightMode,
          ),
          displayName: _displayName(),
          avatarUrl: _avatarUrl(),
          userId: _userId,
        ),
      ),
    );
  }

  Future<void> _openBannerEditor() async {
    if (_isUploadingBanner) return;
    final provider = context.read<ProfileThemeProvider>();
    final bannerUrl = AppConfig.resolveMediaUrl(provider.currentBannerUrl);
    if (bannerUrl == null || bannerUrl.isEmpty) return;
    HapticUtils.tap();
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ProfileBannerEditorScreen(
          initialBannerUrl: bannerUrl,
          initialLayout: provider.currentBannerLayout,
          displayName: _displayName(),
          avatarUrl: _avatarUrl(),
          userId: _userId,
        ),
      ),
    );
  }

  Future<void> _removeBanner() async {
    if (_isUploadingBanner) return;
    HapticUtils.selection();
    setState(() => _isUploadingBanner = true);
    final ok = await context.read<ProfileThemeProvider>().deleteBanner();
    if (!mounted) return;
    setState(() => _isUploadingBanner = false);
    if (!ok) {
      _showToast(
        translateOrFallback(context, 'error', 'Failed to remove banner'),
        isError: true,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Мгновенные действия: Имя и полоска цитирования в чатах
  // ---------------------------------------------------------------------------

  void _applyNameColorImmediate(NameColorPreset preset, ReplyStripStyle style) {
    HapticUtils.selection();
    _nameColorDebounce?.cancel();
    setState(() {
      _draftNamePreset = null;
      _draftStripStyle = null;
    });
    final provider = context.read<ProfileThemeProvider>();
    provider.setNameColorAndStyle(preset, style);
    NameColorSyncService().setNameColorAndStyle(
      preset: preset,
      style: style,
    );
  }

  void _applyNameColorDebounced(NameColorPreset preset, ReplyStripStyle style) {
    setState(() {
      _draftNamePreset = preset;
      _draftStripStyle = style;
    });
    _nameColorDebounce?.cancel();
    _nameColorDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final provider = context.read<ProfileThemeProvider>();
      provider.setNameColorAndStyle(preset, style);
      NameColorSyncService().setNameColorAndStyle(
        preset: preset,
        style: style,
      );
      setState(() {
        _draftNamePreset = null;
        _draftStripStyle = null;
      });
    });
  }

  void _resetNameColor() {
    _applyNameColorImmediate(NameColorPresets.red, ReplyStripStyle.solid);
  }

  Future<void> _pickCustomNameColor() async {
    HapticUtils.selection();
    final provider = context.read<ProfileThemeProvider>();
    final currentPreset = _effectiveNamePreset(provider);
    final currentStyle = _effectiveStripStyle(provider);
    final c1 = currentPreset.primaryColor;
    final c2 = currentPreset.effectiveSecondary;
    final c3 = currentPreset.effectiveTertiary;

    if (currentStyle == ReplyStripStyle.solid) {
      _colorPickerController.showIOSCustomColorPicker(
        context: context,
        startingColor: c1,
        onColorChanged: (c) {
          if (!mounted) return;
          _applyNameColorDebounced(
            NameColorPreset.fromCustomColor(c.withValues(alpha: 1.0)),
            currentStyle,
          );
        },
      );
      return;
    }

    Color draft1 = c1;
    Color draft2 = c2;
    Color draft3 = c3;
    await showTheavGlassModalSheet<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                translateOrFallback(
                  sheetCtx,
                  'customizationNameColorTitle',
                  'Name Color',
                ),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _colorSwatchButton(
                    sheetCtx,
                    draft1,
                    translateOrFallback(
                      sheetCtx,
                      'customizationFirstColor',
                      'First color',
                    ),
                    () {
                      _colorPickerController.showIOSCustomColorPicker(
                        context: sheetCtx,
                        startingColor: draft1,
                        onColorChanged: (c) {
                          final opaque = c.withValues(alpha: 1.0);
                          setSheet(() => draft1 = opaque);
                          final updated =
                              currentStyle == ReplyStripStyle.candyCane
                                  ? NameColorPreset.fromCustomTriple(
                                      draft1,
                                      draft2,
                                      draft3,
                                    )
                                  : NameColorPreset.fromCustomGradient(
                                      draft1,
                                      draft2,
                                    );
                          _applyNameColorDebounced(updated, currentStyle);
                        },
                      );
                    },
                  ),
                  _colorSwatchButton(
                    sheetCtx,
                    draft2,
                    translateOrFallback(
                      sheetCtx,
                      'customizationSecondColor',
                      'Second color',
                    ),
                    () {
                      _colorPickerController.showIOSCustomColorPicker(
                        context: sheetCtx,
                        startingColor: draft2,
                        onColorChanged: (c) {
                          final opaque = c.withValues(alpha: 1.0);
                          setSheet(() => draft2 = opaque);
                          final updated =
                              currentStyle == ReplyStripStyle.candyCane
                                  ? NameColorPreset.fromCustomTriple(
                                      draft1,
                                      draft2,
                                      draft3,
                                    )
                                  : NameColorPreset.fromCustomGradient(
                                      draft1,
                                      draft2,
                                    );
                          _applyNameColorDebounced(updated, currentStyle);
                        },
                      );
                    },
                  ),
                  if (currentStyle == ReplyStripStyle.candyCane)
                    _colorSwatchButton(
                      sheetCtx,
                      draft3,
                      translateOrFallback(
                        sheetCtx,
                        'customizationThirdColor',
                        'Third color',
                      ),
                      () {
                        _colorPickerController.showIOSCustomColorPicker(
                          context: sheetCtx,
                          startingColor: draft3,
                          onColorChanged: (c) {
                            final opaque = c.withValues(alpha: 1.0);
                            setSheet(() => draft3 = opaque);
                            _applyNameColorDebounced(
                              NameColorPreset.fromCustomTriple(
                                draft1,
                                draft2,
                                draft3,
                              ),
                              currentStyle,
                            );
                          },
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: 0.12),
                    foregroundColor: theme.colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.of(sheetCtx).pop(),
                  child: Text(
                    translateOrFallback(sheetCtx, 'ok', 'OK'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _colorSwatchButton(
    BuildContext context,
    Color color,
    String label,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.38)
                    : Colors.black.withValues(alpha: 0.16),
                width: 2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Мгновенные действия: Эмодзи-статус и срок действия (без текстовой заметки)
  // ---------------------------------------------------------------------------

  DateTime? _computeExpiresAt() => _selectedDuration != null
      ? DateTime.now().toUtc().add(_selectedDuration!)
      : null;

  Future<void> _selectUnicodeStatus(String emoji) async {
    final trimmed = emoji.trim();
    if (trimmed.isEmpty) return;
    HapticUtils.selection();
    final until = _computeExpiresAt();
    final optimistic = EmojiStatusData(
      type: 'unicode',
      emoji: trimmed,
      note: '',
      expiresAt: until,
    );
    await context.read<ProfileThemeProvider>().updateCustomization(
          emojiStatusUnicode: trimmed,
          optimisticEmojiStatus: optimistic,
          emojiStatusNote: '',
          emojiStatusUntil: until,
          clearEmojiStatusUntil: until == null,
        );
  }

  Future<void> _selectCustomStickerStatus(StickerItem sticker) async {
    HapticUtils.selection();
    final until = _computeExpiresAt();
    final optimistic = EmojiStatusData(
      type: 'sticker',
      stickerId: sticker.id,
      stickerUrl: sticker.fileUrl,
      thumbnailUrl: sticker.thumbnailUrl,
      stickerFormat: sticker.format,
      note: '',
      expiresAt: until,
    );
    await context.read<ProfileThemeProvider>().updateCustomization(
          emojiStatusStickerId: sticker.id,
          optimisticEmojiStatus: optimistic,
          emojiStatusNote: '',
          emojiStatusUntil: until,
          clearEmojiStatusUntil: until == null,
        );
  }

  Future<void> _onDurationSelected(Duration? duration) async {
    HapticUtils.selection();
    setState(() => _selectedDuration = duration);
    final provider = context.read<ProfileThemeProvider>();
    final active = provider.currentEmojiStatus;
    if (active == null) return;
    final until = _computeExpiresAt();
    await provider.updateCustomization(
      emojiStatusUnicode: active.type == 'unicode' ? active.emoji : null,
      emojiStatusStickerId:
          active.type == 'sticker' ? active.stickerId : null,
      optimisticEmojiStatus: EmojiStatusData(
        type: active.type,
        emoji: active.emoji,
        stickerId: active.stickerId,
        stickerUrl: active.stickerUrl,
        thumbnailUrl: active.thumbnailUrl,
        stickerFormat: active.stickerFormat,
        note: '',
        expiresAt: until,
      ),
      emojiStatusNote: '',
      emojiStatusUntil: until,
      clearEmojiStatusUntil: until == null,
    );
  }

  Future<void> _clearEmojiStatus() async {
    HapticUtils.selection();
    await context.read<ProfileThemeProvider>().updateCustomization(
          clearEmojiStatus: true,
        );
  }

  String _statusSubtitle(BuildContext context, EmojiStatusData? activeStatus) {
    if (activeStatus != null) {
      if (_selectedDuration == const Duration(hours: 1)) {
        return translateOrFallback(context, 'emojiStatusExpiry1h', '1 hour');
      }
      if (_selectedDuration == const Duration(hours: 4)) {
        return translateOrFallback(context, 'emojiStatusExpiry4h', '4 hours');
      }
      if (_selectedDuration == const Duration(hours: 24)) {
        return translateOrFallback(context, 'emojiStatusExpiry24h', '24 hours');
      }
      if (_selectedDuration == const Duration(days: 7)) {
        return translateOrFallback(context, 'emojiStatusExpiry7d', '7 days');
      }
      return translateOrFallback(context, 'emojiStatusExpiryNever', 'Forever');
    }
    return translateOrFallback(
      context,
      'emojiStatusSelectHint',
      'Choose an emoji',
    );
  }

  Future<void> _openEmojiStatusMenu(
    BuildContext context, {
    GlobalKey? anchorKey,
  }) async {
    HapticUtils.tap();
    await showFloatingEmojiStatusMenu(
      context: context,
      anchorKey: anchorKey,
      selectedDuration: _selectedDuration,
      onEmojiSelected: _selectUnicodeStatus,
      onCustomEmojiSelected: _selectCustomStickerStatus,
      onDurationSelected: _onDurationSelected,
      onClearStatus: _clearEmojiStatus,
      accentColor: TheavTheme.of(context).accent,
    );
  }

  // ---------------------------------------------------------------------------
  // Шторка «Все бейджи платформы»
  // ---------------------------------------------------------------------------

  Future<void> _showAllBadgesSheet(
    BuildContext context,
    UserBadge? ownBadge,
    List<UserBadge> catalog,
  ) async {
    HapticUtils.tap();
    await showTheavGlassModalSheet<void>(
      context: context,
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        final isDark = theme.brightness == Brightness.dark;
        final theav = TheavTheme.of(sheetCtx);

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                translateOrFallback(
                  sheetCtx,
                  'customizationAllBadges',
                  'All Platform Badges',
                ),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                translateOrFallback(
                  sheetCtx,
                  'badgesSingleHint',
                  'Only one badge can be active on a profile',
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theav.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: SettingsGroup(
                    margin: EdgeInsets.zero,
                    children: [
                      for (final badge in catalog)
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          leading: PeerBadgesRow.buildCapsule(
                            label: badge.shortTag,
                            color: badge.accentColor,
                            isDark: isDark,
                          ),
                          title: Text(
                            translateOrFallback(
                              sheetCtx,
                              badge.nameKey,
                              badge.shortTag,
                            ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            translateOrFallback(sheetCtx, badge.descKey, ''),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theav.textSecondary,
                            ),
                          ),
                          trailing: ownBadge?.id == badge.id
                              ? iconoir.Check(
                                  width: 20,
                                  height: 20,
                                  color: badge.accentColor,
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Вкладка 0: «Профиль» (визуально 1:1 как реальный ProfileScreen)
  // ---------------------------------------------------------------------------

  Widget _buildProfileTab({
    required BuildContext context,
    required ProfileThemeProvider themeProvider,
    required PeerCustomizationCache cache,
    required ProfileColorPreset coverPreset,
    required bool isDarkBackdrop,
    required double topContentPadding,
  }) {
    final displayName = _displayName();
    final avatarUrl = _avatarUrl();
    final bannerUrl = AppConfig.resolveMediaUrl(themeProvider.currentBannerUrl);
    final hasBanner = bannerUrl != null && bannerUrl.isNotEmpty;
    final activeStatus = themeProvider.currentEmojiStatus;

    final onCoverForeground =
        isDarkBackdrop ? Colors.white : const Color(0xFF1C1C1E);
    final secondaryForeground = isDarkBackdrop
        ? Colors.white.withValues(alpha: 0.62)
        : const Color(0xFF6C6C70);
    final statusTextColor =
        isDarkBackdrop ? coverPreset.statusColor : const Color(0xFF007AFF);
    final sectionAccent =
        isDarkBackdrop ? coverPreset.ringColor : const Color(0xFF0088CC);
    final destructiveColor =
        isDarkBackdrop ? const Color(0xFFFF6B6B) : const Color(0xFFD32F2F);

    final currentDecorationId = themeProvider.currentAvatarDecoration?.id;
    final decorations = cache.decorationsCatalog;
    final ownBadge = themeProvider.currentOwnBadge;

    return ListView(
      key: const PageStorageKey<String>('profile_customization_tab_profile'),
      controller: _profileScrollController,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.only(top: topContentPadding, bottom: 44),
      children: [
        // 0. Живая шапка профиля как на реальном ProfileScreen (без кружка «в сети» у аватара)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
          child: Column(
            children: [
              AvatarWithStatus(
                userId: _userId,
                avatarUrl: avatarUrl,
                name: displayName,
                radius: 55,
                isOnline: false,
                decorationOverride: themeProvider.currentAvatarDecoration,
                showDecoration: true,
                animateDecoration: true,
              ),
              const SizedBox(height: 12),
              Row(
                key: _heroNameRowAnchorKey,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      displayName,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: onCoverForeground,
                      ),
                    ),
                  ),
                  if (activeStatus != null) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      key: _heroEmojiStatusAnchorKey,
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openEmojiStatusMenu(
                        context,
                        anchorKey: _heroEmojiStatusAnchorKey,
                      ),
                      child: EmojiStatusBadge(
                        status: activeStatus,
                        size: 20,
                        animate: true,
                        interactive: false,
                        fallbackColor: onCoverForeground,
                      ),
                    ),
                  ],
                  if (themeProvider.currentVisibleBadge != null)
                    PeerBadgesRow(
                      isBot: false,
                      isVerified: false,
                      badge: themeProvider.currentVisibleBadge,
                      interactiveBadge: false,
                      accentColor: coverPreset.ringColor,
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                translateOrFallback(context, 'profile_online', 'online'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: statusTextColor,
                ),
              ),
            ],
          ),
        ),

        // 1. Обложка и баннер
        ProfileGlassSection(
          title: translateOrFallback(
            context,
            'customizationSectionCoverBanner',
            'Cover & Banner',
          ),
          isDarkBackdrop: isDarkBackdrop,
          accentColor: sectionAccent,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: ColorPalettePicker(
                selectedPreset: coverPreset,
                onSelect: _onCoverPresetSelected,
                onPickCustomColor: _pickCustomCoverColor,
              ),
            ),
            ListTile(
              leading: iconoir.MediaImage(
                width: 22,
                height: 22,
                color: sectionAccent,
              ),
              title: Text(
                translateOrFallback(context, 'bannerUpload', 'Upload Banner'),
              ),
              subtitle: Text(
                translateOrFallback(
                  context,
                  'bannerHint',
                  'Recommended 16:9 image, up to 15 MB',
                ),
              ),
              trailing: _isUploadingBanner
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: sectionAccent,
                      ),
                    )
                  : iconoir.NavArrowRight(
                      width: 18,
                      height: 18,
                      color: secondaryForeground,
                    ),
              onTap: _isUploadingBanner ? null : _pickAndUploadBanner,
            ),
            if (hasBanner)
              ListTile(
                key: const ValueKey<String>('profile_banner_adjust_row'),
                leading: Icon(
                  Icons.tune_rounded,
                  size: 22,
                  color: sectionAccent,
                ),
                title: Text(
                  translateOrFallback(
                    context,
                    'bannerAdjust',
                    'Adjust Banner',
                  ),
                ),
                subtitle: Text(
                  translateOrFallback(
                    context,
                    'bannerAdjustHint',
                    'Size, position, dimming & blur',
                  ),
                ),
                trailing: iconoir.NavArrowRight(
                  width: 18,
                  height: 18,
                  color: secondaryForeground,
                ),
                onTap: _isUploadingBanner ? null : _openBannerEditor,
              ),
            if (hasBanner)
              ListTile(
                leading: iconoir.Trash(
                  width: 22,
                  height: 22,
                  color: destructiveColor,
                ),
                title: Text(
                  translateOrFallback(context, 'bannerRemove', 'Remove Banner'),
                  style: TextStyle(color: destructiveColor),
                ),
                onTap: _isUploadingBanner ? null : _removeBanner,
              ),
            if (coverPreset.id != ProfileColorPresets.blue.id)
              ListTile(
                leading: iconoir.RefreshDouble(
                  width: 22,
                  height: 22,
                  color: secondaryForeground,
                ),
                title: Text(
                  translateOrFallback(
                    context,
                    'customizationResetCover',
                    'Reset Cover Color',
                  ),
                ),
                onTap: _resetCoverColor,
              ),
          ],
        ),

        // 2. Эмодзи-статус (плавающее меню выбора как в Telegram)
        ProfileGlassSection(
          title: translateOrFallback(
            context,
            'emojiStatusTitle',
            'Emoji Status',
          ),
          isDarkBackdrop: isDarkBackdrop,
          accentColor: sectionAccent,
          children: [
            ListTile(
              key: const ValueKey<String>('profile_emoji_status_row'),
              leading: activeStatus != null
                  ? EmojiStatusBadge(
                      status: activeStatus,
                      size: 24,
                      animate: true,
                      interactive: false,
                      fallbackColor: sectionAccent,
                    )
                  : iconoir.Emoji(
                      width: 22,
                      height: 22,
                      color: sectionAccent,
                    ),
              title: Text(
                translateOrFallback(
                  context,
                  'emojiStatusTitle',
                  'Emoji Status',
                ),
              ),
              subtitle: Text(
                _statusSubtitle(context, activeStatus),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (activeStatus != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: translateOrFallback(
                        context,
                        'emojiStatusClear',
                        'Clear Status',
                      ),
                      onPressed: _clearEmojiStatus,
                      icon: iconoir.Xmark(
                        width: 18,
                        height: 18,
                        color: secondaryForeground,
                      ),
                    ),
                  KeyedSubtree(
                    key: _emojiStatusRowAnchorKey,
                    child: activeStatus != null
                        ? EmojiStatusBadge(
                            status: activeStatus,
                            size: 22,
                            animate: true,
                            interactive: false,
                            fallbackColor: sectionAccent,
                          )
                        : iconoir.Emoji(
                            width: 20,
                            height: 20,
                            color: secondaryForeground,
                          ),
                  ),
                  const SizedBox(width: 4),
                  iconoir.NavArrowRight(
                    width: 18,
                    height: 18,
                    color: secondaryForeground,
                  ),
                ],
              ),
              onTap: () => _openEmojiStatusMenu(
                context,
                anchorKey: _emojiStatusRowAnchorKey,
              ),
            ),
          ],
        ),

        // 3. Рамка аватара
        ProfileGlassSection(
          title: translateOrFallback(
            context,
            'customizationSectionAvatarFrame',
            'Avatar Frame',
          ),
          isDarkBackdrop: isDarkBackdrop,
          accentColor: sectionAccent,
          children: [
            SizedBox(
              height: 112,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                itemCount: decorations.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (ctx, index) {
                  final isNone = index == 0;
                  final preset = isNone ? null : decorations[index - 1];
                  final isSelected = isNone
                      ? (currentDecorationId == null ||
                          currentDecorationId.isEmpty)
                      : currentDecorationId == preset!.id;
                  final label = isNone
                      ? translateOrFallback(ctx, 'decoNone', 'None')
                      : translateOrFallback(ctx, preset!.nameKey, preset.id);

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _selectDecoration(preset),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        width: 82,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDarkBackdrop
                                  ? Colors.white.withValues(alpha: 0.16)
                                  : sectionAccent.withValues(alpha: 0.12))
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AvatarWithStatus(
                              avatarUrl: avatarUrl,
                              name: displayName,
                              radius: 24,
                              isOnline: false,
                              decorationOverride: preset,
                              showDecoration: preset != null,
                              animateDecoration: isSelected,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSelected
                                    ? onCoverForeground
                                    : secondaryForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),

        // 4. Бейдж профиля
        ProfileGlassSection(
          title: translateOrFallback(
            context,
            'customizationSectionBadge',
            'Profile Badge',
          ),
          isDarkBackdrop: isDarkBackdrop,
          accentColor: sectionAccent,
          children: [
            if (ownBadge != null)
              ListTile(
                leading: PeerBadgesRow.buildCapsule(
                  label: ownBadge.shortTag,
                  color: ownBadge.accentColor,
                  isDark: isDarkBackdrop,
                ),
                title: Text(
                  translateOrFallback(
                    context,
                    ownBadge.nameKey,
                    ownBadge.shortTag,
                  ),
                ),
                subtitle: Text(
                  translateOrFallback(
                    context,
                    'badgesDisplaySwitch',
                    'Show badge next to name',
                  ),
                ),
                trailing: AdaptiveSwitch(
                  value: themeProvider.isBadgeDisplayed,
                  onChanged: _toggleBadgeDisplayed,
                ),
                onTap: () =>
                    _toggleBadgeDisplayed(!themeProvider.isBadgeDisplayed),
              )
            else
              ListTile(
                leading: iconoir.Medal(
                  width: 22,
                  height: 22,
                  color: secondaryForeground,
                ),
                title: Text(
                  translateOrFallback(
                    context,
                    'badgesEmpty',
                    "You don't have a badge assigned yet",
                  ),
                  style: TextStyle(
                    fontSize: 14.5,
                    color: secondaryForeground,
                  ),
                ),
              ),
            ListTile(
              leading: iconoir.InfoCircle(
                width: 22,
                height: 22,
                color: sectionAccent,
              ),
              title: Text(
                translateOrFallback(
                  context,
                  'customizationAllBadges',
                  'All Platform Badges',
                ),
              ),
              trailing: iconoir.NavArrowRight(
                width: 18,
                height: 18,
                color: secondaryForeground,
              ),
              onTap: () => _showAllBadgesSheet(
                context,
                ownBadge,
                cache.badgesCatalog,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Вкладка 1: «Имя в чатах» (чистый дизайн в духе Telegram без вложенных двойных панелей)
  // ---------------------------------------------------------------------------

  Widget _buildNameTab({
    required BuildContext context,
    required ProfileThemeProvider themeProvider,
    required ProfileColorPreset coverPreset,
    required bool isDarkBackdrop,
    required double topContentPadding,
  }) {
    final displayName = _displayName();
    final avatarUrl = _avatarUrl();
    final namePreset = _effectiveNamePreset(themeProvider);
    final stripStyle = _effectiveStripStyle(themeProvider);
    final isNonDefault = namePreset.id != NameColorPresets.red.id ||
        stripStyle != ReplyStripStyle.solid;
    final secondaryForeground = isDarkBackdrop
        ? Colors.white.withValues(alpha: 0.62)
        : const Color(0xFF6C6C70);
    final sectionAccent =
        isDarkBackdrop ? coverPreset.ringColor : const Color(0xFF0088CC);

    return ListView(
      key: const PageStorageKey<String>('profile_customization_tab_name'),
      controller: _nameScrollController,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.only(top: topContentPadding, bottom: 44),
      children: [
        // 1. Одиночный холст предпросмотра сообщения в чате (без обёртки во вторую панель!)
        ReplyMessagePreviewCard(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          isDarkBackdropOverride: isDarkBackdrop,
          preset: namePreset,
          stripStyle: stripStyle,
          userName: displayName,
          avatarUrl: avatarUrl,
          userId: _userId,
          avatarDecoration: themeProvider.currentAvatarDecoration,
          emojiStatus: themeProvider.currentEmojiStatus,
          badge: themeProvider.currentVisibleBadge,
        ),

        // 2. Единая аккуратная панель выбора цвета имени и стиля полоски цитирования
        ProfileGlassSection(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          isDarkBackdrop: isDarkBackdrop,
          accentColor: sectionAccent,
          dividerIndent: 16,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: NameColorPaletteRow(
                selectedPreset: namePreset,
                selectedStyle: stripStyle,
                isDarkOverride: isDarkBackdrop,
                onPresetSelected: (preset) =>
                    _applyNameColorImmediate(preset, stripStyle),
                onPickCustomColor: _pickCustomNameColor,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ReplyStripStyleSelector(
                selectedPreset: namePreset,
                selectedStyle: stripStyle,
                flatInCard: true,
                isDarkOverride: isDarkBackdrop,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                onStyleSelected: (style) =>
                    _applyNameColorImmediate(namePreset, style),
              ),
            ),
            if (isNonDefault)
              ListTile(
                leading: iconoir.RefreshDouble(
                  width: 20,
                  height: 20,
                  color: secondaryForeground,
                ),
                title: Text(
                  translateOrFallback(
                    context,
                    'customizationResetNameColor',
                    'Reset Name Color',
                  ),
                ),
                onTap: _resetNameColor,
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final glassProvider = context.watch<LiquidGlassProvider>();
    final themeProvider = context.watch<ProfileThemeProvider>();
    final cache = context.watch<PeerCustomizationCache>();

    final coverPreset = _effectiveCoverPreset(themeProvider);
    final isDarkBackdrop = _computeCoverLuminance(coverPreset) < 0.60;
    final baseBgColor = coverPreset.isGradient &&
            coverPreset.gradientColors != null &&
            coverPreset.gradientColors!.isNotEmpty
        ? coverPreset.gradientColors!.last
        : coverPreset.backgroundColor;

    final bannerUrl = AppConfig.resolveMediaUrl(themeProvider.currentBannerUrl);
    final showBanner =
        _activeTab == 0 && bannerUrl != null && bannerUrl.isNotEmpty;

    final statusBarHeight = MediaQuery.paddingOf(context).top;
    final headerTopY = statusBarHeight + 8.0;
    final topContentPadding = headerTopY + kProfileFloatingBarHeight + 14.0;

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          isDarkBackdrop ? Brightness.light : Brightness.dark,
      statusBarBrightness:
          isDarkBackdrop ? Brightness.dark : Brightness.light,
    );

    final labels = <String>[
      translateOrFallback(
        context,
        'customizationSegmentProfile',
        'Profile',
      ),
      translateOrFallback(
        context,
        'customizationSegmentName',
        'Chat Name',
      ),
    ];

    final pageBackdropAndScroll = Stack(
      fit: StackFit.expand,
      children: [
        // 1. Полноэкранный адаптивный фон и градиент как на реальном ProfileScreen
        Positioned.fill(
          key: const ValueKey<String>('profile_customization_bg'),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            decoration: coverPreset.isGradient &&
                    coverPreset.gradientColors != null
                ? BoxDecoration(
                    gradient: LinearGradient(
                      colors: coverPreset.gradientColors!,
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  )
                : BoxDecoration(color: baseBgColor),
          ),
        ),

        // 2. Растворяющийся верхний баннер профиля (без setState во время скролла)
        if (showBanner)
          Positioned(
            key: const ValueKey<String>('profile_customization_banner'),
            top: 0,
            left: 0,
            right: 0,
            height: themeProvider.currentBannerLayout.heightMode
                .resolveCustomizationHeight(
                  topContentPadding,
                  devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                ),
            child: IgnorePointer(
              child: ValueListenableBuilder<double>(
                valueListenable: _bannerScrollOffset,
                builder: (context, offset, child) {
                  final opacity = (1.0 - (offset / 180.0)).clamp(0.0, 1.0);
                  if (opacity <= 0.01) return const SizedBox.shrink();
                  return Opacity(
                    opacity: opacity,
                    child: child,
                  );
                },
                child: ProfileBannerLayer(
                  bannerUrl: bannerUrl,
                  layout: themeProvider.currentBannerLayout,
                  animate: true,
                ),
              ),
            ),
          ),

        // 3. Плавный горизонтальный PageView с независимой прокруткой каждой вкладки
        Positioned.fill(
          key: const ValueKey<String>('profile_customization_pageview'),
          child: PageView(
            controller: _pageController,
            physics: const ClampingScrollPhysics(),
            onPageChanged: (index) {
              if (_isAnimatingTabFromBar) return;
              HapticUtils.selection();
              setState(() => _activeTab = index);
            },
            children: [
              _buildProfileTab(
                context: context,
                themeProvider: themeProvider,
                cache: cache,
                coverPreset: coverPreset,
                isDarkBackdrop: isDarkBackdrop,
                topContentPadding: topContentPadding,
              ),
              _buildNameTab(
                context: context,
                themeProvider: themeProvider,
                coverPreset: coverPreset,
                isDarkBackdrop: isDarkBackdrop,
                topContentPadding: topContentPadding,
              ),
            ],
          ),
        ),
      ],
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: baseBgColor,
        body: ProfileFloatingSwitcherScaffold(
          segments: labels,
          selectedIndex: _activeTab,
          pageController: _pageController,
          onTabSelected: _onTabSelectedFromBar,
          onBack: () => Navigator.of(context).maybePop(),
          glassEnabled: glassProvider.enabled,
          isLite: glassProvider.isLite,
          isDarkBackdrop: isDarkBackdrop,
          topMargin: headerTopY,
          body: pageBackdropAndScroll,
        ),
      ),
    );
  }
}
