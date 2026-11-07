import 'dart:io' show Platform;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../models/call_models.dart';
import '../../models/theav_theme.dart';
import '../../services/liquid_glass_provider.dart';

/// Bottom sheet for configuring High-FPS Screen Share / Go Live quality
/// (Smart Presets + Progressive Disclosure for Resolution: 720p/1080p/1440p/4K,
/// Frame Rate: 30/60/120/144 FPS, Bitrate: 1.5–25 Mbps, Codec: H264/VP8/VP9/AV1,
/// Content Hint: Motion/Detail, System Audio, and Server Recording).
///
/// Supports both Material Matte and Liquid Glass modes (without any FadeTransition
/// on LiquidGlassLens shapes).
class StreamQualitySheet extends StatefulWidget {
  final StreamConfig initialConfig;
  final bool isUpdatingActiveStream;
  final VoidCallback? onStopStream;

  const StreamQualitySheet({
    super.key,
    required this.initialConfig,
    this.isUpdatingActiveStream = false,
    this.onStopStream,
  });

  static Future<StreamConfig?> show(
    BuildContext context, {
    StreamConfig initialConfig = const StreamConfig(),
    bool isUpdatingActiveStream = false,
    VoidCallback? onStopStream,
  }) {
    return showModalBottomSheet<StreamConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StreamQualitySheet(
        initialConfig: initialConfig,
        isUpdatingActiveStream: isUpdatingActiveStream,
        onStopStream: onStopStream,
      ),
    );
  }

  @override
  State<StreamQualitySheet> createState() => _StreamQualitySheetState();
}

class _StreamQualitySheetState extends State<StreamQualitySheet> {
  late int _width;
  late int _height;
  late int _fps;
  late int _bitrateKbps;
  late String _codec;
  late String _contentHint;
  late bool _includeAudio;
  late bool _enableRecording;
  late String _sourceType;
  bool _showAdvanced = false;

  static const List<({String label, int w, int h, int recBitrate})>
      _resolutions = [
    (label: '720p', w: 1280, h: 720, recBitrate: 3500),
    (label: '1080p', w: 1920, h: 1080, recBitrate: 6500),
    (label: '1440p', w: 2560, h: 1440, recBitrate: 12000),
    (label: '4K', w: 3840, h: 2160, recBitrate: 18000),
  ];

  static const List<int> _fpsOptions = [30, 60, 120, 144];
  static const List<({String id, String label, String sublabel})> _codecs = [
    (id: 'H264', label: 'H.264', sublabel: 'HW Ускорение'),
    (id: 'VP8', label: 'VP8', sublabel: 'Базовый'),
    (id: 'VP9', label: 'VP9', sublabel: 'Чёткий текст'),
    (id: 'AV1', label: 'AV1', sublabel: 'Next-Gen'),
  ];

