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
import '../../utils/haptic_utils.dart';
import '../../widgets/chat/emoji_sticker_panel.dart';
import '../../widgets/chat/sticker_item_widget.dart';
import '../../widgets/common/glass_modal_sheet.dart';
import '../../widgets/common/peer_badges_widget.dart';
import '../../widgets/profile/color_palette_picker.dart';
import '../../widgets/profile/name_color_picker.dart';
import '../../widgets/profile/reply_message_preview_card.dart';
import '../../widgets/user/avatar_with_status.dart';
import '../../widgets/user/emoji_status_badge.dart';

/// Unified 5-tab Profile Customization Studio (Frame, Status, Banner, Badges, Colors)
/// styled natively with Material 3 + Liquid Glass adaptivity.
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
  int _statusSourceTab = 0; // 0 = unicode, 1 = custom emoji
  String _selectedUnicode = '✨';
  StickerItem? _selectedSticker;
  Duration? _selectedDuration; // null = never
  final TextEditingController _noteController = TextEditingController();
  final IOSColorPickerController _colorPickerController =
      IOSColorPickerController();

  late ProfileColorPreset _tempCoverPreset;
  late NameColorPreset _tempNamePreset;
  late ReplyStripStyle _tempStripStyle;

  bool _isSaving = false;
  bool _isUploadingBanner = false;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab.clamp(0, 4);

    final themeProvider = context.read<ProfileThemeProvider>();
    _tempCoverPreset = themeProvider.currentPreset ?? ProfileColorPresets.blue;
    _tempNamePreset = themeProvider.currentNameColorPreset;
    _tempStripStyle = themeProvider.currentStripStyle;

    final existingStatus = themeProvider.currentEmojiStatus;
    if (existingStatus != null) {
      _noteController.text = existingStatus.note;
      if (existingStatus.type == 'sticker' && existingStatus.stickerId != null) {
        _statusSourceTab = 1;
        _selectedSticker = StickerService.instance
                .getStickerByIdSync(existingStatus.stickerId) ??
            StickerItem(
              id: existingStatus.stickerId!,
              packId: 0,
              fileUrl: existingStatus.stickerUrl ?? '',
              thumbnailUrl: existingStatus.thumbnailUrl ?? '',
              format: existingStatus.stickerFormat ?? 'webp',
            );
      } else if (existingStatus.emoji != null &&
          existingStatus.emoji!.isNotEmpty) {
        _statusSourceTab = 0;
        _selectedUnicode = existingStatus.emoji!;
      }
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
    _noteController.dispose();
    _colorPickerController.dispose();
    super.dispose();
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

  Future<void> _selectDecoration(AvatarDecorationPreset? preset) async {
    if (_isSaving) return;
    HapticUtils.selection();
    setState(() => _isSaving = true);
    final provider = context.read<ProfileThemeProvider>();
    final ok = await provider.updateCustomization(
      avatarDecorationId: preset?.id,
      clearAvatarDecoration: preset == null,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (ok) {
      _showToast(
        translateOrFallback(
          context,
          'customizationSaved',
          'Profile customization updated',
        ),
      );
    }
  }

  EmojiStatusData? _buildDraftEmojiStatus() {
    final note = _noteController.text.trim();
    final until = _selectedDuration != null
        ? DateTime.now().toUtc().add(_selectedDuration!)
        : null;
    if (_statusSourceTab == 1 && _selectedSticker != null) {
      return EmojiStatusData(
        type: 'sticker',
        stickerId: _selectedSticker!.id,
        stickerUrl: _selectedSticker!.fileUrl,
        thumbnailUrl: _selectedSticker!.thumbnailUrl,
        stickerFormat: _selectedSticker!.format,
        note: note,
        expiresAt: until,
      );
    }
    final unicode = _selectedUnicode.trim();
    if (unicode.isEmpty) return null;
    return EmojiStatusData(
      type: 'unicode',
      emoji: unicode,
      note: note,
      expiresAt: until,
    );
  }

  Future<void> _saveEmojiStatus() async {
    if (_isSaving) return;
    final draft = _buildDraftEmojiStatus();
    if (draft == null) return;
    HapticUtils.selection();
    setState(() => _isSaving = true);
    final provider = context.read<ProfileThemeProvider>();
    final ok = await provider.updateCustomization(
      emojiStatusUnicode: draft.type == 'unicode' ? draft.emoji : null,
      emojiStatusStickerId: draft.type == 'sticker' ? draft.stickerId : null,
      emojiStatusNote: draft.note,
      emojiStatusUntil: draft.expiresAt,
      clearEmojiStatusUntil: draft.expiresAt == null,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (ok) {
      _showToast(
        translateOrFallback(
          context,
          'customizationSaved',
          'Profile customization updated',
        ),
      );
    }
  }

  Future<void> _clearEmojiStatus() async {
    if (_isSaving) return;
    HapticUtils.selection();
    setState(() => _isSaving = true);
    final ok = await context.read<ProfileThemeProvider>().updateCustomization(
          clearEmojiStatus: true,
        );
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _noteController.clear();
    });
    if (ok) {
      _showToast(
        translateOrFallback(
          context,
          'customizationSaved',
          'Profile customization updated',
        ),
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

    if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
      _showToast(
        translateOrFallback(
          context,
          'customizationSaved',
          'Profile customization updated',
        ),
      );
    } else {
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
    if (ok) {
      _showToast(
        translateOrFallback(
          context,
          'customizationSaved',
          'Profile customization updated',
        ),
      );
    }
  }

  Future<void> _saveColors() async {
    if (_isSaving) return;
    HapticUtils.heavy();
    setState(() => _isSaving = true);
    final provider = context.read<ProfileThemeProvider>();
    await provider.setPreset(_tempCoverPreset);
    await provider.setNameColorAndStyle(_tempNamePreset, _tempStripStyle);
    await NameColorSyncService().setNameColorAndStyle(
      preset: _tempNamePreset,
      style: _tempStripStyle,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    _showToast(
      translateOrFallback(
        context,
        'customizationSaved',
        'Profile customization updated',
      ),
    );
  }

  Future<void> _resetColors() async {
    if (_isSaving) return;
    HapticUtils.impact();
    setState(() => _isSaving = true);
    await context.read<ProfileThemeProvider>().resetToDefault();
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _tempCoverPreset = ProfileColorPresets.blue;
      _tempNamePreset = NameColorPresets.red;
      _tempStripStyle = ReplyStripStyle.solid;
    });
    _showToast(
      translateOrFallback(
        context,
        'profile_color_reset_success',
        'Profile colors reset',
      ),
    );
  }

  Future<void> _pickCustomCoverColor() async {
    HapticUtils.selection();
    _colorPickerController.showIOSCustomColorPicker(
      context: context,
      startingColor: _tempCoverPreset.backgroundColor,
      onColorChanged: (c) {
        if (!mounted) return;
        setState(() {
          _tempCoverPreset = ProfileColorPreset.fromCustomColor(
            c.withValues(alpha: 1.0),
          );
        });
      },
    );
  }

  Future<void> _pickCustomNameColor() async {
    HapticUtils.selection();
    final c1 = _tempNamePreset.primaryColor;
    final c2 = _tempNamePreset.effectiveSecondary;
    final c3 = _tempNamePreset.effectiveTertiary;
    if (_tempStripStyle == ReplyStripStyle.solid) {
      _colorPickerController.showIOSCustomColorPicker(
        context: context,
        startingColor: c1,
        onColorChanged: (c) {
          if (!mounted) return;
          setState(() {
            _tempNamePreset = NameColorPreset.fromCustomColor(
              c.withValues(alpha: 1.0),
            );
          });
        },
      );
      return;
    }

    Color draft1 = c1;
    Color draft2 = c2;
    Color draft3 = c3;
    await showTheavGlassModalSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _colorSwatchButton(sheetCtx, draft1, '1', () {
                  _colorPickerController.showIOSCustomColorPicker(
                    context: sheetCtx,
                    startingColor: draft1,
                    onColorChanged: (c) {
                      final opaque = c.withValues(alpha: 1.0);
                      setSheet(() => draft1 = opaque);
                      setState(() {
                        _tempNamePreset = _tempStripStyle ==
                                ReplyStripStyle.candyCane
                            ? NameColorPreset.fromCustomTriple(
                                draft1, draft2, draft3)
                            : NameColorPreset.fromCustomGradient(
                                draft1, draft2);
                      });
                    },
                  );
                }),
                _colorSwatchButton(sheetCtx, draft2, '2', () {
                  _colorPickerController.showIOSCustomColorPicker(
                    context: sheetCtx,
                    startingColor: draft2,
                    onColorChanged: (c) {
                      final opaque = c.withValues(alpha: 1.0);
                      setSheet(() => draft2 = opaque);
                      setState(() {
                        _tempNamePreset = _tempStripStyle ==
                                ReplyStripStyle.candyCane
                            ? NameColorPreset.fromCustomTriple(
                                draft1, draft2, draft3)
                            : NameColorPreset.fromCustomGradient(
                                draft1, draft2);
                      });
                    },
                  );
                }),
                if (_tempStripStyle == ReplyStripStyle.candyCane)
                  _colorSwatchButton(sheetCtx, draft3, '3', () {
                    _colorPickerController.showIOSCustomColorPicker(
                      context: sheetCtx,
                      startingColor: draft3,
                      onColorChanged: (c) {
                        final opaque = c.withValues(alpha: 1.0);
                        setSheet(() => draft3 = opaque);
                        setState(() {
                          _tempNamePreset = NameColorPreset.fromCustomTriple(
                            draft1,
                            draft2,
                            draft3,
                          );
                        });
                      },
                    );
                  }),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(sheetCtx).pop(),
                child: Text(
                  translateOrFallback(sheetCtx, 'ok', 'OK'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorSwatchButton(
    BuildContext context,
    Color color,
    String label,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(color: Colors.white70, width: 2),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildLivePreviewCard(
    BuildContext context,
    ProfileThemeProvider themeProvider,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final displayName = _displayName();
    final avatarUrl = _avatarUrl();
    final bannerUrl = AppConfig.resolveMediaUrl(themeProvider.currentBannerUrl);
    final hasBanner = bannerUrl != null && bannerUrl.isNotEmpty;

    final coverPreset = _activeTab == 4
        ? _tempCoverPreset
        : (themeProvider.currentPreset ?? ProfileColorPresets.blue);
    final previewStatus = _activeTab == 1
        ? (_buildDraftEmojiStatus() ?? themeProvider.currentEmojiStatus)
        : themeProvider.currentEmojiStatus;

    final Decoration coverDecoration = coverPreset.isGradient
        ? BoxDecoration(
            gradient: LinearGradient(
              colors: coverPreset.gradientColors!,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          )
        : BoxDecoration(color: coverPreset.backgroundColor);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: coverPreset.backgroundColor.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(decoration: coverDecoration),
          ),
          if (hasBanner)
            Positioned.fill(
              child: ControlledAnimatedNetworkImage(
                url: bannerUrl,
                fit: BoxFit.cover,
                animate: true,
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: hasBanner ? 0.30 : 0.10),
                    Colors.black.withValues(alpha: hasBanner ? 0.65 : 0.35),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.32),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      translateOrFallback(
                        context,
                        'customizationPreviewLabel',
                        'Live Preview',
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                AvatarWithStatus(
                  userId: _userId,
                  avatarUrl: avatarUrl,
                  name: displayName,
                  radius: 36,
                  isOnline: true,
                  decorationOverride: themeProvider.currentAvatarDecoration,
                  showDecoration: true,
                  animateDecoration: true,
                ),
                const SizedBox(height: 10),
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
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (previewStatus?.activeOrNull != null) ...[
                      const SizedBox(width: 6),
                      EmojiStatusBadge(
                        status: previewStatus,
                        size: 20,
                        animate: true,
                        interactive: false,
                        fallbackColor: Colors.white,
                      ),
                    ],
                    PeerBadgesRow(
                      isBot: false,
                      isVerified: false,
                      badge: themeProvider.currentVisibleBadge,
                      interactiveBadge: false,
                      accentColor: Colors.white,
                    ),
                  ],
                ),
                if (previewStatus?.note.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    previewStatus!.note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.white.withValues(alpha: 0.88),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(BuildContext context, bool glassEnabled) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tabs = [
      translateOrFallback(context, 'customizationTabFrame', 'Frame'),
      translateOrFallback(context, 'customizationTabStatus', 'Status'),
      translateOrFallback(context, 'customizationTabBanner', 'Banner'),
      translateOrFallback(context, 'customizationTabBadges', 'Badges'),
      translateOrFallback(context, 'customizationTabColors', 'Colors'),
    ];

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, idx) {
          final selected = idx == _activeTab;
          return GestureDetector(
            onTap: () {
              HapticUtils.selection();
              setState(() => _activeTab = idx);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primary
                    : (glassEnabled
                        ? (isDark
                            ? Colors.white.withValues(alpha: 0.10)
                            : Colors.black.withValues(alpha: 0.06))
                        : theme.colorScheme.surfaceContainerHighest),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.14)
                          : Colors.black.withValues(alpha: 0.08)),
                ),
              ),
              child: Center(
                child: Text(
                  tabs[idx],
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFrameTab(
    BuildContext context,
    ProfileThemeProvider themeProvider,
    PeerCustomizationCache cache,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentId = themeProvider.currentAvatarDecoration?.id;
    final catalog = cache.decorationsCatalog;
    final displayName = _displayName();
    final avatarUrl = _avatarUrl();

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.84,
      ),
      itemCount: catalog.length + 1,
      itemBuilder: (ctx, index) {
        final isNone = index == 0;
        final preset = isNone ? null : catalog[index - 1];
        final isSelected =
            isNone ? (currentId == null || currentId.isEmpty) : currentId == preset!.id;
        final title = isNone
            ? translateOrFallback(ctx, 'decoNone', 'None')
            : translateOrFallback(ctx, preset!.nameKey, preset.id);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _isSaving ? null : () => _selectDecoration(preset),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.primary.withValues(alpha: 0.14)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.55)),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                  width: isSelected ? 1.8 : 1.0,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AvatarWithStatus(
                    avatarUrl: avatarUrl,
                    name: displayName,
                    radius: 26,
                    decorationOverride: preset,
                    showDecoration: preset != null,
                    animateDecoration: isSelected,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusTab(
    BuildContext context,
    ProfileThemeProvider themeProvider,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final showFooterControls = constraints.maxHeight >= 240.0;
        return Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.08),
                      width: 0.8,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: EmojiStickerPanel(
                      emojiOnly: true,
                      expandToAvailableHeight: true,
                      selectedEmoji:
                          _statusSourceTab == 0 ? _selectedUnicode : null,
                      selectedCustomEmojiId:
                          _statusSourceTab == 1 ? _selectedSticker?.id : null,
                      onEmojiSelected: (emoji) {
                        HapticUtils.selection();
                        setState(() {
                          _statusSourceTab = 0;
                          _selectedUnicode = emoji;
                          _selectedSticker = null;
                        });
                      },
                      onCustomEmojiSelected: (sticker) {
                        HapticUtils.selection();
                        setState(() {
                          _statusSourceTab = 1;
                          _selectedSticker = sticker;
                        });
                      },
                    ),
                  ),
                ),
              ),
            ),
            if (showFooterControls)
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _noteController,
                      maxLength: 64,
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: translateOrFallback(
                          context,
                          'emojiStatusNoteHint',
                          'Add a short note (up to 64 chars)',
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              translateOrFallback(
                                context,
                                'emojiStatusExpiryLabel',
                                'Duration',
                              ),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          for (int i = 0; i < durationOptions.length; i++) ...[
                            if (i > 0) const SizedBox(width: 6),
                            ChoiceChip(
                              label: Text(durationOptions[i].$2),
                              selected:
                                  _selectedDuration == durationOptions[i].$1,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onSelected: (_) {
                                HapticUtils.selection();
                                setState(() =>
                                    _selectedDuration = durationOptions[i].$1);
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSaving ? null : _clearEmojiStatus,
                            child: Text(
                              translateOrFallback(
                                context,
                                'emojiStatusClear',
                                'Clear Status',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _isSaving ? null : _saveEmojiStatus,
                            child: Text(
                              translateOrFallback(
                                context,
                                'customizationSave',
                                'Save Changes',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBannerTab(
    BuildContext context,
    ProfileThemeProvider themeProvider,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bannerUrl = AppConfig.resolveMediaUrl(themeProvider.currentBannerUrl);
    final hasBanner = bannerUrl != null && bannerUrl.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasBanner
                ? ControlledAnimatedNetworkImage(
                    url: bannerUrl,
                    fit: BoxFit.cover,
                    animate: true,
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      iconoir.MediaImage(
                        width: 42,
                        height: 42,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        translateOrFallback(
                          context,
                          'bannerTitle',
                          'Profile Banner',
                        ),
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          translateOrFallback(
            context,
            'bannerHint',
            'Recommended 16:9 image, up to 15 MB',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _isUploadingBanner ? null : _pickAndUploadBanner,
          icon: _isUploadingBanner
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const iconoir.MediaImage(width: 18, height: 18),
          label: Text(
            translateOrFallback(context, 'bannerUpload', 'Upload Banner'),
          ),
        ),
        if (hasBanner) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _isUploadingBanner ? null : _removeBanner,
            icon: const iconoir.Trash(width: 18, height: 18),
            label: Text(
              translateOrFallback(context, 'bannerRemove', 'Remove Banner'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBadgesTab(
    BuildContext context,
    ProfileThemeProvider themeProvider,
    PeerCustomizationCache cache,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ownBadge = themeProvider.currentOwnBadge;
    final catalog = cache.badgesCatalog;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        if (ownBadge != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ownBadge.accentColor.withValues(alpha: isDark ? 0.14 : 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: ownBadge.accentColor.withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    PeerBadgesRow.buildCapsule(
                      label: ownBadge.shortTag,
                      color: ownBadge.accentColor,
                      isDark: isDark,
                      scale: 1.25,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        translateOrFallback(
                          context,
                          ownBadge.nameKey,
                          ownBadge.shortTag,
                        ),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  translateOrFallback(context, ownBadge.descKey, ''),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: themeProvider.isBadgeDisplayed,
                  title: Text(
                    translateOrFallback(
                      context,
                      'badgesDisplaySwitch',
                      'Show badge next to name',
                    ),
                  ),
                  onChanged: _isSaving
                      ? null
                      : (v) async {
                          HapticUtils.selection();
                          await themeProvider.updateCustomization(
                            badgeIsDisplayed: v,
                          );
                        },
                ),
              ],
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              translateOrFallback(
                context,
                'badgesEmpty',
                "You don't have a badge assigned yet",
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          translateOrFallback(
            context,
            'badgesSingleHint',
            'Only one badge can be active on a profile',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        ...catalog.map((badge) {
          final isMine = ownBadge?.id == badge.id;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isMine
                    ? badge.accentColor.withValues(alpha: 0.65)
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PeerBadgesRow.buildCapsule(
                  label: badge.shortTag,
                  color: badge.accentColor,
                  isDark: isDark,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        translateOrFallback(
                          context,
                          badge.nameKey,
                          badge.shortTag,
                        ),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        translateOrFallback(context, badge.descKey, ''),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildColorsTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 28),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ReplyMessagePreviewCard(
            preset: _tempNamePreset,
            stripStyle: _tempStripStyle,
            userName: _displayName(),
            avatarUrl: _avatarUrl(),
          ),
        ),
        const SizedBox(height: 16),
        ColorPalettePicker(
          selectedPreset: _tempCoverPreset,
          onSelect: (preset) => setState(() => _tempCoverPreset = preset),
          onPickCustomColor: _pickCustomCoverColor,
        ),
        const SizedBox(height: 20),
        NameColorPicker(
          selectedPreset: _tempNamePreset,
          selectedStyle: _tempStripStyle,
          onPresetSelected: (p) => setState(() => _tempNamePreset = p),
          onStyleSelected: (s) => setState(() => _tempStripStyle = s),
          onPickCustomColor: _pickCustomNameColor,
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving ? null : _resetColors,
                  child: Text(
                    translateOrFallback(context, 'customizationReset', 'Reset'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _isSaving ? null : _saveColors,
                  child: Text(
                    translateOrFallback(
                      context,
                      'customizationSave',
                      'Save Changes',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final glassEnabled = context.watch<LiquidGlassProvider>().enabled;
    final themeProvider = context.watch<ProfileThemeProvider>();
    final cache = context.watch<PeerCustomizationCache>();
    final theme = Theme.of(context);

    Widget activeBody;
    switch (_activeTab) {
      case 0:
        activeBody = _buildFrameTab(context, themeProvider, cache);
        break;
      case 1:
        activeBody = _buildStatusTab(context, themeProvider);
        break;
      case 2:
        activeBody = _buildBannerTab(context, themeProvider);
        break;
      case 3:
        activeBody = _buildBadgesTab(context, themeProvider, cache);
        break;
      case 4:
      default:
        activeBody = _buildColorsTab(context);
        break;
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: iconoir.NavArrowLeft(
            width: 22,
            height: 22,
            color: theme.colorScheme.onSurface,
          ),
        ),
        title: Text(
          translateOrFallback(
            context,
            'customizationTitle',
            'Profile Customization',
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: MediaQuery.viewInsetsOf(context).bottom > 100
                ? const SizedBox.shrink()
                : _buildLivePreviewCard(context, themeProvider),
          ),
          _buildTabBar(context, glassEnabled),
          const SizedBox(height: 6),
          Expanded(child: activeBody),
        ],
      ),
    );
  }
}
