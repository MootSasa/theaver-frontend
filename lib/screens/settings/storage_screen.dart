import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../../services/settings_service.dart';
import '../../services/auth_service.dart';
import '../../services/cache_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/chat/liquid_glass_app_bar.dart';
import '../../widgets/common/adaptive_switch.dart';
import '../../utils/haptic_utils.dart';

/// Экран «Данные и хранилище» — полный пункт 3.6 плана.
/// Поддерживает два полноценных дизайна:
/// 1. Стандартный (Material 3)
/// 2. Liquid Glass (стеклянный интерфейс с шейдерами и блюром)
class StorageScreen extends StatefulWidget {
  final bool skipNetworkLoad;
  final CacheBreakdown? initialBreakdown;
  const StorageScreen({
    Key? key,
    this.skipNetworkLoad = false,
    this.initialBreakdown,
  }) : super(key: key);

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  final SettingsService _settingsService = SettingsService();
  final CacheService _cacheService = CacheService();

  late StorageSettings _autoDownloadSettings;
  bool _isLoading = true;
  bool _isClearing = false;

  // Local device cache statistics
  CacheBreakdown _cacheBreakdown = CacheBreakdown.empty();
  String _keepMediaPeriod = 'forever';
  int _maxCacheSizeBytes = 0;

  // Real storage data from server
  String _totalUsed = '0 B';
  int _totalUsedBytes = 0;
  List<_MediaTypeStorage> _byType = [];
  List<_ChatStorage> _byChat = [];

  // Storage settings from server
  StorageServerSettings _storageSettings = const StorageServerSettings();

  // Category accent colors
  static const Color colorPhotos = Color(0xFF00E5FF); // Cyan
  static const Color colorVideos = Color(0xFF2979FF); // Blue
  static const Color colorAudio = Color(0xFFFF9100); // Orange
  static const Color colorFiles = Color(0xFFD500F9); // Purple / Magenta
  static const Color colorOther = Color(0xFF78909C); // Slate grey

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    _autoDownloadSettings = _settingsService.storageSettings;
    try {
      _keepMediaPeriod = await _cacheService.getKeepMediaPeriod();
      _maxCacheSizeBytes = await _cacheService.getMaxCacheSize();
      if (widget.initialBreakdown != null) {
        _cacheBreakdown = widget.initialBreakdown!;
      } else {
        _cacheBreakdown = await _cacheService.getCacheStats();
      }
    } catch (e) {
      debugPrint('StorageScreen: cacheService load error: $e');
    }

