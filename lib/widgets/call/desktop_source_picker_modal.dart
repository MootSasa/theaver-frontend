import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../models/call_models.dart';

/// Modal dialog for desktop platforms (Windows, macOS, Linux) allowing the user
/// to select which Display or Application Window to share, along with FPS/Quality presets.
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
    if (kIsWeb || (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux)) {
      return Future.value(initialConfig);
    }
    return showDialog<StreamConfig>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => DesktopSourcePickerModal(initialConfig: initialConfig),
    );
  }

  @override
  State<DesktopSourcePickerModal> createState() => _DesktopSourcePickerModalState();
}

class _DesktopSourcePickerModalState extends State<DesktopSourcePickerModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<DesktopCapturerSource> _screenSources = [];
  List<DesktopCapturerSource> _windowSources = [];
  DesktopCapturerSource? _selectedSource;
  bool _isLoading = true;
  String? _error;

  int _selectedFps = 60;
  int _selectedHeight = 1080;
  int _selectedBitrateKbps = 6000;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedFps = widget.initialConfig.fps;
    _selectedHeight = widget.initialConfig.height;
    _selectedBitrateKbps = widget.initialConfig.bitrateKbps;
    _loadSources();
  }

  @override
  void dispose() {
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
      );
      if (!mounted) return;
      setState(() {
        _screenSources = sources.where((s) => s.type == SourceType.Screen).toList();
        _windowSources = sources.where((s) => s.type == SourceType.Window).toList();
        _selectedSource = _screenSources.isNotEmpty
            ? _screenSources.first
            : (_windowSources.isNotEmpty ? _windowSources.first : null);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось получить список окон: $e';
        _isLoading = false;
      });
    }
  }

  void _onConfirm() {
    final source = _selectedSource;
    if (source == null) {
      Navigator.of(context).pop();
      return;
    }

    final width = (_selectedHeight * 16 / 9).round();
    final config = widget.initialConfig.copyWith(
      sourceId: source.id,
      sourceName: source.name,
      sourceType: source.type == SourceType.Window ? 'window' : 'screen',
      width: width,
      height: _selectedHeight,
      fps: _selectedFps,
      bitrateKbps: _selectedBitrateKbps,
      contentHint: 'motion',
    );
    Navigator.of(context).pop(config);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        width: 640,
        height: 520,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.screen_share_rounded, color: Color(0xFF00E676), size: 24),
                const SizedBox(width: 10),
                const Text(
                  'Поделиться экраном',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white60),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFF00E676),
                labelColor: const Color(0xFF00E676),
                unselectedLabelColor: Colors.white60,
                indicatorSize: TabBarIndicatorSize.tab,
                tabs: const [
                  Tab(text: 'Весь экран'),
                  Tab(text: 'Окно программы'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
                  : _error != null
                      ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildSourceGrid(_screenSources),
                            _buildSourceGrid(_windowSources),
                          ],
                        ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text(
                  'Качество: ',
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                _buildQualityChip(720, 30, 2500, '720p 30fps'),
                const SizedBox(width: 6),
                _buildQualityChip(1080, 60, 6000, '1080p 60fps'),
                const SizedBox(width: 6),
                _buildQualityChip(1080, 120, 10000, '1080p 120fps'),
                const SizedBox(width: 6),
                _buildQualityChip(1440, 60, 12000, '1440p 60fps'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Отмена', style: TextStyle(color: Colors.white60)),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _selectedSource != null ? _onConfirm : null,
                  child: const Text('Начать трансляцию', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityChip(int height, int fps, int bitrate, String label) {
    final isSelected = _selectedHeight == height && _selectedFps == fps;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        setState(() {
          _selectedHeight = height;
          _selectedFps = fps;
          _selectedBitrateKbps = bitrate;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00E676).withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF00E676) : Colors.white12,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF00E676) : Colors.white70,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildSourceGrid(List<DesktopCapturerSource> sources) {
    if (sources.isEmpty) {
      return const Center(
        child: Text('Нет доступных источников', style: TextStyle(color: Colors.white54)),
      );
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.25,
      ),
      itemCount: sources.length,
      itemBuilder: (context, index) {
        final src = sources[index];
        final isSelected = _selectedSource?.id == src.id;

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _selectedSource = src;
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF272730),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? const Color(0xFF00E676) : Colors.white12,
                width: isSelected ? 2 : 1,
              ),
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Expanded(
                  child: src.thumbnail != null && src.thumbnail!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            src.thumbnail!,
                            fit: BoxFit.contain,
                            width: double.infinity,
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Icon(Icons.desktop_windows, color: Colors.white38, size: 36),
                          ),
                        ),
                ),
                const SizedBox(height: 6),
                Text(
                  src.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFF00E676) : Colors.white,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
