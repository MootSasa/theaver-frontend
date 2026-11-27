import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/avatar_editor_models.dart';
import '../../services/glass_toast_service.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../design_system/theav_design_system.dart';
import 'avatar_emoji_constructor_view.dart';
import 'theav_avatar_editor_screen.dart';

/// Full-screen opaque Avatar Picker window offering device Gallery / File Picker
/// and the Emoji / Sticker / Monogram Constructor, seamlessly handing off to
/// [TheavAvatarEditorScreen].
class TheavAvatarPickerSheet extends StatefulWidget {
  final AvatarShapeMask maskShape;
  final AvatarEditorCtaMode ctaMode;
  final String? subjectName;
  final bool canDeleteCurrent;
  final bool startInConstructor;

  const TheavAvatarPickerSheet({
    super.key,
    this.maskShape = AvatarShapeMask.circle,
    this.ctaMode = AvatarEditorCtaMode.done,
    this.subjectName,
    this.canDeleteCurrent = false,
    this.startInConstructor = false,
  });

  /// Alias for [pickAndEdit]. Opens the dedicated full-screen Avatar Picker route.
  static Future<AvatarPickResult?> open({
    required BuildContext context,
    AvatarShapeMask maskShape = AvatarShapeMask.circle,
    AvatarEditorCtaMode ctaMode = AvatarEditorCtaMode.done,
    String? subjectName,
    bool canDeleteCurrent = false,
    bool startInConstructor = false,
  }) {
    return pickAndEdit(
      context: context,
      maskShape: maskShape,
      ctaMode: ctaMode,
      subjectName: subjectName,
      canDeleteCurrent: canDeleteCurrent,
      startInConstructor: startInConstructor,
    );
  }

