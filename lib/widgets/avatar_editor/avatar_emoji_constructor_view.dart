import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:ios_color_picker/show_ios_color_picker.dart';

import '../../l10n/app_localizations.dart';
import '../../models/avatar_editor_models.dart';
import '../../services/glass_toast_service.dart';
import '../../services/sticker_service.dart';
import '../../utils/avatar_studio_renderer.dart';
import '../../utils/emoji_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../chat/sticker_item_widget.dart';
import '../design_system/theav_design_system.dart';
import 'theav_avatar_editor_screen.dart';

/// Interactive Emoji / Sticker / Monogram avatar constructor view.
class AvatarEmojiConstructorView extends StatefulWidget {
  final AvatarShapeMask maskShape;
  final AvatarEditorCtaMode ctaMode;
  final String? subjectName;
  final ValueChanged<AvatarPickResult> onCompleted;

  const AvatarEmojiConstructorView({
    super.key,
    this.maskShape = AvatarShapeMask.circle,
    this.ctaMode = AvatarEditorCtaMode.done,
    this.subjectName,
    required this.onCompleted,
  });

  @override
  State<AvatarEmojiConstructorView> createState() =>
      _AvatarEmojiConstructorViewState();
}

class _AvatarEmojiConstructorViewState
    extends State<AvatarEmojiConstructorView> {
  static const double _previewSize = 220.0;

  static const List<String> _curatedEmojis = <String>[
    '😎', '😀', '🥳', '🤩', '😇', '😈', '🤠', '🥸',
    '🤯', '🥰', '😂', '🥹', '🤗', '🤔', '🤫', '😴',
    '🔥', '✨', '⚡', '💎', '👑', '🏆', '🚀', '🛸',
    '❤️', '🩷', '💜', '💙', '💚', '🖤', '🌈', '🌟',
    '🎉', '🎈', '🎧', '🎮', '🎨', '📸', '💡', '🔮',
    '🐱', '🐶', '🦊', '🐼', '🐯', '🦁', '🐸', '🦋',
    '🦄', '🐙', '🐳', '🦖', '🌸', '🍀', '🍕', '☕',
  ];

  final IOSColorPickerController _colorPickerController =
      IOSColorPickerController();
  late final TextEditingController _monogramCtrl;

  AvatarEmojiConstructorConfig _config = const AvatarEmojiConstructorConfig();
  int _foregroundTab = 0; // 0: Emoji, 1: Stickers, 2: Monogram
  bool _isRendering = false;

  @override
  void initState() {
    super.initState();
    final String initialMono = _deriveInitials(widget.subjectName);
    _monogramCtrl = TextEditingController(text: initialMono);
    StickerService.instance.addListener(_onStickersUpdated);
    StickerService.instance.ensureInitialized();
  }

  @override
  void dispose() {
    StickerService.instance.removeListener(_onStickersUpdated);
    _colorPickerController.dispose();
    _monogramCtrl.dispose();
    super.dispose();
  }

  void _onStickersUpdated() {
    if (mounted) setState(() {});
  }

  String _deriveInitials(String? rawName) {
    final String trimmed = rawName?.trim() ?? '';
    if (trimmed.isEmpty) return 'TH';
    final List<String> parts = trimmed
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return (parts[0].characters.first + parts[1].characters.first)
          .toUpperCase();
    }
    final chars = trimmed.characters.take(2).toList();
    return chars.join().toUpperCase();
  }

  Color _companionGradientColor(Color base) {
    final HSLColor hsl = HSLColor.fromColor(base);
    final double shiftedHue = (hsl.hue + 28.0) % 360.0;
    final double shiftedLightness =
        hsl.lightness > 0.55 ? (hsl.lightness - 0.16) : (hsl.lightness + 0.14);
    return hsl
        .withHue(shiftedHue)
        .withLightness(shiftedLightness.clamp(0.18, 0.86))
        .toColor();
  }

  void _openCustomColorWheel() {
    HapticUtils.selection();
    final Color start = _config.gradientColors.isNotEmpty
        ? _config.gradientColors.first
        : const Color(0xFF4FACFE);
    _colorPickerController.showIOSCustomColorPicker(
      context: context,
      startingColor: start,
      onColorChanged: (Color color) {
        if (!mounted) return;
        final Color opaque = color.withValues(alpha: 1.0);
        setState(() {
          _config = _config.copyWith(
            gradientColors: <Color>[opaque, _companionGradientColor(opaque)],
          );
        });
      },
    );
  }

  Future<void> _openInPhotoEditor() async {
    if (_isRendering) return;
    HapticUtils.tap();
    setState(() => _isRendering = true);
    try {
      final rendered = await AvatarStudioRenderer.renderEmojiConstructorAvatar(
        config: _config,
        textDirection: Directionality.of(context),
      );
      if (!mounted) return;
      setState(() => _isRendering = false);

      final AvatarPickResult? edited = await TheavAvatarEditorScreen.open(
        context: context,
        initialBytes: rendered.bytes,
        fileName: rendered.fileName,
        maskShape: widget.maskShape,
        ctaMode: widget.ctaMode,
        subjectName: widget.subjectName,
        initialAspectMode: AvatarCropAspectMode.square1x1,
        isFromConstructor: true,
      );
      if (edited != null && mounted) {
        widget.onCompleted(edited);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isRendering = false);
      GlassToastService().showError(
        context,
        context.trOr('avatar_editor_export_error', 'Не удалось создать аватар'),
      );
    }
  }

  Future<void> _confirmConstructorAvatar() async {
    if (_isRendering) return;
    HapticUtils.tap();
    setState(() => _isRendering = true);
    try {
      final rendered = await AvatarStudioRenderer.renderEmojiConstructorAvatar(
        config: _config,
        textDirection: Directionality.of(context),
      );
      if (!mounted) return;
      setState(() => _isRendering = false);
      widget.onCompleted(
        AvatarPickResult(
          file: rendered.file,
          bytes: rendered.bytes,
          fileName: rendered.fileName,
          maskShape: widget.maskShape,
          aspectMode: AvatarCropAspectMode.square1x1,
          isFromConstructor: true,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isRendering = false);
      GlassToastService().showError(
        context,
        context.trOr('avatar_editor_export_error', 'Не удалось создать аватар'),
      );
    }
  }

  String _ctaLabel(BuildContext context) {
    switch (widget.ctaMode) {
      case AvatarEditorCtaMode.done:
        return context.trOr('avatar_editor_done', 'Готово');
      case AvatarEditorCtaMode.setPhoto:
        final String? name = widget.subjectName?.trim();
        if (name != null && name.isNotEmpty) {
          return context.trOr(
            'avatar_editor_set_photo_for',
            'Установить фото для {name}',
            <String, String>{'name': name},
          );
        }
        return context.trOr('avatar_editor_set_photo', 'Установить фото');
      case AvatarEditorCtaMode.suggestPhoto:
        return context.trOr(
          'avatar_editor_suggest_photo',
          'Предложить фото',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  child: Column(
                    children: [
                      _buildLivePreview(palette),
                      const SizedBox(height: 14),
                      _buildGradientStrip(palette),
                      const SizedBox(height: 10),
                      _buildScaleAndStyleRow(context, palette),
                      const SizedBox(height: 12),
                      TheavSegmentedControl<int>(
                        useGlass: false,
                        height: 36,
                        expand: true,
                        selected: _foregroundTab,
                        onChanged: (int v) {
                          setState(() {
                            _foregroundTab = v;
                            if (v == 2 &&
                                (_config.monogramText == null ||
                                    _config.monogramText!.trim().isEmpty)) {
                              final text = _monogramCtrl.text.trim().isNotEmpty
                                  ? _monogramCtrl.text.trim()
                                  : 'TH';
                              _config = _config.copyWith(
                                monogramText: text,
                                clearEmoji: true,
                                clearStickerUrl: true,
                              );
                            }
                          });
                        },
                        options: [
                          TheavSegmentOption(
                            value: 0,
                            label: context.trOr(
                              'avatar_constructor_emojis',
                              'Эмодзи',
                            ),
                          ),
                          TheavSegmentOption(
                            value: 1,
                            label: context.trOr(
                              'avatar_constructor_stickers',
                              'Стикеры',
                            ),
                          ),
                          TheavSegmentOption(
                            value: 2,
                            label: context.trOr(
                              'avatar_editor_monogram',
                              'Монограмма',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
              ..._buildForegroundSliver(context, palette),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
            ],
          ),
        ),
        _buildBottomActions(context, palette),
      ],
    );
  }

  Widget _buildLivePreview(TheavPalette palette) {
    final double previewSize = math
        .min(_previewSize, MediaQuery.sizeOf(context).height * 0.28)
        .clamp(136.0, _previewSize);
    final List<Color> colors = _config.gradientColors.length >= 2
        ? _config.gradientColors
        : <Color>[const Color(0xFF4FACFE), const Color(0xFF00F2FE)];
    final double fgBox = previewSize * _config.foregroundScale;

    Widget foreground;
    if (_config.stickerUrl != null && _config.stickerUrl!.isNotEmpty) {
      foreground = StickerMediaView(
        fileUrl: _config.stickerUrl!,
        format: _config.stickerFormat,
        width: fgBox,
        height: fgBox,
        animate: true,
      );
    } else if (_config.monogramText != null &&
        _config.monogramText!.trim().isNotEmpty) {
      final String mono = _config.monogramText!.trim();
      final double factor =
          mono.length <= 1 ? 0.72 : (mono.length == 2 ? 0.58 : 0.44);
      foreground = Text(
        mono,
        maxLines: 1,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: fgBox * factor,
          fontWeight: FontWeight.w800,
          letterSpacing: mono.length > 1 ? -1.5 : 0.0,
          height: 1.0,
        ),
      );
    } else {
      foreground = Text(
        _config.emoji ?? '😎',
        textAlign: TextAlign.center,
        style: EmojiUtils.emojiTextStyle(
          fontSize: fgBox * 0.84,
          height: 1.0,
        ),
      );
    }

    return Center(
      child: Container(
        width: previewSize,
        height: previewSize,
        decoration: BoxDecoration(
          borderRadius: widget.maskShape.borderRadiusForSize(previewSize),
          border: Border.all(
            color: palette.onSurface.withValues(alpha: 0.14),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: colors.first.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: _config.isRadial
                ? RadialGradient(colors: colors, radius: 0.72)
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                  ),
          ),
          child: Center(child: foreground),
        ),
      ),
    );
  }

  Widget _buildGradientStrip(TheavPalette palette) {
    final bool isPresetSelected = AvatarEmojiConstructorConfig.presetGradients
        .any((g) => _colorsMatch(g, _config.gradientColors));

    return SwipeBackBlocker(
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: AvatarEmojiConstructorConfig.presetGradients.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (BuildContext context, int index) {
            if (index == 0) {
              // Custom color wheel button
              return GestureDetector(
                onTap: _openCustomColorWheel,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const SweepGradient(
                      colors: <Color>[
                        Color(0xFFFF3B30),
                        Color(0xFFFFCC00),
                        Color(0xFF34C759),
                        Color(0xFF38BDF8),
                        Color(0xFF5856D6),
                        Color(0xFFFF2D55),
                        Color(0xFFFF3B30),
                      ],
                    ),
                    border: Border.all(
                      color: !isPresetSelected
                          ? palette.primary
                          : palette.onSurface.withValues(alpha: 0.25),
                      width: !isPresetSelected ? 2.6 : 1.0,
                    ),
                  ),
                  child: const Center(
                    child: iconoir.ColorWheel(
                      width: 18,
                      height: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              );
            }

            final List<Color> grad =
                AvatarEmojiConstructorConfig.presetGradients[index - 1];
            final bool selected = _colorsMatch(grad, _config.gradientColors);
            return GestureDetector(
              onTap: () {
                HapticUtils.selection();
                setState(() {
                  _config = _config.copyWith(gradientColors: grad);
                });
              },
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: grad,
                  ),
                  border: Border.all(
                    color: selected
                        ? palette.onSurface
                        : palette.onSurface.withValues(alpha: 0.14),
                    width: selected ? 2.5 : 0.8,
                  ),
                ),
                child: selected
                    ? const Center(
                        child: iconoir.Check(
                          width: 16,
                          height: 16,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildScaleAndStyleRow(BuildContext context, TheavPalette palette) {
    return Row(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 132),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticUtils.selection();
              setState(() {
                _config = _config.copyWith(isRadial: !_config.isRadial);
              });
            },
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: palette.onSurface.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: palette.divider,
                  width: 0.6,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  iconoir.Palette(
                    width: 15,
                    height: 15,
                    color: palette.primary,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      _config.isRadial
                          ? context.trOr(
                              'avatar_constructor_radial',
                              'Радиальный',
                            )
                          : context.trOr(
                              'avatar_constructor_linear',
                              'Линейный',
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 72),
          child: Text(
            context.trOr('avatar_constructor_size', 'Размер'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.subtext,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: SwipeBackBlocker(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: palette.primary,
                inactiveTrackColor: palette.onSurface.withValues(alpha: 0.14),
                thumbColor: Colors.white,
                trackHeight: 3.5,
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 14),
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: _config.foregroundScale.clamp(0.45, 0.95),
                min: 0.45,
                max: 0.95,
                onChanged: (double v) {
                  setState(() {
                    _config = _config.copyWith(foregroundScale: v);
                  });
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildForegroundSliver(
    BuildContext context,
    TheavPalette palette,
  ) {
    if (_foregroundTab == 0) {
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int index) {
                final String emoji = _curatedEmojis[index];
                final bool selected =
                    _config.stickerUrl == null &&
                    _config.monogramText == null &&
                    _config.emoji == emoji;
                return GestureDetector(
                  onTap: () {
                    HapticUtils.selection();
                    setState(() {
                      _config = _config.copyWith(
                        emoji: emoji,
                        clearStickerUrl: true,
                        clearMonogramText: true,
                      );
                    });
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: selected
                          ? palette.primary.withValues(alpha: 0.20)
                          : palette.onSurface.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: selected
                          ? Border.all(color: palette.primary, width: 1.5)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      emoji,
                      style: EmojiUtils.emojiTextStyle(
                        fontSize: 24,
                        height: 1.0,
                      ),
                    ),
                  ),
                );
              },
              childCount: _curatedEmojis.length,
            ),
          ),
        ),
      ];
    }

    if (_foregroundTab == 1) {
      final service = StickerService.instance;
      final List<StickerItem> allStickers = <StickerItem>[
        ...service.favoriteStickers,
        ...service.recentStickers,
        for (final p in service.installedStickerPacks) ...p.stickers,
        for (final p in service.installedEmojiPacks) ...p.stickers,
        for (final p in service.featuredEmojiPacks) ...p.stickers,
      ];
      final Set<int> seenIds = <int>{};
      final List<StickerItem> unique = <StickerItem>[
        for (final s in allStickers)
          if (s.fileUrl.isNotEmpty && seenIds.add(s.id)) s,
      ];

      if (unique.isEmpty) {
        return [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Text(
                context.trOr(
                  'avatar_stickers_empty',
                  'Установленные стикерпаки не найдены',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.subtext, fontSize: 13.5),
              ),
            ),
          ),
        ];
      }

      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int index) {
                final StickerItem item = unique[index];
                final bool selected = _config.stickerUrl == item.fileUrl;
                return GestureDetector(
                  onTap: () {
                    HapticUtils.selection();
                    setState(() {
                      _config = _config.copyWith(
                        stickerUrl: item.fileUrl,
                        stickerFormat: item.format,
                        clearEmoji: true,
                        clearMonogramText: true,
                      );
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: selected
                          ? palette.primary.withValues(alpha: 0.20)
                          : palette.onSurface.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: selected
                          ? Border.all(color: palette.primary, width: 1.5)
                          : null,
                    ),
                    child: Center(
                      child: StickerMediaView(
                        fileUrl: item.fileUrl,
                        thumbnailUrl: item.thumbnailUrl,
                        stickerId: item.id,
                        format: item.format,
                        width: 48,
                        height: 48,
                        animate: false,
                      ),
                    ),
                  ),
                );
              },
              childCount: math.min(unique.length, 150),
            ),
          ),
        ),
      ];
    }

    // Tab 2: Monogram / Text input
    final String suggested = _deriveInitials(widget.subjectName);
    final List<String> quickMonograms = <String>{
      if (suggested.isNotEmpty) suggested,
      if (suggested.length > 1) suggested.characters.first,
      '★',
      'VIP',
    }.toList();

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _monogramCtrl,
                maxLength: 3,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
                onChanged: (String val) {
                  setState(() {
                    _config = _config.copyWith(
                      monogramText: val.trim().isEmpty ? ' ' : val.trim(),
                      clearEmoji: true,
                      clearStickerUrl: true,
                    );
                  });
                },
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'AB',
                  hintStyle: TextStyle(
                    color: palette.subtext.withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: palette.onSurface.withValues(alpha: 0.07),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final String chip in quickMonograms)
                    GestureDetector(
                      onTap: () {
                        HapticUtils.selection();
                        _monogramCtrl.text = chip;
                        setState(() {
                          _config = _config.copyWith(
                            monogramText: chip,
                            clearEmoji: true,
                            clearStickerUrl: true,
                          );
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: palette.onSurface.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: palette.divider,
                            width: 0.6,
                          ),
                        ),
                        child: Text(
                          chip,
                          style: TextStyle(
                            color: palette.onSurface,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildBottomActions(BuildContext context, TheavPalette palette) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextButton(
              key: const ValueKey<String>('avatar_constructor_open_editor'),
              onPressed: _isRendering ? null : _openInPhotoEditor,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  iconoir.EditPencil(
                    width: 17,
                    height: 17,
                    color: palette.primary,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      context.trOr(
                        'avatar_constructor_open_editor',
                        'Открыть в фоторедакторе',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            TheavFloatingPillButton(
              key: const ValueKey<String>('avatar_constructor_cta_btn'),
              height: 46,
              isPrimary: true,
              useGlass: false,
              enabled: !_isRendering,
              label: _ctaLabel(context),
              icon: _isRendering
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.0,
                        color: palette.onPrimary,
                      ),
                    )
                  : iconoir.Check(
                      width: 18,
                      height: 18,
                      color: palette.onPrimary,
                    ),
              onTap: _confirmConstructorAvatar,
            ),
          ],
        ),
      ),
    );
  }

  bool _colorsMatch(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].toARGB32() != b[i].toARGB32()) return false;
    }
    return true;
  }
}
