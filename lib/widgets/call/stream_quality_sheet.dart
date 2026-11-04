import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../models/call_models.dart';
import '../../models/theav_theme.dart';
import '../../services/liquid_glass_provider.dart';

/// Bottom sheet for configuring High-FPS Screen Share / Go Live quality
/// (Resolution: 720p/1080p/1440p/4K, Frame Rate: 30/60/120/144 FPS,
/// Bitrate: 1.5–25 Mbps, Codec: VP9/AV1/H264, Content Hint: Motion/Detail,
/// System Audio, and Server Recording).
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

  static const List<({String label, int w, int h, int recBitrate})>
      _resolutions = [
    (label: '720p', w: 1280, h: 720, recBitrate: 3500),
    (label: '1080p', w: 1920, h: 1080, recBitrate: 6500),
    (label: '1440p', w: 2560, h: 1440, recBitrate: 12000),
    (label: '4K', w: 3840, h: 2160, recBitrate: 18000),
  ];

  static const List<int> _fpsOptions = [30, 60, 120, 144];
  static const List<String> _codecs = ['H264', 'VP8', 'VP9', 'AV1'];

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
    _sourceType = c.sourceType;
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
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    final bodyContent = SingleChildScrollView(
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
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
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
                          ? 'Качество трансляции'
                          : 'Настройки экрана (Go Live)',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                    Text(
                      'До 1440p @ 144 FPS • Simulcast SFU',
                      style: TextStyle(fontSize: 12.5, color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              if (_fps >= 120)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF9800), Color(0xFFFF5722)],
                    ),
                    borderRadius: BorderRadius.circular(8),
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
          const SizedBox(height: 20),

          // Source selector
          if (!widget.isUpdatingActiveStream) ...[
            _sectionLabel('Источник захвата', p),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildOptionChip(
                  label: 'Экран',
                  icon: Icons.monitor_rounded,
                  selected: _sourceType == 'screen',
                  onTap: () => setState(() => _sourceType = 'screen'),
                  primaryColor: primaryColor,
                  p: p,
                ),
                const SizedBox(width: 8),
                _buildOptionChip(
                  label: 'Окно',
                  icon: Icons.web_asset_rounded,
                  selected: _sourceType == 'window',
                  onTap: () => setState(() => _sourceType = 'window'),
                  primaryColor: primaryColor,
                  p: p,
                ),
                const SizedBox(width: 8),
                _buildOptionChip(
                  label: 'Камера',
                  icon: Icons.videocam_rounded,
                  selected: _sourceType == 'camera',
                  onTap: () => setState(() => _sourceType = 'camera'),
                  primaryColor: primaryColor,
                  p: p,
                ),
              ],
            ),
            const SizedBox(height: 18),
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
                    onTap: () =>
                        _selectResolution(res.w, res.h, res.recBitrate),
                    primaryColor: primaryColor,
                    p: p,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),

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
                    sublabel: isHighFps ? 'High-FPS' : 'Standard',
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
          const SizedBox(height: 18),

          // Bitrate slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionLabel('Битрейт видео', p),
              Text(
                '${(_bitrateKbps / 1000).toStringAsFixed(1)} Mbps ($_bitrateKbps kbps)',
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
              onChanged: (v) => setState(() => _bitrateKbps = v.round()),
            ),
          ),

          // Codec & Content Hint
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel('Кодек', p),
                    const SizedBox(height: 8),
                    Row(
                      children: _codecs.map((c) {
                        final selected = _codec == c;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: c == _codecs.last ? 0 : 6,
                            ),
                            child: _buildSelectPill(
                              label: c,
                              selected: selected,
                              onTap: () => setState(() => _codec = c),
                              primaryColor: primaryColor,
                              p: p,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel('Профиль', p),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSelectPill(
                            label: 'Игры',
                            selected: _contentHint == 'motion',
                            onTap: () =>
                                setState(() => _contentHint = 'motion'),
                            primaryColor: primaryColor,
                            p: p,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildSelectPill(
                            label: 'Текст',
                            selected: _contentHint == 'detail',
                            onTap: () =>
                                setState(() => _contentHint = 'detail'),
                            primaryColor: primaryColor,
                            p: p,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // System audio & Server recording toggles
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _includeAudio,
            activeThumbColor: primaryColor,
            title: Text(
              'Транслировать системный звук',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: p.textPrimary,
              ),
            ),
            subtitle: Text(
              'Стерео Opus 128 kbps',
              style: TextStyle(fontSize: 12, color: p.textSecondary),
            ),
            onChanged: (v) => setState(() => _includeAudio = v),
          ),
          if (!widget.isUpdatingActiveStream)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _enableRecording,
              activeThumbColor: Colors.redAccent,
              title: Text(
                'Запись на сервере (1080p @ 60fps)',
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

          const SizedBox(height: 16),
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
                  ),
                );
              },
              icon: Icon(
                widget.isUpdatingActiveStream
                    ? Icons.tune_rounded
                    : Icons.play_arrow_rounded,
              ),
              label: Text(
                widget.isUpdatingActiveStream
                    ? 'Применить (${_height}p @ $_fps FPS)'
                    : 'Начать трансляцию (${_height}p @ $_fps FPS)',
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
                : Colors.white.withValues(alpha: 0.78),
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
                : Colors.white.withValues(alpha: 0.95),
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

  Widget _buildOptionChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    required Color primaryColor,
    required TheavPalette p,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? primaryColor : p.textSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? primaryColor : p.textPrimary,
                ),
              ),
            ],
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
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
          children: [
            Text(
              label,
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
                style: TextStyle(
                  fontSize: 10,
                  color: selected ? activeColor : p.textTertiary,
                ),
              ),
            ],
          ],
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