    if (!widget.skipNetworkLoad) {
      await _loadStorageInfo();
      await _loadStorageSettings();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadStorageInfo() async {
    try {
      final token = await AuthService.getToken();
      final dio = Dio();
      final response = await dio.get(
        '${AppConfig.baseUrl}/api/settings/storage',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (mounted) {
        setState(() {
          _totalUsed = response.data['total_human'] ?? '0 B';
          _totalUsedBytes = response.data['total_used'] ?? 0;
          _byType = (response.data['by_type'] as List?)
                  ?.map((e) => _MediaTypeStorage.fromJson(e))
                  .toList() ??
              [];
          _byChat = (response.data['by_chat'] as List?)
                  ?.map((e) => _ChatStorage.fromJson(e))
                  .toList() ??
              [];
        });
      }
    } catch (e) {
      debugPrint('StorageScreen: loadStorageInfo: $e');
    }
  }

  Future<void> _loadStorageSettings() async {
    try {
      final token = await AuthService.getToken();
      final dio = Dio();
      final response = await dio.get(
        '${AppConfig.baseUrl}/api/settings/storage/settings',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (mounted) {
        setState(() {
          _storageSettings = StorageServerSettings.fromJson(response.data);
        });
      }
    } catch (e) {
      debugPrint('StorageScreen: loadStorageSettings: $e');
    }
  }

  Future<void> _saveStorageSettings(StorageServerSettings settings) async {
    try {
      final token = await AuthService.getToken();
      final dio = Dio();
      await dio.put(
        '${AppConfig.baseUrl}/api/settings/storage/settings',
        data: settings.toJson(),
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (mounted) {
        setState(() => _storageSettings = settings);
      }
    } catch (e) {
      debugPrint('StorageScreen: saveStorageSettings: $e');
    }
  }

  /// Perform selective clearing of local cache and notify server
  Future<void> _performClearSelected({
    required bool photos,
    required bool videos,
    required bool audio,
    required bool files,
    required bool other,
  }) async {
    final l10n = context.l10n;
    setState(() => _isClearing = true);

    try {
      // 1. Clear local device cache files
      final freed = await _cacheService.clearCache(
        photos: photos,
        videos: videos,
        audio: audio,
        files: files,
        other: other,
      );

      // 2. Notify backend server of cache clearance (media preserved in MinIO)
      try {
        final token = await AuthService.getToken();
        if (token != null) {
          final dio = Dio();
          await dio.post(
            '${AppConfig.baseUrl}/api/settings/storage/clear',
            data: {
              if (photos && !videos && !audio && !files && !other) 'media_type': 'photos',
              if (videos && !photos && !audio && !files && !other) 'media_type': 'videos',
              if (audio && !photos && !videos && !files && !other) 'media_type': 'audio',
              if (files && !photos && !videos && !audio && !other) 'media_type': 'files',
            },
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          );
        }
      } catch (e) {
        debugPrint('StorageScreen: server clear error: $e');
      }

      // 3. Refresh statistics
      final updatedBreakdown = await _cacheService.getCacheStats();
      await _loadStorageInfo();

      if (mounted) {
        setState(() {
          _cacheBreakdown = updatedBreakdown;
        });
        final freedStr = CacheService.formatBytes(freed);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.translate('storage_cache_cleared')} ($freedStr)'),
            backgroundColor: const Color(0xFF0088CC),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  /// Clear cache for a specific chat
  Future<void> _clearChatCache(String chatId) async {
    final l10n = context.l10n;
    setState(() => _isClearing = true);

    try {
      final token = await AuthService.getToken();
      final dio = Dio();
      await dio.post(
        '${AppConfig.baseUrl}/api/settings/storage/clear',
        data: {'chat_id': chatId},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      // Also refresh local cache
      final updatedBreakdown = await _cacheService.getCacheStats();
      await _loadStorageInfo();

      if (mounted) {
        setState(() {
          _cacheBreakdown = updatedBreakdown;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('storage_clear_success'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  void _showClearChatDialog(_ChatStorage chat) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('storage_clear_chat_cache_title').replaceAll('{chat}', chat.chatName)),
        content: Text(l10n.translate('storage_clear_chat_cache_message')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.translate('storage_cancel'))),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _clearChatCache(chat.chatId);
            },
            child: Text(l10n.translate('storage_clear'), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDownloadPath() async {
    final l10n = context.l10n;
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      await _settingsService.updateDownloadPath(selectedDirectory);
      setState(() => _autoDownloadSettings = _settingsService.storageSettings);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.translate('storage_download_path_set')}: $selectedDirectory')),
        );
      }
    }
  }

  Future<void> _updateAutoDownload({
    bool? photosWifi, bool? videosWifi, bool? filesWifi, bool? audioWifi,
    bool? photosCellular, bool? videosCellular, bool? filesCellular, bool? audioCellular,
    bool? photosRoaming, bool? videosRoaming, bool? filesRoaming, bool? audioRoaming,
  }) async {
    await _settingsService.updateAutoDownloadSettings(
      photosWifi: photosWifi, videosWifi: videosWifi, filesWifi: filesWifi, audioWifi: audioWifi,
      photosCellular: photosCellular, videosCellular: videosCellular, filesCellular: filesCellular, audioCellular: audioCellular,
      photosRoaming: photosRoaming, videosRoaming: videosRoaming, filesRoaming: filesRoaming, audioRoaming: audioRoaming,
    );
    setState(() => _autoDownloadSettings = _settingsService.storageSettings);
  }

  // ===================== UI BUILD =====================

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Consumer<LiquidGlassProvider>(
      builder: (context, glassProvider, _) {
        final glassEnabled = glassProvider.enabled;
        final isLite = glassProvider.isLite;

        if (glassEnabled) {
          final topPadding = MediaQuery.of(context).padding.top + kToolbarHeight;
          return Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                          physics: const ClampingScrollPhysics(),
                          padding: EdgeInsets.only(top: topPadding + 10, bottom: 40),
                          children: _buildSections(context, l10n, glassEnabled: true, isLite: isLite),
                        ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LiquidGlassAppBar(
                    title: Text(l10n.translate('storage_title')),
                    centerTitle: true,
                    isLite: isLite,
                  ),
                ),
                if (_isClearing)
                  Container(
                    color: Colors.black45,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          );
        }

        // Standard Material 3 Design
        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.translate('storage_title')),
            centerTitle: true,
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    ListView(
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      children: _buildSections(context, l10n, glassEnabled: false, isLite: false),
                    ),
                    if (_isClearing)
                      Container(
                        color: Colors.black26,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
        );
      },
    );
  }

  /// Build all settings sections
  List<Widget> _buildSections(
    BuildContext context,
    AppLocalizations l10n, {
    required bool glassEnabled,
    required bool isLite,
  }) {
    return [
      // 1. Live Storage Breakdown & Meter Card
      _buildStorageMeterCard(context, l10n, glassEnabled: glassEnabled, isLite: isLite),

      const SizedBox(height: 16),

      // 2. Keep Media ("Хранить медиа")
      _buildKeepMediaCard(context, l10n, glassEnabled: glassEnabled, isLite: isLite),

      const SizedBox(height: 16),

      // 3. Maximum Cache Size ("Максимальный размер кэша")
      _buildMaxCacheSizeCard(context, l10n, glassEnabled: glassEnabled, isLite: isLite),

      const SizedBox(height: 16),

      // 4. Per-Chat Storage (if chats exist)
      if (_byChat.isNotEmpty) ...[
        _buildSectionHeader(l10n.translate('storage_chats')),
        _buildChatStorageCard(context, l10n, glassEnabled: glassEnabled, isLite: isLite),
        const SizedBox(height: 16),
      ],

      // 5. Auto-Download Media
      _buildSectionHeader(l10n.translate('storage_auto_download')),
      _buildAutoDownloadCard(context, l10n, glassEnabled: glassEnabled, isLite: isLite),

      const SizedBox(height: 16),

      // 6. Additional Settings
      _buildSectionHeader(l10n.translate('storage_additional_section')),
      _buildAdditionalSettingsCard(context, l10n, glassEnabled: glassEnabled, isLite: isLite),
    ];
  }

  // ===================== SECTION 1: STORAGE METER =====================

  Widget _buildStorageMeterCard(
    BuildContext context,
    AppLocalizations l10n, {
    required bool glassEnabled,
    required bool isLite,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Use local cache breakdown if available, else server stats
    final hasLocal = _cacheBreakdown.totalBytes > 0;
    final totalBytes = hasLocal ? _cacheBreakdown.totalBytes : _totalUsedBytes;
    final totalHuman = hasLocal ? _cacheBreakdown.totalHuman : _totalUsed;

    final pBytes = hasLocal ? _cacheBreakdown.photos.sizeBytes : _findServerTypeBytes('photos');
    final vBytes = hasLocal ? _cacheBreakdown.videos.sizeBytes : _findServerTypeBytes('videos');
    final aBytes = hasLocal ? _cacheBreakdown.audio.sizeBytes : _findServerTypeBytes('audio');
    final fBytes = hasLocal ? _cacheBreakdown.files.sizeBytes : _findServerTypeBytes('files');
    final oBytes = hasLocal ? _cacheBreakdown.other.sizeBytes : _findServerTypeBytes('other');

    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.translate('storage_device_cache'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.translate('storage_device_cache_desc'),
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
            Text(
              totalHuman,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),

        const SizedBox(height: 18),

        // Multi-colored segmented storage bar
        _buildSegmentedBar(
          context,
          totalBytes: totalBytes,
          photosBytes: pBytes,
          videosBytes: vBytes,
          audioBytes: aBytes,
          filesBytes: fBytes,
          otherBytes: oBytes,
          glassEnabled: glassEnabled,
        ),

        const SizedBox(height: 16),

        // Category Legend
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _buildLegendItem(
              color: colorPhotos,
              label: l10n.translate('storage_photos'),
              size: CacheService.formatBytes(pBytes),
            ),
            _buildLegendItem(
              color: colorVideos,
              label: l10n.translate('storage_videos'),
              size: CacheService.formatBytes(vBytes),
            ),
            _buildLegendItem(
              color: colorAudio,
              label: l10n.translate('storage_audio'),
              size: CacheService.formatBytes(aBytes),
            ),
            _buildLegendItem(
              color: colorFiles,
              label: l10n.translate('storage_files'),
              size: CacheService.formatBytes(fBytes),
            ),
            _buildLegendItem(
              color: colorOther,
              label: l10n.translate('storage_other'),
              size: CacheService.formatBytes(oBytes),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Prominent "Clear Cache" button (Dual-design)
        if (glassEnabled)
          _buildGlassClearButton(context, l10n, isLite: isLite)
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.delete_sweep_outlined),
              label: Text(l10n.translate('storage_clear_cache')),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _showClearCacheBottomSheet(context, glassEnabled: false, isLite: false),
            ),
          ),
      ],
    );

    return _buildSectionCard(
      context: context,
      glassEnabled: glassEnabled,
      isLite: isLite,
      child: child,
    );
  }

  int _findServerTypeBytes(String type) {
    for (final item in _byType) {
      if (item.mediaType == type) return item.sizeBytes;
    }
    return 0;
  }

  /// Horizontal segmented bar showing media proportions
  Widget _buildSegmentedBar(
    BuildContext context, {
    required int totalBytes,
    required int photosBytes,
    required int videosBytes,
    required int audioBytes,
    required int filesBytes,
    required int otherBytes,
    required bool glassEnabled,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (totalBytes <= 0) {
      return Container(
        height: glassEnabled ? 16 : 14,
        decoration: BoxDecoration(
          color: isDark ? Colors.white12 : Colors.black12,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          '0 B',
          style: TextStyle(
            fontSize: 10,
            color: isDark ? Colors.white54 : Colors.black45,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    // Calculate proportions with minimum flex so small fractions remain visible
    int flex(int bytes) {
      if (bytes <= 0) return 0;
      final f = (bytes / totalBytes * 1000).round();
      return f < 8 ? 8 : f;
    }

    final pFlex = flex(photosBytes);
    final vFlex = flex(videosBytes);
    final aFlex = flex(audioBytes);
    final fFlex = flex(filesBytes);
    final oFlex = flex(otherBytes);

    return Container(
      height: glassEnabled ? 18 : 14,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black12,
        borderRadius: BorderRadius.circular(glassEnabled ? 9 : 7),
        boxShadow: glassEnabled
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          if (pFlex > 0)
            Expanded(
              flex: pFlex,
              child: _barSegment(colorPhotos, glassEnabled: glassEnabled),
            ),
          if (vFlex > 0)
            Expanded(
              flex: vFlex,
              child: _barSegment(colorVideos, glassEnabled: glassEnabled),
            ),
          if (aFlex > 0)
            Expanded(
              flex: aFlex,
              child: _barSegment(colorAudio, glassEnabled: glassEnabled),
            ),
          if (fFlex > 0)
            Expanded(
              flex: fFlex,
              child: _barSegment(colorFiles, glassEnabled: glassEnabled),
            ),
          if (oFlex > 0)
            Expanded(
              flex: oFlex,
              child: _barSegment(colorOther, glassEnabled: glassEnabled),
            ),
        ],
      ),
    );
  }

  Widget _barSegment(Color color, {required bool glassEnabled}) {
    if (!glassEnabled) {
      return Container(
        color: color,
        margin: const EdgeInsets.symmetric(horizontal: 0.5),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0.5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.95),
            color.withValues(alpha: 0.75),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 3,
            spreadRadius: 0.5,
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem({
    required Color color,
    required String label,
    required String size,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 2,
              ),
            ],
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            '$label: ',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
        Text(
          size,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildGlassClearButton(
    BuildContext context,
    AppLocalizations l10n, {
    required bool isLite,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        HapticUtils.selection();
        _showClearCacheBottomSheet(context, glassEnabled: true, isLite: isLite);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: isDark
                ? [
                    Colors.redAccent.withValues(alpha: 0.25),
                    Colors.redAccent.withValues(alpha: 0.15),
                  ]
                : [
                    Colors.redAccent.withValues(alpha: 0.18),
                    Colors.redAccent.withValues(alpha: 0.10),
                  ],
          ),
          border: Border.all(
            color: Colors.redAccent.withValues(alpha: isDark ? 0.5 : 0.4),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.redAccent.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent, size: 20),
            const SizedBox(width: 8),
            Text(
              l10n.translate('storage_clear_cache'),
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== SECTION 2: KEEP MEDIA =====================

  Widget _buildKeepMediaCard(
    BuildContext context,
    AppLocalizations l10n, {
    required bool glassEnabled,
    required bool isLite,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final options = <({String value, String label})>[
      (value: '3days', label: l10n.translate('storage_keep_3days')),
      (value: '1week', label: l10n.translate('storage_keep_1week')),
      (value: '1month', label: l10n.translate('storage_keep_1month')),
      (value: 'forever', label: l10n.translate('storage_keep_forever')),
    ];

    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('storage_keep_media_section'),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.translate('storage_keep_media_desc'),
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white60 : Colors.black54,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 14),

        if (glassEnabled)
          _buildGlassSegmentedControl<String>(
            context: context,
            isLite: isLite,
            selectedValue: _keepMediaPeriod,
            options: options,
            onSelected: (val) async {
              setState(() => _keepMediaPeriod = val);
              await _cacheService.setKeepMediaPeriod(val);
              await _saveStorageSettings(
                _storageSettings.copyWithField('keep_photos', val),
              );
            },
          )
        else
          _buildStandardSegmentedControl<String>(
            context: context,
            selectedValue: _keepMediaPeriod,
            options: options,
            onSelected: (val) async {
              setState(() => _keepMediaPeriod = val);
              await _cacheService.setKeepMediaPeriod(val);
              await _saveStorageSettings(
                _storageSettings.copyWithField('keep_photos', val),
              );
            },
          ),
      ],
    );

    return _buildSectionCard(
      context: context,
      glassEnabled: glassEnabled,
      isLite: isLite,
      child: child,
    );
  }

  // ===================== SECTION 3: MAX CACHE SIZE =====================

  Widget _buildMaxCacheSizeCard(
    BuildContext context,
    AppLocalizations l10n, {
    required bool glassEnabled,
    required bool isLite,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final options = <({int value, String label})>[
      (value: 524288000, label: '500 MB'),
      (value: 1073741824, label: '1 GB'),
      (value: 2147483648, label: '2 GB'),
      (value: 0, label: l10n.translate('storage_no_limit')),
    ];

    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('storage_max_cache_size'),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.translate('storage_max_cache_size_desc'),
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white60 : Colors.black54,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 14),

        if (glassEnabled)
          _buildGlassSegmentedControl<int>(
            context: context,
            isLite: isLite,
            selectedValue: _maxCacheSizeBytes,
            options: options,
            onSelected: (val) async {
              setState(() => _maxCacheSizeBytes = val);
              await _cacheService.setMaxCacheSize(val);
            },
          )
        else
          _buildStandardSegmentedControl<int>(
            context: context,
            selectedValue: _maxCacheSizeBytes,
            options: options,
            onSelected: (val) async {
              setState(() => _maxCacheSizeBytes = val);
              await _cacheService.setMaxCacheSize(val);
            },
          ),
      ],
    );

    return _buildSectionCard(
      context: context,
      glassEnabled: glassEnabled,
      isLite: isLite,
      child: child,
    );
  }

  // ===================== SECTION 4: PER-CHAT STORAGE =====================

  Widget _buildChatStorageCard(
    BuildContext context,
    AppLocalizations l10n, {
    required bool glassEnabled,
    required bool isLite,
  }) {
    final child = Column(
      children: [
        for (int i = 0; i < _byChat.length; i++) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
              child: Icon(Icons.chat_bubble_outline, color: Theme.of(context).colorScheme.primary, size: 20),
            ),
            title: Text(_byChat[i].chatName, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${_byChat[i].fileCount} ${l10n.translate('storage_files_count')}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_byChat[i].sizeHuman, style: const TextStyle(fontWeight: FontWeight.w500)),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => _showClearChatDialog(_byChat[i]),
                ),
              ],
            ),
          ),
          if (i < _byChat.length - 1)
            const Divider(height: 1),
        ],
      ],
    );

    return _buildSectionCard(
      context: context,
      glassEnabled: glassEnabled,
      isLite: isLite,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: child,
    );
  }

