import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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
import '../../widgets/chat/emoji_sticker_panel.dart';
import '../../widgets/chat/sticker_item_widget.dart';
import '../../widgets/common/adaptive_switch.dart';
import '../../widgets/common/glass_modal_sheet.dart';
import '../../widgets/common/peer_badges_widget.dart';
import '../../widgets/profile/color_palette_picker.dart';
import '../../widgets/profile/name_color_picker.dart';
import '../../widgets/profile/profile_segmented_control.dart';
import '../../widgets/profile/reply_message_preview_card.dart';
import '../../widgets/settings/settings_floating_header.dart';
import '../../widgets/settings/settings_group.dart';
import '../../widgets/user/avatar_with_status.dart';
import '../../widgets/user/emoji_status_badge.dart';

/// Экран «Оформление профиля» в едином стиле настроек Theaver:
/// - Полноширинная живая обложка профиля под плавающим [SettingsFloatingHeader].
/// - Скользящий 3-секционный [ProfileSegmentedControl] («Профиль», «Имя в чатах», «Статус»).
/// - Карточки [SettingsGroup], [AdaptiveSwitch] и мгновенное применение изменений без нижних кнопок сохранения.
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
  late int _activeTab;
  Duration? _selectedDuration; // null = forever
  final TextEditingController _noteController = TextEditingController();
  final IOSColorPickerController _colorPickerController =
      IOSColorPickerController();

  ProfileColorPreset? _draftCoverPreset;
  NameColorPreset? _draftNamePreset;
  ReplyStripStyle? _draftStripStyle;

  Timer? _coverDebounce;
  Timer? _nameColorDebounce;
  Timer? _noteDebounce;

  bool _isUploadingBanner = false;
  String? _userId;

  static int _normalizeInitialTab(int raw) {
    if (raw <= 0) return 0;
    if (raw == 1) return 1;
    if (raw == 2) return 2;
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _activeTab = _normalizeInitialTab(widget.initialTab);

    final themeProvider = context.read<ProfileThemeProvider>();
    final existingStatus = themeProvider.currentEmojiStatus;
    if (existingStatus != null) {
      _noteController.text = existingStatus.note;
    }

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
  }

  @override
  void dispose() {
    _flushPendingSync();
    _noteController.dispose();
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
    if (_noteDebounce?.isActive == true) {
      _noteDebounce!.cancel();
      _syncNoteForActiveStatus();
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

    setState(() => _isUploadingBanner = true);
    final provider = context.read<ProfileThemeProvider>();
    final uploadedUrl = await provider.uploadBanner(
      filePath: kIsWeb ? null : file.path,
      bytes: kIsWeb ? file.bytes : null,
      fileName: file.name,
    );
    if (!mounted) return;
    setState(() => _isUploadingBanner = false);

    if (uploadedUrl == null || uploadedUrl.isEmpty) {
      _showToast(
        translateOrFallback(
          context,
          'customizationUploadError',
          'Failed to upload banner',
        ),
        isError: true,
      );
    }
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
                                      draft1, draft2, draft3)
                                  : NameColorPreset.fromCustomGradient(
                                      draft1, draft2);
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
                                      draft1, draft2, draft3)
                                  : NameColorPreset.fromCustomGradient(
                                      draft1, draft2);
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
  // Мгновенные действия: Эмодзи-статус, заметка и срок действия
  // ---------------------------------------------------------------------------

  DateTime? _computeExpiresAt() => _selectedDuration != null
      ? DateTime.now().toUtc().add(_selectedDuration!)
      : null;

  Future<void> _selectUnicodeStatus(String emoji) async {
    final trimmed = emoji.trim();
    if (trimmed.isEmpty) return;
    HapticUtils.selection();
    _noteDebounce?.cancel();
    final note = _noteController.text.trim();
    final until = _computeExpiresAt();
    final optimistic = EmojiStatusData(
      type: 'unicode',
      emoji: trimmed,
      note: note,
      expiresAt: until,
    );
    await context.read<ProfileThemeProvider>().updateCustomization(
          emojiStatusUnicode: trimmed,
          optimisticEmojiStatus: optimistic,
          emojiStatusNote: note,
          emojiStatusUntil: until,
          clearEmojiStatusUntil: until == null,
        );
  }

  Future<void> _selectCustomStickerStatus(StickerItem sticker) async {
    HapticUtils.selection();
    _noteDebounce?.cancel();
    final note = _noteController.text.trim();
    final until = _computeExpiresAt();
    final optimistic = EmojiStatusData(
      type: 'sticker',
      stickerId: sticker.id,
      stickerUrl: sticker.fileUrl,
      thumbnailUrl: sticker.thumbnailUrl,
      stickerFormat: sticker.format,
      note: note,
      expiresAt: until,
    );
    await context.read<ProfileThemeProvider>().updateCustomization(
          emojiStatusStickerId: sticker.id,
          optimisticEmojiStatus: optimistic,
          emojiStatusNote: note,
          emojiStatusUntil: until,
          clearEmojiStatusUntil: until == null,
        );
  }

  void _onStatusNoteChanged(String _) {
    setState(() {});
    _noteDebounce?.cancel();
    _noteDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      _syncNoteForActiveStatus();
    });
  }

  Future<void> _syncNoteForActiveStatus() async {
    final provider = context.read<ProfileThemeProvider>();
    final active = provider.currentEmojiStatus;
    if (active == null) return;
    final note = _noteController.text.trim();
    if (active.note == note) return;
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
        note: note,
        expiresAt: active.expiresAt,
      ),
      emojiStatusNote: note,
      emojiStatusUntil: active.expiresAt,
      clearEmojiStatusUntil: active.expiresAt == null,
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
        note: _noteController.text.trim(),
        expiresAt: until,
      ),
      emojiStatusNote: _noteController.text.trim(),
      emojiStatusUntil: until,
      clearEmojiStatusUntil: until == null,
    );
  }

  Future<void> _clearEmojiStatus() async {
    HapticUtils.selection();
    _noteDebounce?.cancel();
    setState(() => _noteController.clear());
    await context.read<ProfileThemeProvider>().updateCustomization(
          clearEmojiStatus: true,
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
  // Полноширинная живая шапка профиля (без рамок и без плашки «Live Preview»)
  // ---------------------------------------------------------------------------

  Widget _buildHeroSection(
    BuildContext context,
    ProfileThemeProvider themeProvider,
  ) {
    final topClearance = SettingsFloatingHeader.topClearanceOf(context);
    final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 100;
    if (isKeyboardOpen) {
      return SizedBox(height: topClearance);
    }

    final displayName = _displayName();
    final avatarUrl = _avatarUrl();

    if (_activeTab == 1) {
      return Padding(
        padding: EdgeInsets.only(top: topClearance + 6, bottom: 4),
        child: ReplyMessagePreviewCard(
          preset: _effectiveNamePreset(themeProvider),
          stripStyle: _effectiveStripStyle(themeProvider),
          userName: displayName,
          avatarUrl: avatarUrl,
          userId: _userId,
          avatarDecoration: themeProvider.currentAvatarDecoration,
          emojiStatus: themeProvider.currentEmojiStatus,
          badge: themeProvider.currentVisibleBadge,
        ),
      );
    }

    final coverPreset = _effectiveCoverPreset(themeProvider);
    final bannerUrl = AppConfig.resolveMediaUrl(themeProvider.currentBannerUrl);
    final hasBanner = bannerUrl != null && bannerUrl.isNotEmpty;
    final activeStatus = themeProvider.currentEmojiStatus;
    final draftNote = _noteController.text.trim();
    final effectiveNote = _activeTab == 2 && activeStatus != null
        ? draftNote
        : (activeStatus?.note.trim() ?? '');

    final BoxDecoration coverDecoration = coverPreset.isGradient &&
            coverPreset.gradientColors != null
        ? BoxDecoration(
            gradient: LinearGradient(
              colors: coverPreset.gradientColors!,
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          )
        : BoxDecoration(color: coverPreset.backgroundColor);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      decoration: coverDecoration,
      child: Stack(
        children: [
          if (hasBanner)
            Positioned.fill(
              child: ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.62, 1.0],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: ControlledAnimatedNetworkImage(
                  url: bannerUrl,
                  fit: BoxFit.cover,
                  animate: true,
                ),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: hasBanner ? 0.24 : 0.04),
                    Colors.black.withValues(alpha: hasBanner ? 0.44 : 0.14),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, topClearance + 8, 20, 22),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AvatarWithStatus(
                    userId: _userId,
                    avatarUrl: avatarUrl,
                    name: displayName,
                    radius: 42,
                    isOnline: true,
                    decorationOverride: themeProvider.currentAvatarDecoration,
                    showDecoration: true,
                    animateDecoration: true,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (activeStatus != null) ...[
                        const SizedBox(width: 6),
                        EmojiStatusBadge(
                          status: activeStatus,
                          size: 20,
                          animate: true,
                          interactive: false,
                          fallbackColor: Colors.white,
                        ),
                      ],
                      if (themeProvider.currentVisibleBadge != null)
                        PeerBadgesRow(
                          isBot: false,
                          isVerified: false,
                          badge: themeProvider.currentVisibleBadge,
                          interactiveBadge: false,
                          accentColor: Colors.white,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    effectiveNote.isNotEmpty
                        ? effectiveNote
                        : translateOrFallback(
                            context,
                            'profile_online',
                            'online',
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: effectiveNote.isNotEmpty
                          ? Colors.white.withValues(alpha: 0.88)
                          : coverPreset.statusColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Вкладка 0: Профиль (Обложка и баннер + Рамка аватара + Бейдж)
  // ---------------------------------------------------------------------------

  Widget _buildProfileTab(
    BuildContext context,
    ProfileThemeProvider themeProvider,
    PeerCustomizationCache cache,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final theav = TheavTheme.of(context);
    final coverPreset = _effectiveCoverPreset(themeProvider);
    final bannerUrl = AppConfig.resolveMediaUrl(themeProvider.currentBannerUrl);
    final hasBanner = bannerUrl != null && bannerUrl.isNotEmpty;

    final currentDecorationId = themeProvider.currentAvatarDecoration?.id;
    final decorations = cache.decorationsCatalog;
    final displayName = _displayName();
    final avatarUrl = _avatarUrl();
    final ownBadge = themeProvider.currentOwnBadge;

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      children: [
        // 1. Обложка и баннер
        SettingsGroup(
          title: translateOrFallback(
            context,
            'customizationSectionCoverBanner',
            'Cover & Banner',
          ),
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
                color: theav.accent,
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
                style: TextStyle(fontSize: 12.5, color: theav.textSecondary),
              ),
              trailing: _isUploadingBanner
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : iconoir.NavArrowRight(
                      width: 18,
                      height: 18,
                      color: theav.textSecondary,
                    ),
              onTap: _isUploadingBanner ? null : _pickAndUploadBanner,
            ),
            if (hasBanner)
              ListTile(
                leading: iconoir.Trash(
                  width: 22,
                  height: 22,
                  color: theav.palette.error,
                ),
                title: Text(
                  translateOrFallback(context, 'bannerRemove', 'Remove Banner'),
                  style: TextStyle(color: theav.palette.error),
                ),
                onTap: _isUploadingBanner ? null : _removeBanner,
              ),
            if (coverPreset.id != ProfileColorPresets.blue.id)
              ListTile(
                leading: iconoir.RefreshDouble(
                  width: 22,
                  height: 22,
                  color: theav.textSecondary,
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

        // 2. Рамка аватара (горизонтальная карусель внутри SettingsGroup)
        SettingsGroup(
          title: translateOrFallback(
            context,
            'customizationSectionAvatarFrame',
            'Avatar Frame',
          ),
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
                              ? theav.accent
                                  .withValues(alpha: isDark ? 0.16 : 0.10)
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
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSelected
                                    ? theav.accent
                                    : theav.textPrimary,
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

        // 3. Бейдж профиля
        SettingsGroup(
          title: translateOrFallback(
            context,
            'customizationSectionBadge',
            'Profile Badge',
          ),
          children: [
            if (ownBadge != null)
              ListTile(
                leading: PeerBadgesRow.buildCapsule(
                  label: ownBadge.shortTag,
                  color: ownBadge.accentColor,
                  isDark: isDark,
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
                  style: TextStyle(fontSize: 12.5, color: theav.textSecondary),
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
                  color: theav.textSecondary,
                ),
                title: Text(
                  translateOrFallback(
                    context,
                    'badgesEmpty',
                    "You don't have a badge assigned yet",
                  ),
                  style: TextStyle(
                    fontSize: 14.5,
                    color: theav.textSecondary,
                  ),
                ),
              ),
            ListTile(
              leading: iconoir.InfoCircle(
                width: 22,
                height: 22,
                color: theav.accent,
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
                color: theav.textSecondary,
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
  // Вкладка 1: Имя в чатах
  // ---------------------------------------------------------------------------

  Widget _buildNameTab(
    BuildContext context,
    ProfileThemeProvider themeProvider,
  ) {
    final theav = TheavTheme.of(context);
    final namePreset = _effectiveNamePreset(themeProvider);
    final stripStyle = _effectiveStripStyle(themeProvider);
    final isNonDefault = namePreset.id != NameColorPresets.red.id ||
        stripStyle != ReplyStripStyle.solid;

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      children: [
        SettingsGroup(
          title: translateOrFallback(
            context,
            'customizationNameColorTitle',
            'Name Color',
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: NameColorPaletteRow(
                selectedPreset: namePreset,
                selectedStyle: stripStyle,
                onPresetSelected: (preset) =>
                    _applyNameColorImmediate(preset, stripStyle),
                onPickCustomColor: _pickCustomNameColor,
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: translateOrFallback(
            context,
            'customizationReplyStripTitle',
            'Reply Strip Style',
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: ReplyStripStyleSelector(
                selectedPreset: namePreset,
                selectedStyle: stripStyle,
                onStyleSelected: (style) =>
                    _applyNameColorImmediate(namePreset, style),
              ),
            ),
          ],
        ),
        if (isNonDefault)
          SettingsGroup(
            children: [
              ListTile(
                leading: iconoir.RefreshDouble(
                  width: 22,
                  height: 22,
                  color: theav.textSecondary,
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

  // ---------------------------------------------------------------------------
  // Вкладка 2: Эмодзи-статус
  // ---------------------------------------------------------------------------

  Widget _buildStatusTab(
    BuildContext context,
    ProfileThemeProvider themeProvider,
  ) {
    final theme = Theme.of(context);
    final theav = TheavTheme.of(context);
    final activeStatus = themeProvider.currentEmojiStatus;

    final durationOptions = <(Duration?, String)>[
      (null, translateOrFallback(context, 'emojiStatusExpiryNever', 'Forever')),
      (
        const Duration(hours: 1),
        translateOrFallback(context, 'emojiStatusExpiry1h', '1 hour')
      ),
      (
        const Duration(hours: 4),
        translateOrFallback(context, 'emojiStatusExpiry4h', '4 hours')
      ),
      (
        const Duration(hours: 24),
        translateOrFallback(context, 'emojiStatusExpiry24h', '24 hours')
      ),
      (
        const Duration(days: 7),
        translateOrFallback(context, 'emojiStatusExpiry7d', '7 days')
      ),
    ];

    int selectedDurationIdx = 0;
    for (int i = 0; i < durationOptions.length; i++) {
      if (durationOptions[i].$1 == _selectedDuration) {
        selectedDurationIdx = i;
        break;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final showMetaControls = constraints.maxHeight >= 220.0;
        return Column(
          children: [
            if (showMetaControls)
              SettingsGroup(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    child: Row(
                      children: [
                        if (activeStatus != null)
                          EmojiStatusBadge(
                            status: activeStatus,
                            size: 22,
                            animate: true,
                            interactive: false,
                            fallbackColor: theav.accent,
                          )
                        else
                          iconoir.Emoji(
                            width: 22,
                            height: 22,
                            color: theav.accent,
                          ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextField(
                            controller: _noteController,
                            maxLength: 64,
                            decoration: InputDecoration(
                              counterText: '',
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                              hintText: translateOrFallback(
                                context,
                                'emojiStatusNoteHint',
                                'Add a short note (up to 64 chars)',
                              ),
                              hintStyle: TextStyle(
                                color: theav.textSecondary,
                                fontSize: 14.5,
                              ),
                            ),
                            onChanged: _onStatusNoteChanged,
                          ),
                        ),
                        if (activeStatus != null ||
                            _noteController.text.isNotEmpty)
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
                              color: theav.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  PopupMenuButton<int>(
                    onSelected: (idx) =>
                        _onDurationSelected(durationOptions[idx].$1),
                    itemBuilder: (ctx) => [
                      for (int i = 0; i < durationOptions.length; i++)
                        PopupMenuItem<int>(
                          value: i,
                          child: Row(
                            children: [
                              Expanded(child: Text(durationOptions[i].$2)),
                              if (i == selectedDurationIdx)
                                iconoir.Check(
                                  width: 18,
                                  height: 18,
                                  color: theav.accent,
                                ),
                            ],
                          ),
                        ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          iconoir.Clock(
                            width: 21,
                            height: 21,
                            color: theav.accent,
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Text(
                              translateOrFallback(
                                context,
                                'emojiStatusExpiryLabel',
                                'Duration',
                              ),
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            durationOptions[selectedDurationIdx].$2,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: theav.accent,
                            ),
                          ),
                          const SizedBox(width: 4),
                          iconoir.NavArrowDown(
                            width: 16,
                            height: 16,
                            color: theav.accent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ColoredBox(
                    color: theme.cardColor,
                    child: EmojiStickerPanel(
                      emojiOnly: true,
                      expandToAvailableHeight: true,
                      selectedEmoji: activeStatus?.type == 'unicode'
                          ? activeStatus?.emoji
                          : null,
                      selectedCustomEmojiId: activeStatus?.type == 'sticker'
                          ? activeStatus?.stickerId
                          : null,
                      onEmojiSelected: _selectUnicodeStatus,
                      onCustomEmojiSelected: _selectCustomStickerStatus,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final glassProvider = context.watch<LiquidGlassProvider>();
    final themeProvider = context.watch<ProfileThemeProvider>();
    final cache = context.watch<PeerCustomizationCache>();

    final Widget activeBody = switch (_activeTab) {
      1 => _buildNameTab(context, themeProvider),
      2 => _buildStatusTab(context, themeProvider),
      _ => _buildProfileTab(context, themeProvider, cache),
    };

    return SettingsFloatingScaffold(
      title: translateOrFallback(
        context,
        'customizationTitle',
        'Profile Customization',
      ),
      padBodyTop: false,
      body: Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _buildHeroSection(context, themeProvider),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: ProfileSegmentedControl(
              enabled: glassProvider.enabled,
              isLite: glassProvider.isLite,
              neutralSurface: true,
              height: 36,
              selectedIndex: _activeTab,
              labels: [
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
                translateOrFallback(
                  context,
                  'customizationSegmentStatus',
                  'Status',
                ),
              ],
              onTabChanged: (idx) => setState(() => _activeTab = idx),
            ),
          ),
          Expanded(child: activeBody),
        ],
      ),
    );
  }
}
