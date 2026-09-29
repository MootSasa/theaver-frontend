import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:draggable_scrollbar/draggable_scrollbar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/liquid_glass_provider.dart';

enum AttachmentPickerAction {
  camera,
  gallery,
  file,
  location,
  poll,
  contact,
  music,
}

class AttachmentPickerResult {
  final AttachmentPickerAction? action;
  final List<File>? files;
  final bool asDocument;
  final bool sendImmediately;

  const AttachmentPickerResult.action(this.action)
      : files = null,
        asDocument = false,
        sendImmediately = false;

  const AttachmentPickerResult.files(
    this.files, {
    this.asDocument = false,
    this.sendImmediately = false,
  }) : action = null;
}

class AttachmentPickerBottomSheet extends StatefulWidget {
  final bool allowPoll;

  const AttachmentPickerBottomSheet({
    Key? key,
    this.allowPoll = true,
  }) : super(key: key);

  static Future<AttachmentPickerResult?> show(
    BuildContext context, {
    bool allowPoll = true,
  }) {
    return showModalBottomSheet<AttachmentPickerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => AttachmentPickerBottomSheet(
        allowPoll: allowPoll,
      ),
    );
  }

  @override
  State<AttachmentPickerBottomSheet> createState() =>
      _AttachmentPickerBottomSheetState();
}

class _AttachmentPickerBottomSheetState extends State<AttachmentPickerBottomSheet> {
  static const int _pageSize = 60;

  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _selectedAlbum;
  int _totalAssetsCount = 0;

  // Virtualized page cache for smooth, lag-free scrolling
  final Map<int, List<AssetEntity>> _pageCache = {};
  final Set<int> _loadingPages = {};
  final List<AssetEntity> _selectedAssets = [];

  bool _isLoadingAssets = true;
  bool _hasPermission = false;
  bool _sendAsDocument = false;
  bool _isConverting = false;

