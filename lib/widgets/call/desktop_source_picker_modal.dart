import 'dart:io' show Platform;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../models/call_models.dart';
import '../../models/theav_theme.dart';
import '../../services/liquid_glass_provider.dart';
import 'stream_quality_sheet.dart';

/// Modal dialog for desktop platforms (Windows, macOS, Linux) allowing the user
/// to select which Display or Application Window to share, along with Smart Quality
/// Presets (up to 1440p @ 144 FPS / 4K @ 60 FPS), Content Profile (Motion vs Detail),
/// System Audio, and full Pro Codec/Bitrate settings.
class DesktopSourcePickerModal extends StatefulWidget {
  final StreamConfig initialConfig;

  const DesktopSourcePickerModal({
    super.key,
    required this.initialConfig,
  });

  static Future<StreamConfig?> show(
    BuildContext context, {
    StreamConfig initialConfig = const StreamConfig(),
  }) {
    if (kIsWeb ||
        (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux)) {
      return Future.value(initialConfig);
    }
    return showDialog<StreamConfig>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => DesktopSourcePickerModal(initialConfig: initialConfig),
    );
  }

  @override
  State<DesktopSourcePickerModal> createState() =>
      _DesktopSourcePickerModalState();
}

class _DesktopSourcePickerModalState extends State<DesktopSourcePickerModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<DesktopCapturerSource> _screenSources = [];
  List<DesktopCapturerSource> _windowSources = [];
  DesktopCapturerSource? _selectedSource;
  String? _hoveredSourceId;
  bool _isLoading = true;
  String? _error;

  late int _selectedWidth;
  late int _selectedHeight;
  late int _selectedFps;
  late int _selectedBitrateKbps;
  late String _selectedCodec;
  late String _contentHint;
  late bool _includeAudio;
  late bool _enableRecording;

  static const List<({int w, int h, int fps, int bitrate, String label})>
      _quickPresets = [
    (w: 1280, h: 720, fps: 30, bitrate: 3000, label: '720p 30'),
    (w: 1920, h: 1080, fps: 60, bitrate: 6500, label: '1080p 60'),
    (w: 1920, h: 1080, fps: 120, bitrate: 10500, label: '1080p 120'),
    (w: 2560, h: 1440, fps: 60, bitrate: 12000, label: '1440p 60'),
    (w: 2560, h: 1440, fps: 144, bitrate: 15000, label: '1440p 144'),
    (w: 3840, h: 2160, fps: 60, bitrate: 18000, label: '4K 60'),
  ];

  @override
  void initState() {
    super.initState();
    final c = widget.initialConfig;
    _selectedWidth = c.width;
    _selectedHeight = c.height;
    _selectedFps = c.fps;
    _selectedBitrateKbps = c.bitrateKbps;
    _selectedCodec = c.codec;
    _contentHint = c.contentHint;
    _includeAudio = c.includeAudio;
    _enableRecording = c.enableServerRecording;

    final initialTab = c.sourceType == 'window' ? 1 : 0;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: initialTab,
    );
    _tabController.addListener(_onTabChanged);
    _loadSources();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (!mounted) return;
    setState(() {
      if (_tabController.index == 0) {
        if (_selectedSource == null ||
            _selectedSource!.type != SourceType.Screen) {
          if (_screenSources.isNotEmpty) {
            _selectedSource = _screenSources.first;
          }
        }
      } else {
        if (_selectedSource == null ||
            _selectedSource!.type != SourceType.Window) {
          if (_windowSources.isNotEmpty) {
            _selectedSource = _windowSources.first;
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSources() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final sources = await desktopCapturer.getSources(
        types: [SourceType.Screen, SourceType.Window],
        thumbnailSize: ThumbnailSize(320, 180),
      );
      if (!mounted) return;
      final screens =
          sources.where((s) => s.type == SourceType.Screen).toList();
      final windows = sources
          .where((s) => s.type == SourceType.Window && s.name.trim().isNotEmpty)
          .toList();

      DesktopCapturerSource? matched;
      if (_selectedSource != null) {
        matched = sources
            .where((s) => s.id == _selectedSource!.id)
            .firstOrNull;
      }
      if (matched == null && widget.initialConfig.sourceId != null) {
        matched = sources
            .where((s) => s.id == widget.initialConfig.sourceId)
            .firstOrNull;
      }
      matched ??= _tabController.index == 1 && windows.isNotEmpty
          ? windows.first
          : (screens.isNotEmpty
              ? screens.first
              : (windows.isNotEmpty ? windows.first : null));

      setState(() {
        _screenSources = screens;
        _windowSources = windows;
        _selectedSource = matched;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось получить список экранов и окон: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _openProSettings() async {
    final current = _buildConfig();
    final updated = await StreamQualitySheet.show(
      context,
      initialConfig: current,
      isUpdatingActiveStream: false,
    );
    if (updated != null && mounted) {
      setState(() {
        _selectedWidth = updated.width;
        _selectedHeight = updated.height;
        _selectedFps = updated.fps;
        _selectedBitrateKbps = updated.bitrateKbps;
        _selectedCodec = updated.codec;
        _contentHint = updated.contentHint;
        _includeAudio = updated.includeAudio;
        _enableRecording = updated.enableServerRecording;
      });
    }
  }

  StreamConfig _buildConfig() {
    final source = _selectedSource;
    final width = _selectedWidth > 0
        ? _selectedWidth
        : (_selectedHeight * 16 / 9).round();
    return widget.initialConfig.copyWith(
      sourceId: source?.id,
      sourceName: source?.name,
      sourceType:
          source?.type == SourceType.Window ? 'window' : 'screen',
      width: width,
      height: _selectedHeight,
      fps: _selectedFps,
      bitrateKbps: _selectedBitrateKbps,
      codec: _selectedCodec,
      contentHint: _contentHint,
      includeAudio: _includeAudio,
      enableServerRecording: _enableRecording,
    );
  }

  void _onConfirm() {
    if (_selectedSource == null) {
      Navigator.of(context).pop();
      return;
    }
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(_buildConfig());
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final modalWidth =
            (constraints.maxWidth * 0.88).clamp(520.0, 820.0);
        final modalHeight =
            (constraints.maxHeight * 0.86).clamp(480.0, 660.0);
        final gridColumns = modalWidth >= 700 ? 3 : 2;

        final dialogBody = SizedBox(
          width: modalWidth,
          height: modalHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.15),
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
                            'Трансляция экрана (Go Live)',
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _selectedSource != null
                                ? 'Источник: ${_selectedSource!.name} • ${_selectedHeight}p @ $_selectedFps FPS ($_selectedCodec)'
                                : 'Выберите экран или окно приложения для начала эфира',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Обновить список окон',
                      icon: Icon(
                        Icons.refresh_rounded,
                        color: p.textSecondary,
                        size: 20,
                      ),
                      onPressed: _isLoading ? null : _loadSources,
                    ),
                    IconButton(
                      tooltip: 'Закрыть',
                      icon: Icon(
                        Icons.close_rounded,
                        color: p.textSecondary,
                        size: 21,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 2. Tabs (Screens vs Windows)
                Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: p.surfaceSecondary.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.borderSubtle, width: 0.8),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: primaryColor,
                    labelColor: primaryColor,
                    unselectedLabelColor: p.textSecondary,
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.monitor_rounded, size: 17),
                            const SizedBox(width: 7),
                            Text('Экраны (${_screenSources.length})'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.web_asset_rounded, size: 17),
                            const SizedBox(width: 7),
                            Text('Окна программ (${_windowSources.length})'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 3. Source Thumbnail Grid
                Expanded(
                  child: _isLoading
                      ? Center(
                          child: CircularProgressIndicator(color: primaryColor),
                        )
                      : _error != null
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.error_outline_rounded,
                                    color: Colors.redAccent,
                                    size: 36,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    onPressed: _loadSources,
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('Повторить'),
                                  ),
                                ],
                              ),
                            )
                          : TabBarView(
                              controller: _tabController,
                              children: [
                                _buildSourceGrid(
                                  _screenSources,
                                  gridColumns,
                                  primaryColor,
                                  p,
                                ),
                                _buildSourceGrid(
                                  _windowSources,
                                  gridColumns,
                                  primaryColor,
                                  p,
                                ),
                              ],
                            ),
                ),
                const SizedBox(height: 14),

                // 4. Stream Settings Control Bar (Quality Presets + Profile + Audio + Pro Tuning)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.surfaceSecondary.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: p.borderSubtle, width: 0.8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            Text(
                              'Качество:',
                              style: TextStyle(
                                color: p.textSecondary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            for (final preset in _quickPresets) ...[
                              _buildQualityChip(
                                preset.w,
                                preset.h,
                                preset.fps,
                                preset.bitrate,
                                preset.label,
                                primaryColor,
                                p,
                              ),
                              const SizedBox(width: 6),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Content Hint toggle (Motion vs Detail)
                          _buildTogglePill(
                            icon: _contentHint == 'detail'
                                ? Icons.text_fields_rounded
                                : Icons.motion_photos_on_rounded,
                            label: _contentHint == 'detail'
                                ? 'Профиль: Чёткость текста'
                                : 'Профиль: Плавность кадров',
                            active: true,
                            accentColor: _contentHint == 'detail'
                                ? const Color(0xFF00C853)
                                : primaryColor,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _contentHint = _contentHint == 'detail'
                                    ? 'motion'
                                    : 'detail';
                              });
                            },
                            p: p,
                          ),
                          // System Audio toggle
                          _buildTogglePill(
                            icon: _includeAudio
                                ? Icons.volume_up_rounded
                                : Icons.volume_off_rounded,
                            label: _includeAudio
                                ? 'Системный звук: Вкл'
                                : 'Системный звук: Выкл',
                            active: _includeAudio,
                            accentColor: primaryColor,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _includeAudio = !_includeAudio);
                            },
                            p: p,
                          ),
                          // Server Recording toggle
                          _buildTogglePill(
                            icon: Icons.fiber_manual_record_rounded,
                            label: _enableRecording
                                ? 'Запись на сервере: Вкл'
                                : 'Запись: Выкл',
                            active: _enableRecording,
                            accentColor: Colors.redAccent,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(
                                () => _enableRecording = !_enableRecording,
                              );
                            },
                            p: p,
                          ),
                          // Pro Codec & Bitrate button
                          MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: _openProSettings,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: p.surfacePrimary.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: p.borderSubtle,
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.tune_rounded,
                                      size: 15,
                                      color: p.textSecondary,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Кодек ($_selectedCodec • ${(_selectedBitrateKbps / 1000).toStringAsFixed(1)} Мбит/с)',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: p.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 5. Footer CTA Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Отмена',
                        style: TextStyle(
                          color: p.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 13,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _selectedSource != null ? _onConfirm : null,
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: Text(
                        'Начать трансляцию (${_selectedHeight}p • $_selectedFps FPS)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );

        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(24),
          child: useGlass
              ? LiquidGlassLens(
                  style: glassProvider.createStyle(
                    context: context,
                    cornerRadius: 24,
                    color: isDark
                        ? const Color(0xFF14161C).withValues(alpha: 0.78)
                        : Colors.white.withValues(alpha: 0.86),
                    refractionIndex: isFullGlass ? 1.1 : 1.04,
                    refractionWidth: 22.0,
                  ),
                  child: dialogBody,
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter.grouped(
                    filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? p.surfaceElevated.withValues(alpha: 0.96)
                            : Colors.white.withValues(alpha: 0.97),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: p.borderSubtle,
                          width: 0.9,
                        ),
                      ),
                      child: dialogBody,
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildQualityChip(
    int width,
    int height,
    int fps,
    int bitrate,
    String label,
    Color primaryColor,
    TheavPalette p,
  ) {
    final isSelected = _selectedHeight == height && _selectedFps == fps;
    final isHighFps = fps >= 120;
    final activeColor =
        isHighFps && isSelected ? const Color(0xFFFF8F00) : primaryColor;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            _selectedWidth = width;
            _selectedHeight = height;
            _selectedFps = fps;
            _selectedBitrateKbps = bitrate;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: 0.18)
                : p.surfacePrimary.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: isSelected ? activeColor : p.borderSubtle,
              width: isSelected ? 1.4 : 0.8,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? activeColor : p.textPrimary,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTogglePill({
    required IconData icon,
    required String label,
    required bool active,
    required Color accentColor,
    required VoidCallback onTap,
    required TheavPalette p,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? accentColor.withValues(alpha: 0.16)
                : p.surfacePrimary.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: active ? accentColor : p.borderSubtle,
              width: active ? 1.3 : 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: active ? accentColor : p.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? accentColor : p.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceGrid(
    List<DesktopCapturerSource> sources,
    int columns,
    Color primaryColor,
    TheavPalette p,
  ) {
    if (sources.isEmpty) {
      return Center(
        child: Text(
          'Нет доступных источников в этой категории',
          style: TextStyle(color: p.textSecondary),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.32,
      ),
      itemCount: sources.length,
      itemBuilder: (context, index) {
        final src = sources[index];
        final isSelected = _selectedSource?.id == src.id;
        final isHovered = _hoveredSourceId == src.id;

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hoveredSourceId = src.id),
          onExit: (_) {
            if (_hoveredSourceId == src.id) {
              setState(() => _hoveredSourceId = null);
            }
          },
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedSource = src);
            },
            onDoubleTap: () {
              setState(() => _selectedSource = src);
              _onConfirm();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                color: isSelected
                    ? primaryColor.withValues(alpha: 0.12)
                    : (isHovered
                        ? p.surfaceSecondary.withValues(alpha: 0.85)
                        : p.surfaceSecondary.withValues(alpha: 0.55)),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected
                      ? primaryColor
                      : (isHovered
                          ? primaryColor.withValues(alpha: 0.5)
                          : p.borderSubtle),
                  width: isSelected ? 2.0 : 1.0,
                ),
              ),
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        src.thumbnail != null && src.thumbnail!.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(9),
                                child: Image.memory(
                                  src.thumbnail!,
                                  fit: BoxFit.contain,
                                  width: double.infinity,
                                ),
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Center(
                                  child: Icon(
                                    src.type == SourceType.Window
                                        ? Icons.web_asset_rounded
                                        : Icons.desktop_windows_rounded,
                                    color: p.textTertiary,
                                    size: 34,
                                  ),
                                ),
                              ),
                        if (isSelected)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: primaryColor,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                size: 13,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Icon(
                        src.type == SourceType.Window
                            ? Icons.web_asset_rounded
                            : Icons.monitor_rounded,
                        size: 14,
                        color: isSelected ? primaryColor : p.textSecondary,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          src.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected ? primaryColor : p.textPrimary,
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