  bool get _isMobilePlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    final c = widget.initialConfig;
    _width = c.width;
    _height = c.height;
    _fps = c.fps;
    _bitrateKbps = c.bitrateKbps;
    _codec = c.codec;
    _contentHint = c.contentHint;
    _includeAudio = c.includeAudio;
    _enableRecording = c.enableServerRecording;
    _sourceType = c.sourceType == 'camera' ? 'screen' : c.sourceType;
    _showAdvanced = widget.isUpdatingActiveStream;
  }

  String get _activePresetId {
    if (_contentHint == 'detail' && _height == 1440 && _fps == 60) {
      return 'text_clarity';
    }
    if (_contentHint == 'motion' && _height == 1080 && _fps == 60) {
      return 'balanced';
    }
    if (_contentHint == 'motion' && _height >= 1080 && _fps >= 120) {
      return 'ultra_fps';
    }
    return 'custom';
  }

  void _applySmartPreset(String presetId) {
    HapticFeedback.selectionClick();
    setState(() {
      switch (presetId) {
        case 'balanced':
          _width = 1920;
          _height = 1080;
          _fps = 60;
          _bitrateKbps = 6500;
          _codec = 'H264';
          _contentHint = 'motion';
          break;
        case 'ultra_fps':
          _width = 2560;
          _height = 1440;
          _fps = 144;
          _bitrateKbps = 14000;
          _codec = 'H264';
          _contentHint = 'motion';
          break;
        case 'text_clarity':
          _width = 2560;
          _height = 1440;
          _fps = 60;
          _bitrateKbps = 8000;
          _codec = 'VP9';
          _contentHint = 'detail';
          break;
      }
    });
  }

  void _selectResolution(int w, int h, int recBitrate) {
    HapticFeedback.selectionClick();
    setState(() {
      _width = w;
      _height = h;
      final fpsBoost = _fps >= 120 ? 1.45 : (_fps == 60 ? 1.0 : 0.75);
      _bitrateKbps = (recBitrate * fpsBoost).round().clamp(1500, 25000);
    });
  }

  void _selectFps(int fps) {
    HapticFeedback.selectionClick();
    setState(() {
      _fps = fps;
      if (fps >= 120 && _bitrateKbps < 9000) {
        _bitrateKbps = 12000;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.theav;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final glassProvider = context.watch<LiquidGlassProvider>();
    final useGlass = glassProvider.enabled;
    final isFullGlass = glassProvider.isFull;
    final mq = MediaQuery.of(context);
    final bottomPadding = mq.padding.bottom;
    final activePreset = _activePresetId;

    final bodyContent = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: p.textTertiary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.screen_share_rounded,
                    color: primaryColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isUpdatingActiveStream
                            ? 'Настройки активного эфира'
                            : 'Трансляция экрана (Go Live)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_height}p @ $_fps FPS • ${(_bitrateKbps / 1000).toStringAsFixed(1)} Мбит/с • $_codec',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: p.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_fps >= 120)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF9800), Color(0xFFFF5722)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$_fps FPS ULTRA',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),

            // 1. Smart Scenario Presets
            _sectionLabel('Быстрый выбор режима', p),
            const SizedBox(height: 8),
            _buildSmartPresetCard(
              id: 'balanced',
              title: 'Сбалансированный',
              badge: '1080p • 60 FPS',
              subtitle: 'Плавная картинка и стабильная работа в любой сети',
              icon: Icons.bolt_rounded,
              accentColor: primaryColor,
              selected: activePreset == 'balanced',
              onTap: () => _applySmartPreset('balanced'),
              p: p,
            ),
            const SizedBox(height: 8),
            _buildSmartPresetCard(
              id: 'ultra_fps',
              title: 'Ультра-плавный (Игры / Видео)',
              badge: '1440p • 144 FPS',
              subtitle: 'Максимальная частота кадров и минимальная задержка',
              icon: Icons.sports_esports_rounded,
              accentColor: const Color(0xFFFF8F00),
              selected: activePreset == 'ultra_fps',
              onTap: () => _applySmartPreset('ultra_fps'),
              p: p,
            ),
            const SizedBox(height: 8),
            _buildSmartPresetCard(
              id: 'text_clarity',
              title: 'Чёткий текст (Код / Документы)',
              badge: '1440p • VP9',
              subtitle: 'Удерживает 100% чёткость мелких шрифтов и интерфейсов',
              icon: Icons.code_rounded,
              accentColor: const Color(0xFF00C853),
              selected: activePreset == 'text_clarity',
              onTap: () => _applySmartPreset('text_clarity'),
              p: p,
            ),
            const SizedBox(height: 16),

            // 2. Content Optimization Profile (48px touch targets)
            _sectionLabel('Приоритет адаптации качества', p),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildProfileCard(
                    icon: Icons.motion_photos_on_rounded,
                    title: 'Плавность кадров',
                    subtitle: 'Без зависаний (30–144 FPS)',
                    selected: _contentHint == 'motion',
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _contentHint = 'motion');
                    },
                    primaryColor: primaryColor,
                    p: p,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildProfileCard(
                    icon: Icons.text_fields_rounded,
                    title: 'Чёткость текста',
                    subtitle: 'Фиксация разрешения',
                    selected: _contentHint == 'detail',
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _contentHint = 'detail');
                    },
                    primaryColor: primaryColor,
                    p: p,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 3. Progressive Disclosure Toggle for Pro Settings
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _showAdvanced = !_showAdvanced);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: p.surfaceSecondary.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: p.borderSubtle, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.tune_rounded,
                        size: 18,
                        color: _showAdvanced ? primaryColor : p.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Тонкая настройка (Разрешение, FPS, Битрейт, Кодек)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _showAdvanced ? primaryColor : p.textPrimary,
                          ),
                        ),
                      ),
                      Icon(
                        _showAdvanced
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: p.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: _showAdvanced
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Web source type selector (hidden on Android/iOS where OS MediaProjection handles capture)
                    if (!widget.isUpdatingActiveStream && !_isMobilePlatform) ...[
                      _sectionLabel('Область захвата', p),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildOptionChip(
                            label: 'Весь экран',
                            icon: Icons.monitor_rounded,
                            selected: _sourceType == 'screen',
                            onTap: () => setState(() => _sourceType = 'screen'),
                            primaryColor: primaryColor,
                            p: p,
                          ),
                          const SizedBox(width: 8),
                          _buildOptionChip(
                            label: 'Окно программы',
                            icon: Icons.web_asset_rounded,
                            selected: _sourceType == 'window',
                            onTap: () => setState(() => _sourceType = 'window'),
                            primaryColor: primaryColor,
                            p: p,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Resolution selector
                    _sectionLabel('Разрешение', p),
                    const SizedBox(height: 8),
                    Row(
                      children: _resolutions.map((res) {
                        final isSelected = _height == res.h;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: res == _resolutions.last ? 0 : 8,
                            ),
                            child: _buildSelectPill(
                              label: res.label,
                              sublabel: '${res.w}×${res.h}',
                              selected: isSelected,
                              onTap: () => _selectResolution(
                                res.w,
                                res.h,
                                res.recBitrate,
                              ),
                              primaryColor: primaryColor,
                              p: p,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Frame rate selector (30 / 60 / 120 / 144 FPS)
                    _sectionLabel('Частота кадров (FPS)', p),
                    const SizedBox(height: 8),
                    Row(
                      children: _fpsOptions.map((fps) {
                        final isSelected = _fps == fps;
                        final isHighFps = fps >= 120;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: fps == _fpsOptions.last ? 0 : 8,
                            ),
                            child: _buildSelectPill(
                              label: '$fps FPS',
                              sublabel: isHighFps ? 'High-FPS' : 'Стандарт',
                              selected: isSelected,
                              highlightAmber: isHighFps,
                              onTap: () => _selectFps(fps),
                              primaryColor: primaryColor,
                              p: p,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Video Codec selector (Full width row so touch targets are >= 44px on mobile)
                    _sectionLabel('Видеокодек', p),
                    const SizedBox(height: 8),
                    Row(
                      children: _codecs.map((c) {
                        final selected = _codec == c.id;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: c == _codecs.last ? 0 : 8,
                            ),
                            child: _buildSelectPill(
                              label: c.label,
                              sublabel: c.sublabel,
                              selected: selected,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _codec = c.id);
                              },
                              primaryColor: primaryColor,
                              p: p,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Bitrate slider
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _sectionLabel('Целевой битрейт', p),
                        Text(
                          '${(_bitrateKbps / 1000).toStringAsFixed(1)} Мбит/с ($_bitrateKbps kbps)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: primaryColor,
                        thumbColor: primaryColor,
                        overlayColor: primaryColor.withValues(alpha: 0.15),
                      ),
                      child: Slider(
                        value: _bitrateKbps.toDouble().clamp(1500.0, 25000.0),
                        min: 1500,
                        max: 25000,
                        divisions: 47,
                        onChanged: (v) =>
                            setState(() => _bitrateKbps = v.round()),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // System audio & Server recording toggles
            if (!_isMobilePlatform || !Platform.isAndroid)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _includeAudio,
                activeTrackColor: primaryColor,
                title: Text(
                  'Транслировать системный звук',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary,
                  ),
                ),
                subtitle: Text(
                  'Стерео Opus 128 kbps вместе с видеопотоком',
                  style: TextStyle(fontSize: 12, color: p.textSecondary),
                ),
                onChanged: (v) => setState(() => _includeAudio = v),
              ),
            if (!widget.isUpdatingActiveStream)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _enableRecording,
                activeTrackColor: Colors.redAccent,
                title: Text(
                  'Запись эфира на сервере',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary,
                  ),
                ),
                subtitle: Text(
                  'Автоматически сохранит запись в чат после завершения',
                  style: TextStyle(fontSize: 12, color: p.textSecondary),
                ),
                onChanged: (v) => setState(() => _enableRecording = v),
              ),

            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop(
                    StreamConfig(
                      width: _width,
                      height: _height,
                      fps: _fps,
                      bitrateKbps: _bitrateKbps,
                      codec: _codec,
                      contentHint: _contentHint,
                      includeAudio: _includeAudio,
                      enableServerRecording: _enableRecording,
                      sourceType: _sourceType,
                      sourceId: widget.initialConfig.sourceId,
                      sourceName: widget.initialConfig.sourceName,
                    ),
                  );
                },
                icon: Icon(
                  widget.isUpdatingActiveStream
                      ? Icons.check_rounded
                      : Icons.play_arrow_rounded,
                ),
                label: Text(
                  widget.isUpdatingActiveStream
                      ? 'Применить (${_height}p • $_fps FPS)'
                      : 'Начать трансляцию (${_height}p • $_fps FPS)',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (widget.isUpdatingActiveStream && widget.onStopStream != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: BorderSide(
                      color: Colors.redAccent.withValues(alpha: 0.6),
                    ),
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onStopStream?.call();
                  },
                  icon: const Icon(Icons.stop_screen_share_rounded),
                  label: const Text(
                    'Остановить трансляцию экрана',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (useGlass) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: LiquidGlassLens(
          style: glassProvider.createStyle(
            context: context,
            cornerRadius: 28,
            color: isDark
                ? const Color(0xFF14161C).withValues(alpha: 0.72)
                : Colors.white.withValues(alpha: 0.84),
            refractionIndex: isFullGlass ? 1.1 : 1.04,
            refractionWidth: 24.0,
          ),
          child: bodyContent,
        ),
      );
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter.grouped(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? p.surfaceElevated.withValues(alpha: 0.94)
                : Colors.white.withValues(alpha: 0.96),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(color: p.borderSubtle, width: 0.8),
            ),
          ),
          child: bodyContent,
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, TheavPalette p) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: p.textSecondary,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildSmartPresetCard({
    required String id,
    required String title,
    required String badge,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required bool selected,
    required VoidCallback onTap,
    required TheavPalette p,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? accentColor.withValues(alpha: 0.14)
                : p.surfaceSecondary.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? accentColor : p.borderSubtle,
              width: selected ? 1.5 : 0.8,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: selected
                      ? accentColor.withValues(alpha: 0.20)
                      : p.surfacePrimary.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: selected ? accentColor : p.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: selected ? accentColor : p.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: accentColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: p.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? accentColor : p.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
    required Color primaryColor,
    required TheavPalette p,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? primaryColor.withValues(alpha: 0.15)
                : p.surfaceSecondary.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? primaryColor : p.borderSubtle,
              width: selected ? 1.4 : 0.8,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 19,
                color: selected ? primaryColor : p.textSecondary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: selected ? primaryColor : p.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: p.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    required Color primaryColor,
    required TheavPalette p,
  }) {
    return Expanded(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            constraints: const BoxConstraints(minHeight: 46),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            decoration: BoxDecoration(
              color: selected
                  ? primaryColor.withValues(alpha: 0.16)
                  : p.surfaceSecondary.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? primaryColor : p.borderSubtle,
                width: selected ? 1.4 : 0.8,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? primaryColor : p.textSecondary,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? primaryColor : p.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectPill({
    required String label,
    String? sublabel,
    required bool selected,
    bool highlightAmber = false,
    required VoidCallback onTap,
    required Color primaryColor,
    required TheavPalette p,
  }) {
    final activeColor =
        highlightAmber && selected ? const Color(0xFFFF8F00) : primaryColor;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
          decoration: BoxDecoration(
            color: selected
                ? activeColor.withValues(alpha: 0.16)
                : p.surfaceSecondary.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? activeColor : p.borderSubtle,
              width: selected ? 1.4 : 0.8,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? activeColor : p.textPrimary,
                ),
              ),
              if (sublabel != null) ...[
                const SizedBox(height: 2),
                Text(
                  sublabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: selected ? activeColor : p.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for viewers to select their received stream quality
/// (Auto Simulcast, Source up to 144 FPS, Medium 720p60, Low 480p30, Audio Only).
class ViewerQualitySelectorSheet extends StatelessWidget {
  final ViewerSubscriptionQuality currentQuality;
  final CallStream? stream;

  const ViewerQualitySelectorSheet({
    super.key,
    required this.currentQuality,
    this.stream,
  });

  static Future<ViewerSubscriptionQuality?> show(
    BuildContext context, {
    required ViewerSubscriptionQuality currentQuality,
    CallStream? stream,
  }) {
    return showModalBottomSheet<ViewerSubscriptionQuality>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ViewerQualitySelectorSheet(
        currentQuality: currentQuality,
        stream: stream,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.theav;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter.grouped(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomPadding),
          decoration: BoxDecoration(
            color: isDark
                ? p.surfaceElevated.withValues(alpha: 0.94)
                : Colors.white.withValues(alpha: 0.95),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.textTertiary.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Icon(Icons.hd_rounded, color: primaryColor, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        stream != null
                            ? 'Качество просмотра (${stream!.qualityBadge} • ${stream!.codec})'
                            : 'Качество просмотра трансляции',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              ...ViewerSubscriptionQuality.values.map((q) {
                final selected = q == currentQuality;
                return ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  leading: Icon(
                    q == ViewerSubscriptionQuality.audioOnly
                        ? Icons.headphones_rounded
                        : Icons.high_quality_rounded,
                    color: selected ? primaryColor : p.textSecondary,
                  ),
                  title: Text(
                    q.label,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? primaryColor : p.textPrimary,
                    ),
                  ),
                  trailing: selected
                      ? Icon(Icons.check_circle_rounded, color: primaryColor)
                      : null,
                  onTap: () => Navigator.of(context).pop(q),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