  /// Opens the dedicated full-screen Avatar Picker route and resolves with an
  /// [AvatarPickResult] (media bytes/file or [AvatarPickResult.deletedCurrent]),
  /// or `null` on cancel.
  static Future<AvatarPickResult?> pickAndEdit({
    required BuildContext context,
    AvatarShapeMask maskShape = AvatarShapeMask.circle,
    AvatarEditorCtaMode ctaMode = AvatarEditorCtaMode.done,
    String? subjectName,
    bool canDeleteCurrent = false,
    bool startInConstructor = false,
  }) {
    final NavigatorState navigator = Navigator.of(context);
    final CapturedThemes capturedThemes = InheritedTheme.capture(
      from: context,
      to: navigator.context,
    );
    return navigator.push<AvatarPickResult>(
      SwipeBackPageRoute<AvatarPickResult>(
        builder: (BuildContext _) => capturedThemes.wrap(
          TheavMatteScope(
            child: TheavAvatarPickerSheet(
              maskShape: maskShape,
              ctaMode: ctaMode,
              subjectName: subjectName,
              canDeleteCurrent: canDeleteCurrent,
              startInConstructor: startInConstructor,
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<TheavAvatarPickerSheet> createState() => _TheavAvatarPickerSheetState();
}

class _TheavAvatarPickerSheetState extends State<TheavAvatarPickerSheet> {
  static const int _pageSize = 60;
  final ImagePicker _imagePicker = ImagePicker();

  late int _activeTab;
  bool _isBusy = false;

  // Mobile PhotoManager gallery state
  bool _isLoadingAlbums = false;
  bool _hasPermission = false;
  List<AssetPathEntity> _albums = <AssetPathEntity>[];
  AssetPathEntity? _selectedAlbum;
  int _totalAssetsCount = 0;
  final Map<int, List<AssetEntity>> _pageCache = <int, List<AssetEntity>>{};
  final Set<int> _loadingPages = <int>{};
  final Set<int> _scheduledPageRequests = <int>{};
  BuildContext? _matteContext;

  bool get _isMobileGallery =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _activeTab = widget.startInConstructor ? 1 : 0;
    if (_isMobileGallery) {
      _initMobileGallery();
    }
  }

  Future<void> _initMobileGallery() async {
    setState(() => _isLoadingAlbums = true);
    try {
      final PermissionState perm = await PhotoManager.requestPermissionExtend();
      if (!mounted) return;
      if (perm.hasAccess) {
        final FilterOptionGroup filterOption = FilterOptionGroup(
          orders: const <OrderOption>[
            OrderOption(
              type: OrderOptionType.createDate,
              asc: false,
            ),
          ],
        );
        final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
          type: RequestType.image,
          filterOption: filterOption,
        );
        if (!mounted) return;
        if (paths.isNotEmpty) {
          _albums = paths;
          _hasPermission = true;
          await _selectAlbum(paths.first);
          return;
        }
        setState(() {
          _hasPermission = true;
          _isLoadingAlbums = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('[TheavAvatarPickerSheet] Gallery init failed: $e');
    }
    if (mounted) {
      setState(() {
        _hasPermission = false;
        _isLoadingAlbums = false;
      });
    }
  }

  Future<void> _selectAlbum(AssetPathEntity album) async {
    _pageCache.clear();
    _loadingPages.clear();
    _scheduledPageRequests.clear();
    setState(() {
      _selectedAlbum = album;
      _isLoadingAlbums = true;
    });
    try {
      final int count = await album.assetCountAsync;
      if (!mounted) return;
      setState(() => _totalAssetsCount = count);
      await _fetchPage(0);
    } catch (e) {
      debugPrint('[TheavAvatarPickerSheet] Album load failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingAlbums = false);
      }
    }
  }

  void _requestPageIfNeeded(int pageIndex) {
    if (_pageCache.containsKey(pageIndex) ||
        _loadingPages.contains(pageIndex) ||
        !_scheduledPageRequests.add(pageIndex)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduledPageRequests.remove(pageIndex);
      if (mounted) {
        _fetchPage(pageIndex);
      }
    });
  }

  Future<void> _fetchPage(int pageIndex) async {
    if (_loadingPages.contains(pageIndex) ||
        _pageCache.containsKey(pageIndex) ||
        _selectedAlbum == null) {
      return;
    }
    _loadingPages.add(pageIndex);
    try {
      final int start = pageIndex * _pageSize;
      final int end = math.min(start + _pageSize, _totalAssetsCount);
      if (start >= end) {
        _loadingPages.remove(pageIndex);
        return;
      }
      final List<AssetEntity> list =
          await _selectedAlbum!.getAssetListRange(start: start, end: end);
      if (!mounted) return;
      setState(() {
        _pageCache[pageIndex] = list;
        _loadingPages.remove(pageIndex);
      });
    } catch (_) {
      _loadingPages.remove(pageIndex);
    }
  }

  Future<void> _openEditorWithSource({
    Uint8List? bytes,
    String? filePath,
    required String fileName,
  }) async {
    if (!mounted) return;
    final AvatarPickResult? edited = await TheavAvatarEditorScreen.open(
      context: context,
      initialBytes: bytes,
      initialFilePath: filePath,
      fileName: fileName,
      maskShape: widget.maskShape,
      ctaMode: widget.ctaMode,
      subjectName: widget.subjectName,
    );
    if (edited != null && mounted) {
      Navigator.of(context).pop(edited);
    }
  }

  Future<void> _onTapAsset(AssetEntity asset) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      File? file = await asset.file;
      if (file == null) {
        try {
          file = await asset.originFile;
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() => _isBusy = false);
      if (file != null) {
        final String diskName = file.uri.pathSegments.isNotEmpty
            ? file.uri.pathSegments.last
            : '';
        final String name =
            diskName.contains('.') ? diskName : (asset.title?.trim() ?? 'avatar.jpg');
        await _openEditorWithSource(filePath: file.path, fileName: name);
      }
    } catch (_) {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _pickFromCamera() async {
    if (_isBusy) return;
    HapticUtils.tap();
    setState(() => _isBusy = true);
    try {
      final XFile? shot =
          await _imagePicker.pickImage(source: ImageSource.camera);
      if (!mounted) return;
      setState(() => _isBusy = false);
      if (shot == null) return;
      final Uint8List? bytes = kIsWeb ? await shot.readAsBytes() : null;
      if (!mounted) return;
      await _openEditorWithSource(
        bytes: bytes,
        filePath: kIsWeb ? null : shot.path,
        fileName: shot.name,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      GlassToastService().showError(
        context,
        context.trOr(
          'avatar_picker_camera_unavailable',
          'Камера недоступна на этом устройстве',
        ),
      );
    }
  }

  Future<void> _pickFromFileSystem() async {
    if (_isBusy) return;
    HapticUtils.tap();
    setState(() => _isBusy = true);
    try {
      final FilePickerResult? picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['jpg', 'jpeg', 'png', 'webp', 'gif'],
        withData: kIsWeb,
      );
      if (!mounted) return;
      setState(() => _isBusy = false);
      if (picked == null || picked.files.isEmpty) return;

      final PlatformFile pf = picked.files.first;
      Uint8List? bytes = pf.bytes;
      String? path = kIsWeb ? null : pf.path;
      if (bytes == null && (path == null || path.isEmpty)) return;

      await _openEditorWithSource(
        bytes: bytes,
        filePath: path,
        fileName: pf.name,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      GlassToastService().showError(
        context,
        context.trOr('avatar_picker_file_error', 'Не удалось выбрать файл'),
      );
    }
  }

  Future<void> _confirmDeleteCurrent() async {
    if (_isBusy) return;
    HapticUtils.heavy();
    final BuildContext dialogCtx =
        (_matteContext != null && _matteContext!.mounted)
            ? _matteContext!
            : context;
    final bool? confirmed = await showTheavDialog<bool>(
      context: dialogCtx,
      title: context.trOr(
        'avatar_picker_delete_confirm_title',
        'Удалить фото?',
      ),
      message: context.trOr(
        'avatar_picker_delete_confirm_message',
        'Текущее фото будет удалено.',
      ),
      actions: [
        TheavDialogAction<bool>(
          label: context.trOr('profile_cancel', 'Отмена'),
          result: false,
        ),
        TheavDialogAction<bool>(
          label: context.trOr('avatar_picker_delete_photo', 'Удалить фото'),
          result: true,
          isDestructive: true,
        ),
      ],
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(
        AvatarPickResult.deleted(maskShape: widget.maskShape),
      );
    }
  }

  void _showAlbumSelector() {
    if (_albums.length <= 1) return;
    final BuildContext sheetHostCtx =
        (_matteContext != null && _matteContext!.mounted)
            ? _matteContext!
            : context;
    showTheavModalSheet<void>(
      context: sheetHostCtx,
      title: context.trOr('avatar_picker_all_photos', 'Все фото'),
      showCloseButton: true,
      maxHeightFactor: 0.72,
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 20),
      builder: (BuildContext ctx) {
        final palette = ctx.theav;
        return ListView.builder(
          shrinkWrap: true,
          itemCount: _albums.length,
          itemBuilder: (_, int index) {
            final AssetPathEntity album = _albums[index];
            final bool isSelected = album.id == _selectedAlbum?.id;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              child: TheavInsetGroup(
                margin: EdgeInsets.zero,
                showDividers: false,
                children: [
                  TheavListRow(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: palette.onSurface.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: FutureBuilder<List<AssetEntity>>(
                        future: album.getAssetListRange(start: 0, end: 1),
                        builder: (_, AsyncSnapshot<List<AssetEntity>> snap) {
                          if (snap.hasData && snap.data!.isNotEmpty) {
                            return AssetEntityImage(
                              snap.data!.first,
                              isOriginal: false,
                              thumbnailSize: const ThumbnailSize.square(120),
                              fit: BoxFit.cover,
                            );
                          }
                          return Center(
                            child: iconoir.Folder(
                              width: 20,
                              height: 20,
                              color: palette.subtext,
                            ),
                          );
                        },
                      ),
                    ),
                    title: album.isAll
                        ? context.trOr('avatar_picker_all_photos', 'Все фото')
                        : album.name,
                    subtitleWidget: FutureBuilder<int>(
                      future: album.assetCountAsync,
                      builder: (_, AsyncSnapshot<int> snap) {
                        return Text(
                          snap.hasData ? '${snap.data}' : '...',
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.subtext,
                          ),
                        );
                      },
                    ),
                    trailing: TheavCheckCircle(
                      selected: isSelected,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        if (!isSelected) _selectAlbum(album);
                      },
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      if (!isSelected) _selectAlbum(album);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;

    return TheavMatteScope(
      child: Builder(
        builder: (BuildContext matteCtx) {
          _matteContext = matteCtx;
          return Scaffold(
            backgroundColor: palette.bgBase,
            body: SafeArea(
              bottom: false,
              child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  children: [
                    _PickerMatteCircleButton(
                      key: const ValueKey<String>('avatar_picker_close_btn'),
                      size: 38,
                      tooltip:
                          MaterialLocalizations.of(context).backButtonTooltip,
                      icon: iconoir.NavArrowLeft(
                        width: 20,
                        height: 20,
                        color: palette.onSurface,
                      ),
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TheavSegmentedControl<int>(
                        useGlass: false,
                        height: 36,
                        expand: true,
                        selected: _activeTab,
                        onChanged: (int v) => setState(() => _activeTab = v),
                        options: [
                          TheavSegmentOption(
                            value: 0,
                            label: context.trOr(
                              'avatar_picker_gallery',
                              'Галерея',
                            ),
                          ),
                          TheavSegmentOption(
                            value: 1,
                            label: context.trOr(
                              'avatar_picker_constructor',
                              'Конструктор',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (widget.canDeleteCurrent)
                      _PickerMatteCircleButton(
                        key: const ValueKey<String>('avatar_picker_delete_btn'),
                        size: 38,
                        tooltip: context.trOr(
                          'avatar_picker_delete_photo',
                          'Удалить фото',
                        ),
                        icon: iconoir.Trash(
                          width: 18,
                          height: 18,
                          color: palette.error,
                        ),
                        onTap: _confirmDeleteCurrent,
                      )
                    else
                      const SizedBox(width: 38),
                  ],
                ),
              ),
              Expanded(
                child: _activeTab == 0
                    ? (_isMobileGallery
                        ? _buildMobileGalleryTab(context, palette)
                        : _buildDesktopPickerTab(context, palette))
                    : AvatarEmojiConstructorView(
                        maskShape: widget.maskShape,
                        ctaMode: widget.ctaMode,
                        subjectName: widget.subjectName,
                        onCompleted: (AvatarPickResult res) {
                          if (mounted) Navigator.of(context).pop(res);
                        },
                      ),
              ),
            ],
          ),
        ),
          );
        },
      ),
    );
  }

  Widget _buildMobileGalleryTab(BuildContext context, TheavPalette palette) {
    final String albumTitle = _selectedAlbum != null
        ? (_selectedAlbum!.isAll
            ? context.trOr('avatar_picker_all_photos', 'Все фото')
            : _selectedAlbum!.name)
        : context.trOr('avatar_picker_all_photos', 'Все фото');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: LayoutBuilder(
            builder: (BuildContext ctx, BoxConstraints box) {
              return Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _albums.length > 1 ? _showAlbumSelector : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: palette.onSurface.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  albumTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: palette.onSurface,
                                  ),
                                ),
                              ),
                              if (_albums.length > 1) ...[
                                const SizedBox(width: 4),
                                iconoir.NavArrowDown(
                                  width: 16,
                                  height: 16,
                                  color: palette.subtext,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.max(96.0, box.maxWidth * 0.48),
                    ),
                    child: TextButton(
                      onPressed: _isBusy ? null : _pickFromFileSystem,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          iconoir.Folder(
                            width: 16,
                            height: 16,
                            color: palette.primary,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              context.trOr(
                                'avatar_picker_choose_file',
                                'Выбрать файл',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: palette.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Expanded(
          child: _isLoadingAlbums && _totalAssetsCount == 0
              ? Center(
                  child: CircularProgressIndicator(color: palette.primary),
                )
              : (!_hasPermission
                  ? _buildPermissionDeniedView(context, palette)
                  : GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        4,
                        0,
                        4,
                        MediaQuery.paddingOf(context).bottom + 12,
                      ),
                      scrollCacheExtent: const ScrollCacheExtent.pixels(540),
                      addAutomaticKeepAlives: false,
                      physics: const BouncingScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 3,
                        crossAxisSpacing: 3,
                      ),
                      itemCount: _totalAssetsCount + 1,
                      itemBuilder: (BuildContext ctx, int index) {
                        if (index == 0) {
                          return _buildMobileCameraTile(context, palette);
                        }
                        final int assetIdx = index - 1;
                        final int pageIdx = assetIdx ~/ _pageSize;
                        final int itemIdx = assetIdx % _pageSize;
                        final List<AssetEntity>? page = _pageCache[pageIdx];
                        if (page != null && itemIdx < page.length) {
                          if (itemIdx >= (_pageSize * 0.7).floor() &&
                              (pageIdx + 1) * _pageSize < _totalAssetsCount) {
                            _requestPageIfNeeded(pageIdx + 1);
                          }
                          final AssetEntity asset = page[itemIdx];
                          return RepaintBoundary(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _onTapAsset(asset),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: AssetEntityImage(
                                  asset,
                                  isOriginal: false,
                                  thumbnailSize:
                                      const ThumbnailSize.square(240),
                                  filterQuality: FilterQuality.low,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          );
                        }
                        _requestPageIfNeeded(pageIdx);
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            color: palette.onSurface.withValues(alpha: 0.08),
                          ),
                        );
                      },
                    )),
        ),
      ],
    );
  }

  Widget _buildMobileCameraTile(BuildContext context, TheavPalette palette) {
    return Material(
      color: palette.onSurface.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _isBusy ? null : _pickFromCamera,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            iconoir.Camera(
              width: 28,
              height: 28,
              color: palette.primary,
            ),
            const SizedBox(height: 6),
            Text(
              context.trOr('avatar_picker_camera', 'Камера'),
              style: TextStyle(
                color: palette.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionDeniedView(
    BuildContext context,
    TheavPalette palette,
  ) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        TheavInsetGroup(
          header: context.trOr(
            'avatar_picker_permission_title',
            'Нет доступа к галерее',
          ),
          footer: context.trOr(
            'avatar_picker_permission_subtitle',
            'Разрешите доступ к фотографиям или выберите изображение вручную.',
          ),
          children: [
            TheavListRow(
              leading: iconoir.Settings(
                width: 20,
                height: 20,
                color: palette.primary,
              ),
              title: context.trOr(
                'avatar_picker_open_settings',
                'Открыть настройки',
              ),
              showChevron: true,
              onTap: () => PhotoManager.openSetting(),
            ),
            TheavListRow(
              leading: iconoir.Folder(
                width: 20,
                height: 20,
                color: palette.primary,
              ),
              title: context.trOr('avatar_picker_choose_file', 'Выбрать файл'),
              showChevron: true,
              onTap: _pickFromFileSystem,
            ),
            TheavListRow(
              leading: iconoir.Camera(
                width: 20,
                height: 20,
                color: palette.primary,
              ),
              title: context.trOr('avatar_picker_camera', 'Камера'),
              showChevron: true,
              onTap: _pickFromCamera,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDesktopPickerTab(BuildContext context, TheavPalette palette) {
    return ListView(
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      children: [
        TheavInsetGroup(
          children: [
            TheavListRow(
              key: const ValueKey<String>('avatar_picker_choose_device_row'),
              leading: iconoir.MediaImage(
                width: 22,
                height: 22,
                color: palette.primary,
              ),
              title: context.trOr(
                'avatar_picker_choose_device',
                'Выбрать изображение с устройства',
              ),
              showChevron: true,
              onTap: _isBusy ? null : _pickFromFileSystem,
            ),
            TheavListRow(
              key: const ValueKey<String>('avatar_picker_take_photo_row'),
              leading: iconoir.Camera(
                width: 22,
                height: 22,
                color: palette.primary,
              ),
              title: context.trOr('avatar_picker_take_photo', 'Сделать фото'),
              showChevron: true,
              onTap: _isBusy ? null : _pickFromCamera,
            ),
          ],
        ),
        if (widget.canDeleteCurrent)
          TheavInsetGroup(
            children: [
              TheavListRow(
                key: const ValueKey<String>('avatar_picker_delete_row'),
                leading: iconoir.Trash(
                  width: 22,
                  height: 22,
                  color: palette.error,
                ),
                title: context.trOr(
                  'avatar_picker_delete_photo',
                  'Удалить фото',
                ),
                isDestructive: true,
                onTap: _isBusy ? null : _confirmDeleteCurrent,
              ),
            ],
          ),
      ],
    );
  }
}

class _PickerMatteCircleButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;

  const _PickerMatteCircleButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.size = 38.0,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    Widget btn = SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.onSurface.withValues(alpha: 0.08),
          shape: BoxShape.circle,
          border: Border.all(color: palette.divider, width: 0.5),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap == null
                ? null
                : () {
                    HapticUtils.tap();
                    onTap!();
                  },
            child: Center(child: icon),
          ),
        ),
      ),
    );
    if (tooltip != null && tooltip!.isNotEmpty) {
      btn = Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}