  // ===================== SECTION 5: AUTO-DOWNLOAD =====================

  Widget _buildAutoDownloadCard(
    BuildContext context,
    AppLocalizations l10n, {
    required bool glassEnabled,
    required bool isLite,
  }) {
    final child = Column(
      children: [
        _autoDownloadExpansionTile(l10n, l10n.translate('storage_on_wifi'), wifi: true),
        const Divider(height: 1),
        _autoDownloadExpansionTile(l10n, l10n.translate('storage_on_cellular'), cellular: true),
        const Divider(height: 1),
        _autoDownloadExpansionTile(l10n, l10n.translate('storage_on_roaming'), roaming: true),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.translate('storage_download_path')),
          subtitle: Text(
            _autoDownloadSettings.downloadPath ?? l10n.translate('storage_download_path_default'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.folder_open),
          onTap: _selectDownloadPath,
        ),
      ],
    );

    return _buildSectionCard(
      context: context,
      glassEnabled: glassEnabled,
      isLite: isLite,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: child,
    );
  }

  Widget _autoDownloadExpansionTile(
    AppLocalizations l10n,
    String title, {
    bool wifi = false,
    bool cellular = false,
    bool roaming = false,
  }) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      children: [
        ListTile(
          contentPadding: const EdgeInsets.only(left: 12),
          title: Text(l10n.translate('storage_photos')),
          trailing: AdaptiveSwitch(
            value: wifi
                ? _autoDownloadSettings.autoDownloadPhotosOnWifi
                : cellular
                    ? _autoDownloadSettings.autoDownloadPhotosOnCellular
                    : _autoDownloadSettings.autoDownloadPhotosOnRoaming,
            onChanged: (v) => _updateAutoDownload(
              photosWifi: wifi ? v : null,
              photosCellular: cellular ? v : null,
              photosRoaming: roaming ? v : null,
            ),
          ),
        ),
        ListTile(
          contentPadding: const EdgeInsets.only(left: 12),
          title: Text(l10n.translate('storage_videos')),
          trailing: AdaptiveSwitch(
            value: wifi
                ? _autoDownloadSettings.autoDownloadVideosOnWifi
                : cellular
                    ? _autoDownloadSettings.autoDownloadVideosOnCellular
                    : _autoDownloadSettings.autoDownloadVideosOnRoaming,
            onChanged: (v) => _updateAutoDownload(
              videosWifi: wifi ? v : null,
              videosCellular: cellular ? v : null,
              videosRoaming: roaming ? v : null,
            ),
          ),
        ),
        ListTile(
          contentPadding: const EdgeInsets.only(left: 12),
          title: Text(l10n.translate('storage_files')),
          trailing: AdaptiveSwitch(
            value: wifi
                ? _autoDownloadSettings.autoDownloadFilesOnWifi
                : cellular
                    ? _autoDownloadSettings.autoDownloadFilesOnCellular
                    : _autoDownloadSettings.autoDownloadFilesOnRoaming,
            onChanged: (v) => _updateAutoDownload(
              filesWifi: wifi ? v : null,
              filesCellular: cellular ? v : null,
              filesRoaming: roaming ? v : null,
            ),
          ),
        ),
        ListTile(
          contentPadding: const EdgeInsets.only(left: 12),
          title: Text(l10n.translate('storage_audio')),
          trailing: AdaptiveSwitch(
            value: wifi
                ? _autoDownloadSettings.autoDownloadAudioOnWifi
                : cellular
                    ? _autoDownloadSettings.autoDownloadAudioOnCellular
                    : _autoDownloadSettings.autoDownloadAudioOnRoaming,
            onChanged: (v) => _updateAutoDownload(
              audioWifi: wifi ? v : null,
              audioCellular: cellular ? v : null,
              audioRoaming: roaming ? v : null,
            ),
          ),
        ),
      ],
    );
  }

  // ===================== SECTION 6: ADDITIONAL SETTINGS =====================

  Widget _buildAdditionalSettingsCard(
    BuildContext context,
    AppLocalizations l10n, {
    required bool glassEnabled,
    required bool isLite,
  }) {
    final child = Column(
      children: [
        AdaptiveSwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.translate('storage_compress_images')),
          subtitle: Text(l10n.translate('storage_compress_images_desc')),
          value: _storageSettings.compressImages,
          onChanged: (v) => _saveStorageSettings(
            _storageSettings.copyWithField('compress_images', v),
          ),
        ),
        const Divider(height: 1),
        AdaptiveSwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.translate('storage_auto_download_stickers')),
          value: _storageSettings.autoDownloadStickers,
          onChanged: (v) => _saveStorageSettings(
            _storageSettings.copyWithField('auto_download_stickers', v),
          ),
        ),
        const Divider(height: 1),
        AdaptiveSwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.translate('storage_suggest_stickers')),
          value: _storageSettings.suggestStickers,
          onChanged: (v) => _saveStorageSettings(
            _storageSettings.copyWithField('suggest_stickers', v),
          ),
        ),
        const Divider(height: 1),
        AdaptiveSwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.translate('storage_suggest_emoji')),
          value: _storageSettings.suggestEmoji,
          onChanged: (v) => _saveStorageSettings(
            _storageSettings.copyWithField('suggest_emoji', v),
          ),
        ),
      ],
    );

    return _buildSectionCard(
      context: context,
      glassEnabled: glassEnabled,
      isLite: isLite,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: child,
    );
  }

  // ===================== CLEAR CACHE BOTTOM SHEET =====================

  void _showClearCacheBottomSheet(
    BuildContext context, {
    required bool glassEnabled,
    required bool isLite,
  }) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    bool clearPhotos = true;
    bool clearVideos = true;
    bool clearAudio = true;
    bool clearFiles = true;
    bool clearOther = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: glassEnabled ? Colors.transparent : null,
      shape: glassEnabled
          ? null
          : const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final allSelected = clearPhotos && clearVideos && clearAudio && clearFiles && clearOther;
            final noneSelected = !clearPhotos && !clearVideos && !clearAudio && !clearFiles && !clearOther;

            var selectedBytes = 0;
            if (clearPhotos) selectedBytes += _cacheBreakdown.photos.sizeBytes;
            if (clearVideos) selectedBytes += _cacheBreakdown.videos.sizeBytes;
            if (clearAudio) selectedBytes += _cacheBreakdown.audio.sizeBytes;
            if (clearFiles) selectedBytes += _cacheBreakdown.files.sizeBytes;
            if (clearOther) selectedBytes += _cacheBreakdown.other.sizeBytes;

            final clearButtonText = selectedBytes > 0
                ? '${l10n.translate('storage_clear')} (${CacheService.formatBytes(selectedBytes)})'
                : l10n.translate('storage_clear_cache');

            final sheetBody = SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                left: 20,
                right: 20,
                top: 12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Handle indicator
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white30 : Colors.black26,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header with Select All toggle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.translate('storage_clear_cache_title'),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        onPressed: () {
                          HapticUtils.selection();
                          setModalState(() {
                            final newVal = !allSelected;
                            clearPhotos = newVal;
                            clearVideos = newVal;
                            clearAudio = newVal;
                            clearFiles = newVal;
                            clearOther = newVal;
                          });
                        },
                        child: Text(
                          allSelected
                              ? l10n.translate('storage_deselect_all')
                              : l10n.translate('storage_select_all'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Category check items
                  _categoryCheckboxTile(
                    icon: Icons.photo_library_outlined,
                    color: colorPhotos,
                    title: l10n.translate('storage_photos'),
                    size: _cacheBreakdown.photos.sizeHuman,
                    count: _cacheBreakdown.photos.fileCount,
                    value: clearPhotos,
                    onChanged: (v) => setModalState(() => clearPhotos = v ?? false),
                  ),
                  _categoryCheckboxTile(
                    icon: Icons.videocam_outlined,
                    color: colorVideos,
                    title: l10n.translate('storage_videos'),
                    size: _cacheBreakdown.videos.sizeHuman,
                    count: _cacheBreakdown.videos.fileCount,
                    value: clearVideos,
                    onChanged: (v) => setModalState(() => clearVideos = v ?? false),
                  ),
                  _categoryCheckboxTile(
                    icon: Icons.audiotrack_outlined,
                    color: colorAudio,
                    title: l10n.translate('storage_audio'),
                    size: _cacheBreakdown.audio.sizeHuman,
                    count: _cacheBreakdown.audio.fileCount,
                    value: clearAudio,
                    onChanged: (v) => setModalState(() => clearAudio = v ?? false),
                  ),
                  _categoryCheckboxTile(
                    icon: Icons.insert_drive_file_outlined,
                    color: colorFiles,
                    title: l10n.translate('storage_files'),
                    size: _cacheBreakdown.files.sizeHuman,
                    count: _cacheBreakdown.files.fileCount,
                    value: clearFiles,
                    onChanged: (v) => setModalState(() => clearFiles = v ?? false),
                  ),
                  _categoryCheckboxTile(
                    icon: Icons.folder_outlined,
                    color: colorOther,
                    title: l10n.translate('storage_other'),
                    size: _cacheBreakdown.other.sizeHuman,
                    count: _cacheBreakdown.other.fileCount,
                    value: clearOther,
                    onChanged: (v) => setModalState(() => clearOther = v ?? false),
                  ),

                  const SizedBox(height: 12),

                  // Reassurance note: Media remains in MinIO cloud
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_done_outlined,
                          color: Theme.of(context).colorScheme.primary,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l10n.translate('storage_cloud_note'),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : Colors.black87,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Clear button
                  FilledButton(
                    onPressed: noneSelected
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            await _performClearSelected(
                              photos: clearPhotos,
                              videos: clearVideos,
                              audio: clearAudio,
                              files: clearFiles,
                              other: clearOther,
                            );
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      clearButtonText,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            );

            if (glassEnabled) {
              return ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color.fromARGB(220, 20, 20, 32)
                          : const Color.fromARGB(220, 245, 245, 252),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                      border: Border(
                        top: BorderSide(
                          color: isDark ? Colors.white24 : Colors.black12,
                          width: 0.8,
                        ),
                      ),
                    ),
                    child: sheetBody,
                  ),
                ),
              );
            }

            return sheetBody;
          },
        );
      },
    );
  }

  Widget _categoryCheckboxTile({
    required IconData icon,
    required Color color,
    required String title,
    required String size,
    required int count,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(count > 0 ? '$size ($count ${context.l10n.translate('storage_files_count')})' : size),
      contentPadding: EdgeInsets.zero,
    );
  }

  // ===================== REUSABLE DUAL-DESIGN CARD =====================

  Widget _buildSectionCard({
    required BuildContext context,
    required bool glassEnabled,
    required bool isLite,
    required Widget child,
    EdgeInsetsGeometry margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (glassEnabled) {
      const shape = LiquidRoundedSuperellipse(borderRadius: 20);
      final glassContent = GlassGlow(
        child: Container(
          width: double.infinity,
          margin: margin,
          padding: padding,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
          child: child,
        ),
      );

      final glassSettings = LiquidGlassSettings(
        refractiveIndex: 1.1,
        thickness: 10,
        blur: 14,
        saturation: 1.2,
        lightIntensity: isDark ? 0.4 : 0.7,
        ambientStrength: isDark ? 0.15 : 0.3,
        glassColor: isDark
            ? const Color.fromARGB(80, 20, 20, 30)
            : const Color.fromARGB(80, 240, 240, 245),
      );

      return isLite
          ? FakeGlass(shape: shape, child: glassContent)
          : LiquidGlass.withOwnLayer(
              shape: shape,
              settings: glassSettings,
              child: glassContent,
            );
    }

    // Standard Material 3 Card
    return Card(
      margin: margin,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }

  // ===================== REUSABLE SEGMENTED CONTROLS =====================

  Widget _buildGlassSegmentedControl<T>({
    required BuildContext context,
    required bool isLite,
    required T selectedValue,
    required List<({T value, String label})> options,
    required ValueChanged<T> onSelected,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      child: Row(
        children: options.map((opt) {
          final isSelected = opt.value == selectedValue;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticUtils.selection();
                onSelected(opt.value);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: isSelected
                      ? LinearGradient(
                          colors: isDark
                              ? [const Color(0xFF0088CC), const Color(0xFF00B4D8)]
                              : [const Color(0xFF0077B6), const Color(0xFF0096C7)],
                        )
                      : null,
                  color: isSelected ? null : Colors.transparent,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF0088CC).withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  opt.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected
                        ? Colors.white
                        : (isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStandardSegmentedControl<T>({
    required BuildContext context,
    required T selectedValue,
    required List<({T value, String label})> options,
    required ValueChanged<T> onSelected,
  }) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<T>(
        showSelectedIcon: false,
        segments: options
            .map((opt) => ButtonSegment<T>(
                  value: opt.value,
                  label: Text(opt.label, style: const TextStyle(fontSize: 11)),
                ))
            .toList(),
        selected: {selectedValue},
        onSelectionChanged: (newSet) {
          HapticUtils.selection();
          onSelected(newSet.first);
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

// ============ Data Models ============

class _MediaTypeStorage {
  final String mediaType;
  final int sizeBytes;
  final int fileCount;
  final String sizeHuman;

  _MediaTypeStorage({
    required this.mediaType,
    required this.sizeBytes,
    required this.fileCount,
    required this.sizeHuman,
  });

  factory _MediaTypeStorage.fromJson(Map<String, dynamic> json) => _MediaTypeStorage(
        mediaType: json['media_type'] ?? '',
        sizeBytes: json['size_bytes'] ?? 0,
        fileCount: json['file_count'] ?? 0,
        sizeHuman: json['size_human'] ?? '0 B',
      );
}

class _ChatStorage {
  final String chatId;
  final String chatName;
  final int sizeBytes;
  final int fileCount;
  final String sizeHuman;

  _ChatStorage({
    required this.chatId,
    required this.chatName,
    required this.sizeBytes,
    required this.fileCount,
    required this.sizeHuman,
  });

  factory _ChatStorage.fromJson(Map<String, dynamic> json) => _ChatStorage(
        chatId: json['chat_id'] ?? '',
        chatName: json['chat_name'] ?? '',
        sizeBytes: json['size_bytes'] ?? 0,
        fileCount: json['file_count'] ?? 0,
        sizeHuman: json['size_human'] ?? '0 B',
      );
}

class StorageServerSettings {
  final String keepPhotos;
  final String keepVideos;
  final String keepFiles;
  final String keepAudio;
  final String keepStickers;
  final bool compressImages;
  final int imageCompressionQuality;
  final bool autoDownloadStickers;
  final bool suggestStickers;
  final bool suggestEmoji;

  const StorageServerSettings({
    this.keepPhotos = 'forever',
    this.keepVideos = 'forever',
    this.keepFiles = 'forever',
    this.keepAudio = 'forever',
    this.keepStickers = 'forever',
    this.compressImages = true,
    this.imageCompressionQuality = 80,
    this.autoDownloadStickers = true,
    this.suggestStickers = true,
    this.suggestEmoji = true,
  });

  factory StorageServerSettings.fromJson(Map<String, dynamic> json) => StorageServerSettings(
        keepPhotos: json['keep_photos'] ?? 'forever',
        keepVideos: json['keep_videos'] ?? 'forever',
        keepFiles: json['keep_files'] ?? 'forever',
        keepAudio: json['keep_audio'] ?? 'forever',
        keepStickers: json['keep_stickers'] ?? 'forever',
        compressImages: json['compress_images'] ?? true,
        imageCompressionQuality: json['image_compression_quality'] ?? 80,
        autoDownloadStickers: json['auto_download_stickers'] ?? true,
        suggestStickers: json['suggest_stickers'] ?? true,
        suggestEmoji: json['suggest_emoji'] ?? true,
      );

  Map<String, dynamic> toJson() => {
        'keep_photos': keepPhotos,
        'keep_videos': keepVideos,
        'keep_files': keepFiles,
        'keep_audio': keepAudio,
        'keep_stickers': keepStickers,
        'compress_images': compressImages,
        'image_compression_quality': imageCompressionQuality,
        'auto_download_stickers': autoDownloadStickers,
        'suggest_stickers': suggestStickers,
        'suggest_emoji': suggestEmoji,
      };

  StorageServerSettings copyWithField(String field, dynamic value) {
    return StorageServerSettings(
      keepPhotos: field == 'keep_photos' ? value as String : keepPhotos,
      keepVideos: field == 'keep_videos' ? value as String : keepVideos,
      keepFiles: field == 'keep_files' ? value as String : keepFiles,
      keepAudio: field == 'keep_audio' ? value as String : keepAudio,
      keepStickers: field == 'keep_stickers' ? value as String : keepStickers,
      compressImages: field == 'compress_images' ? value as bool : compressImages,
      imageCompressionQuality:
          field == 'image_compression_quality' ? value as int : imageCompressionQuality,
      autoDownloadStickers:
          field == 'auto_download_stickers' ? value as bool : autoDownloadStickers,
      suggestStickers: field == 'suggest_stickers' ? value as bool : suggestStickers,
      suggestEmoji: field == 'suggest_emoji' ? value as bool : suggestEmoji,
    );
  }
}