  // Live camera preview
  CameraController? _cameraController;
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    _loadAlbumsAndAssets();
    _initLiveCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initLiveCamera() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS)) return;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty || !mounted) return;
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        backCamera,
        ResolutionPreset.low,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _isCameraInitialized = true;
      });
    } catch (e) {
      debugPrint('Live camera preview init note: $e');
    }
  }

  Future<void> _loadAlbumsAndAssets() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS)) {
      if (mounted) {
        setState(() {
          _isLoadingAssets = false;
          _hasPermission = false;
        });
      }
      return;
    }

    try {
      final PermissionState state = await PhotoManager.requestPermissionExtend();
      if (!mounted) return;

      if (state.hasAccess) {
        // Order from newest to oldest
        final filterOption = FilterOptionGroup(
          orders: [
            const OrderOption(
              type: OrderOptionType.createDate,
              asc: false, // Newest first!
            ),
          ],
        );

        final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
          type: RequestType.common,
          filterOption: filterOption,
        );

        if (paths.isNotEmpty && mounted) {
          _albums = paths;
          _selectedAlbum = paths.first;
          _hasPermission = true;
          await _selectAlbum(_selectedAlbum!);
          return;
        }
      }
    } catch (e) {
      debugPrint('Error loading albums: $e');
    }

    if (mounted) {
      setState(() {
        _hasPermission = false;
        _isLoadingAssets = false;
      });
    }
  }

  Future<void> _selectAlbum(AssetPathEntity album) async {
    _pageCache.clear();
    _loadingPages.clear();
    setState(() {
      _selectedAlbum = album;
      _isLoadingAssets = true;
    });

    try {
      final count = await album.assetCountAsync;
      if (!mounted) return;
      setState(() {
        _totalAssetsCount = count;
      });
      await _fetchPage(0);
    } catch (e) {
      debugPrint('Error selecting album: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAssets = false;
        });
      }
    }
  }

  Future<void> _fetchPage(int pageIndex) async {
    if (_loadingPages.contains(pageIndex) || _selectedAlbum == null) return;
    _loadingPages.add(pageIndex);

    try {
      final start = pageIndex * _pageSize;
      final end = math.min(start + _pageSize, _totalAssetsCount);
      if (start >= end) {
        _loadingPages.remove(pageIndex);
        return;
      }

      final list = await _selectedAlbum!.getAssetListRange(start: start, end: end);
      if (!mounted) return;

      setState(() {
        _pageCache[pageIndex] = list;
        _loadingPages.remove(pageIndex);
      });
    } catch (e) {
      debugPrint('Error fetching page $pageIndex: $e');
      _loadingPages.remove(pageIndex);
    }
  }

  String _formatMonthYear(DateTime dt, String locale) {
    final isRu = locale.startsWith('ru');
    const monthsRu = [
      'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
    ];
    const monthsEn = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final monthName = isRu ? monthsRu[dt.month - 1] : monthsEn[dt.month - 1];
    return '$monthName ${dt.year}';
  }

  String _getDateForOffset(double offsetY, ScrollController controller) {
    if (_totalAssetsCount == 0) return '';
    final locale = Localizations.localeOf(context).languageCode;

    // Approximate row calculation
    final screenWidth = MediaQuery.of(context).size.width;
    final rowWidth = (screenWidth - 8 - 6) / 3;
    final rowHeight = rowWidth + 3;

    final row = (offsetY / rowHeight).floor();
    final targetIndex = (row * 3).clamp(0, math.max(0, _totalAssetsCount - 1)).toInt();
    final pageIndex = targetIndex ~/ _pageSize;
    final indexInPage = targetIndex % _pageSize;

    if (_pageCache.containsKey(pageIndex)) {
      final page = _pageCache[pageIndex]!;
      if (indexInPage < page.length) {
        return _formatMonthYear(page[indexInPage].createDateTime, locale);
      }
    }

    // Fallback to nearest cached page
    for (int offset = 0; offset <= 5; offset++) {
      for (final candidate in [pageIndex - offset, pageIndex + offset]) {
        if (_pageCache.containsKey(candidate) && _pageCache[candidate]!.isNotEmpty) {
          return _formatMonthYear(_pageCache[candidate]!.first.createDateTime, locale);
        }
      }
    }

    return _formatMonthYear(DateTime.now(), locale);
  }

  void _showAlbumSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.65,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E24) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
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
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Text(
                      context.l10n.translate('chat_all_photos'),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: isDark ? Colors.white10 : Colors.black12,
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _albums.length,
                  itemBuilder: (context, index) {
                    final album = _albums[index];
                    final isSelected = album.id == _selectedAlbum?.id;
                    return ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2C2C34) : const Color(0xFFF0F2F5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: FutureBuilder<List<AssetEntity>>(
                          future: album.getAssetListRange(start: 0, end: 1),
                          builder: (context, snapshot) {
                            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: AssetEntityImage(
                                  snapshot.data!.first,
                                  isOriginal: false,
                                  thumbnailSize: const ThumbnailSize.square(120),
                                  fit: BoxFit.cover,
                                ),
                              );
                            }
                            return Icon(
                              Icons.folder_outlined,
                              color: isDark ? Colors.white70 : Colors.black54,
                            );
                          },
                        ),
                      ),
                      title: Text(
                        album.isAll ? context.l10n.translate('chat_recent_photos') : album.name,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected
                              ? const Color(0xFF2AABEE)
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                      subtitle: FutureBuilder<int>(
                        future: album.assetCountAsync,
                        builder: (context, snapshot) {
                          return Text(
                            snapshot.hasData ? '${snapshot.data}' : '...',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          );
                        },
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: Color(0xFF2AABEE))
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        if (album.id != _selectedAlbum?.id) {
                          _selectAlbum(album);
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _toggleSelection(AssetEntity asset) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedAssets.contains(asset)) {
        _selectedAssets.remove(asset);
      } else {
        // Unlimited selection: user can select more than 10 items
        _selectedAssets.add(asset);
      }
    });
  }

  Future<void> _onAssetTap(AssetEntity asset) async {
    if (_selectedAssets.isNotEmpty) {
      _toggleSelection(asset);
      return;
    }

    // Single item tapped without selection: open in media editor/preview
    setState(() => _isConverting = true);
    try {
      File? file = await asset.file;
      if (file == null) {
        try {
          file = await asset.originFile;
        } catch (_) {}
      }
      if (file != null && mounted) {
        Navigator.pop(
          context,
          AttachmentPickerResult.files(
            [file],
            asDocument: false,
            sendImmediately: false,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error loading asset file: $e');
    } finally {
      if (mounted) {
        setState(() => _isConverting = false);
      }
    }
  }

  Future<void> _sendSelected() async {
    if (_selectedAssets.isEmpty || _isConverting) return;
    setState(() => _isConverting = true);

    try {
      final List<File> files = [];
      for (final asset in _selectedAssets) {
        File? file = await asset.file;
        if (file == null) {
          try {
            file = await asset.originFile;
          } catch (_) {}
        }
        if (file != null) {
          files.add(file);
        }
      }

      if (mounted && files.isNotEmpty) {
        Navigator.pop(
          context,
          AttachmentPickerResult.files(
            files,
            asDocument: _sendAsDocument,
            sendImmediately: true,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error preparing files for send: $e');
    } finally {
      if (mounted) {
        setState(() => _isConverting = false);
      }
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final glassProvider = context.watch<LiquidGlassProvider>();
    final isGlassEnabled = glassProvider.enabled;
    final effectiveBlur = isGlassEnabled ? (glassProvider.blur * 2.0).clamp(8.0, 30.0) : 24.0;

    final backgroundColor = isDark
        ? const Color(0xFF1E1E24).withValues(alpha: isGlassEnabled ? 0.85 : 0.96)
        : Colors.white.withValues(alpha: isGlassEnabled ? 0.88 : 0.97);

    return DraggableScrollableSheet(
      initialChildSize: 0.58,
      minChildSize: 0.35,
      maxChildSize: 0.94,
      snap: true,
      snapSizes: const [0.58, 0.94],
      builder: (context, scrollController) {
        final albumTitle = _selectedAlbum != null
            ? (_selectedAlbum!.isAll
                ? context.l10n.translate('chat_recent_photos')
                : _selectedAlbum!.name)
            : context.l10n.translate('chat_recent_photos');

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: effectiveBlur, sigmaY: effectiveBlur),
            child: Container(
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                  width: 0.8,
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    // Drag Handle Pill
                    Center(
                      child: Container(
                        width: 38,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white30 : Colors.black26,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Top Section Bar: Folder/Album Selector + "Галерея" shortcut
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Album / Folder dropdown selector
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _albums.length > 1 ? _showAlbumSelector : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    albumTitle,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: theme.textTheme.titleMedium?.color,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  if (_albums.length > 1) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 18,
                                      color: theme.textTheme.titleMedium?.color?.withValues(alpha: 0.7),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),

                          // Quick Gallery Button
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(
                                context,
                                const AttachmentPickerResult.action(
                                  AttachmentPickerAction.gallery,
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    context.l10n.translate('chat_gallery'),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF2AABEE),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                    color: Color(0xFF2AABEE),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Media Grid Section with DraggableScrollbar
                    Expanded(
                      child: _buildMediaGrid(scrollController, isDark, theme),
                    ),

                    // Floating Oval Dock (Action Buttons or Send Bar)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: _selectedAssets.isNotEmpty
                          ? _buildSendBar(isDark, theme)
                          : _buildActionsRow(isDark, theme),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMediaGrid(
    ScrollController scrollController,
    bool isDark,
    ThemeData theme,
  ) {
    if (_isLoadingAssets) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }

    // If no permission or no media available
    if (!_hasPermission || (_totalAssetsCount == 0 && _selectedAlbum == null)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                ),
                child: Icon(
                  Icons.photo_library_outlined,
                  size: 32,
                  color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.translate('chat_allow_gallery_access'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF2AABEE),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: () => PhotoManager.openSetting(),
                child: Text(
                  context.l10n.translate('settings'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Stable, fixed itemCount: 1 camera tile + all photos in the album!
    final totalCount = 1 + _totalAssetsCount;

    return DraggableScrollbar.rrect(
      controller: scrollController,
      alwaysVisibleScrollThumb: true,
      heightScrollThumb: 44.0,
      backgroundColor: isDark ? const Color(0xFF32323C) : Colors.black45,
      labelTextBuilder: (double offsetY) {
        return Text(
          _getDateForOffset(offsetY, scrollController),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        );
      },
      labelConstraints: const BoxConstraints.tightFor(width: 120.0, height: 28.0),
      child: GridView.builder(
        controller: scrollController,
        cacheExtent: 600,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 3,
          crossAxisSpacing: 3,
          childAspectRatio: 1.0,
        ),
        itemCount: totalCount,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildCameraTile(isDark);
          }

          final assetIndex = index - 1;
          final pageIndex = assetIndex ~/ _pageSize;
          final indexInPage = assetIndex % _pageSize;

          final page = _pageCache[pageIndex];
          if (page != null && indexInPage < page.length) {
            final asset = page[indexInPage];
            final isSelected = _selectedAssets.contains(asset);
            final selectionIndex = _selectedAssets.indexOf(asset) + 1;
            return _buildAssetTile(asset, isSelected, selectionIndex, isDark);
          }

          // Trigger dynamic background fetch for this page if not yet loaded
          if (!_loadingPages.contains(pageIndex)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _fetchPage(pageIndex);
            });
          }

          return _buildPlaceholderTile(isDark);
        },
      ),
    );
  }

  Widget _buildPlaceholderTile(bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        color: isDark ? const Color(0xFF22222A) : const Color(0xFFE4E6EA),
      ),
    );
  }

  Widget _buildCameraTile(bool isDark) {
    return RepaintBoundary(
      child: Material(
        color: isDark ? const Color(0xFF272730) : const Color(0xFFE8EAEE),
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.pop(
              context,
              const AttachmentPickerResult.action(AttachmentPickerAction.camera),
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Live Camera Preview if initialized
              if (_isCameraInitialized &&
                  _cameraController != null &&
                  _cameraController!.value.isInitialized)
                ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _cameraController!.value.previewSize?.height ?? 100,
                        height: _cameraController!.value.previewSize?.width ?? 100,
                        child: CameraPreview(_cameraController!),
                      ),
                    ),
                  ),
                ),

              // Translucent overlay for readable icon/label
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.20),
                      Colors.black.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),

              // Monotone Camera Icon & Label
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.35),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.6),
                          width: 1.5,
                        ),
                      ),
                      child: const Center(
                        child: iconoir.Camera(
                          color: Colors.white,
                          width: 22,
                          height: 22,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      context.l10n.translate('chat_camera'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black87,
                            blurRadius: 4,
                          ),
                        ],
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

  Widget _buildAssetTile(
    AssetEntity asset,
    bool isSelected,
    int selectionIndex,
    bool isDark,
  ) {
    final isVideo = asset.type == AssetType.video;

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail Image
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _onAssetTap(asset),
            child: Stack(
              fit: StackFit.expand,
              children: [
                AssetEntityImage(
                  asset,
                  isOriginal: false,
                  thumbnailSize: const ThumbnailSize.square(200),
                  thumbnailFormat: ThumbnailFormat.jpeg,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: isDark ? Colors.black26 : Colors.black12,
                    child: const Icon(Icons.broken_image, size: 24, color: Colors.grey),
                  ),
                ),

                // Selected tint overlay & border
                if (isSelected)
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2AABEE).withValues(alpha: 0.22),
                      border: Border.all(
                        color: const Color(0xFF2AABEE),
                        width: 2.5,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),

                // Video duration chip
                if (isVideo)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.play_arrow_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            _formatDuration(asset.duration),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Selection Badge (Top-right corner hitbox)
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _toggleSelection(asset),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? const Color(0xFF2AABEE)
                        : Colors.black.withValues(alpha: 0.35),
                    border: Border.all(
                      color: Colors.white,
                      width: 1.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Center(
                    child: isSelected
                        ? Text(
                            '$selectionIndex',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsRow(bool isDark, ThemeData theme) {
    final iconColor = isDark ? Colors.white : Colors.black87;

    final items = [
      _PickerItem(
        action: AttachmentPickerAction.gallery,
        label: context.l10n.translate('chat_gallery'),
        fallbackLabel: 'Gallery',
        icon: iconoir.MediaImage(color: iconColor, width: 22, height: 22),
      ),
      _PickerItem(
        action: AttachmentPickerAction.file,
        label: context.l10n.translate('chat_file'),
        fallbackLabel: 'File',
        icon: iconoir.Page(color: iconColor, width: 22, height: 22),
      ),
      _PickerItem(
        action: AttachmentPickerAction.location,
        label: context.l10n.translate('chat_location'),
        fallbackLabel: 'Location',
        icon: iconoir.MapPin(color: iconColor, width: 22, height: 22),
      ),
      _PickerItem(
        action: AttachmentPickerAction.contact,
        label: context.l10n.translate('chat_contact'),
        fallbackLabel: 'Contact',
        icon: iconoir.User(color: iconColor, width: 22, height: 22),
      ),
      _PickerItem(
        action: AttachmentPickerAction.music,
        label: context.l10n.translate('chat_music'),
        fallbackLabel: 'Music',
        icon: iconoir.MusicDoubleNote(color: iconColor, width: 22, height: 22),
      ),
      if (widget.allowPoll)
        _PickerItem(
          action: AttachmentPickerAction.poll,
          label: context.l10n.translate('chat_poll'),
          fallbackLabel: 'Poll',
          icon: iconoir.StatsUpSquare(color: iconColor, width: 22, height: 22),
        ),
    ];

    return _wrapWithGlassDock(
      context,
      isDark: isDark,
      key: const ValueKey('actions_dock'),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: items.map((item) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _AnimatedPickerButton(
                item: item,
                onTap: () => Navigator.pop(
                  context,
                  AttachmentPickerResult.action(item.action),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSendBar(bool isDark, ThemeData theme) {
    final count = _selectedAssets.length;

    return _wrapWithGlassDock(
      context,
      isDark: isDark,
      key: const ValueKey('send_dock'),
      child: Row(
              children: [
                // "Без сжатия" toggle
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _sendAsDocument = !_sendAsDocument);
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: _sendAsDocument
                              ? const Color(0xFF2AABEE)
                              : Colors.transparent,
                          border: Border.all(
                            color: _sendAsDocument
                                ? const Color(0xFF2AABEE)
                                : (isDark ? Colors.white38 : Colors.black38),
                            width: 1.8,
                          ),
                        ),
                        child: _sendAsDocument
                            ? const Icon(Icons.check, size: 16, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.translate('chat_send_without_compression'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Selected count badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2AABEE).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Color(0xFF2AABEE),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Send Button (flat solid Telegram blue)
                GestureDetector(
                  onTap: _isConverting ? null : _sendSelected,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF2AABEE),
                    ),
                    child: Center(
                      child: _isConverting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const iconoir.Send(
                              color: Colors.white,
                              width: 20,
                              height: 20,
                            ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _wrapWithGlassDock(
    BuildContext context, {
    required Widget child,
    required bool isDark,
    required Key key,
  }) {
    final glassProvider = context.watch<LiquidGlassProvider>();
    final isGlassEnabled = glassProvider.enabled;

    if (!isGlassEnabled) {
      return Padding(
        padding: const EdgeInsets.only(left: 12, right: 12, bottom: 10, top: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              key: key,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF24242C).withValues(alpha: 0.92)
                    : Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
      );
    }

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final lightAngle = glassProvider.getEffectiveLightAngle(reduceMotion: reduceMotion);

    final shape = LiquidGlassShape.continuousRoundedRectangle(
      cornerRadius: 36,
      clipQuality: LiquidGlassClipQuality.exact,
      borderWidth: 0.7,
      lightIntensity: isDark ? 0.7 : 0.95,
      lightDirection: lightAngle,
      borderType: const OpticalBorder(
        borderSaturation: 1.1,
        ambientIntensity: 0.85,
        borderSolidity: 0.95,
      ),
    );

    final style = LiquidGlassStyle(
      shape: shape,
      appearance: LiquidGlassAppearance(
        color: isDark
            ? const Color(0x3D24242C)
            : const Color(0x9EFFFFFF),
        blur: glassProvider.blurEffect,
        shadow: LiquidGlassShadow(
          blur: 16,
          opacity: isDark ? 0.35 : 0.12,
          offset: const Offset(0, 4),
          color: Colors.black,
        ),
      ),
      refraction: const LiquidGlassRefraction(
        distortion: 0.06,
        distortionWidth: 26,
      ),
      liteGlass: glassProvider.isLite ? LiquidGlassLitePickup.backdrop : null,
    );

    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 10, top: 4),
      child: LiquidGlassLens(
        key: key,
        style: style,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: child,
        ),
      ),
    );
  }
}

class _AnimatedPickerButton extends StatefulWidget {
  final _PickerItem item;
  final VoidCallback onTap;

  const _AnimatedPickerButton({
    Key? key,
    required this.item,
    required this.onTap,
  }) : super(key: key);

  @override
  State<_AnimatedPickerButton> createState() => _AnimatedPickerButtonState();
}

class _AnimatedPickerButtonState extends State<_AnimatedPickerButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final item = widget.item;
    final displayLabel = item.label.isNotEmpty && item.label != item.action.name
        ? item.label
        : item.fallbackLabel;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        setState(() => _isPressed = true);
        HapticFeedback.lightImpact();
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
      },
      child: AnimatedScale(
        scale: _isPressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutBack,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? const Color(0xFF32323C)
                    : const Color(0xFFEBEDF2),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05),
                  width: 1.0,
                ),
              ),
              child: Center(child: item.icon),
            ),
            const SizedBox(height: 5),
            Text(
              displayLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.1,
                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.9),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerItem {
  final AttachmentPickerAction action;
  final String label;
  final String fallbackLabel;
  final Widget icon;

  const _PickerItem({
    required this.action,
    required this.label,
    required this.fallbackLabel,
    required this.icon,
  });
}
