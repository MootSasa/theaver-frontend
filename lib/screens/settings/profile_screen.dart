import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:image_picker/image_picker.dart';
import 'package:inspire_blur/inspire_blur.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';

import '../../services/account_manager.dart';
import '../../services/auth_service.dart';
import '../../services/avatar_sync_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/avatar_crop_utils.dart';
import '../../utils/image_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/profile/expandable_avatar.dart';
import '../../widgets/profile/avatar_gallery_viewer.dart';
import '../../widgets/profile/liquid_glass_profile_buttons.dart';
import '../../widgets/profile/liquid_glass_music_status.dart';
import '../../widgets/profile/liquid_glass_info_panel.dart';
import '../../widgets/profile/profile_segmented_control.dart';
import '../../widgets/profile/qr_code_dialog.dart';
import '../../widgets/notifications/in_app_notification_banner.dart';
import '../../services/profile_theme_provider.dart';
import '../../config/app_config.dart';
import 'edit_profile_screen.dart';
import 'profile_color_screen.dart';

/// Экран профиля пользователя с двумя режимами дизайна.
///
/// - **Liquid Glass включён** — премиальный дизайн со стеклянными элементами
/// - **Liquid Glass выключен/недоступен** — премиальный дизайн с полупрозрачными карточками
///
/// Фото сохраняется автоматически при выборе/удалении.
/// Оба режима поддерживают светлую и тёмную тему приложения.
class ProfileScreen extends StatefulWidget {
  final Function()? onUpdate;

  const ProfileScreen({
    Key? key,
    this.onUpdate,
  }) : super(key: key);

  @override
  ProfileScreenState createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TextEditingController _nameController;
  late TextEditingController _surnameController;
  late TextEditingController _usernameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  String? _avatarUrl;
  List<String> _avatarUrls = []; // все аватарки (новейшая первая)
  List<int> _avatarIds = [];     // ID аватарок для удаления
  File? _avatarFile;
  final ImagePicker _imagePicker = ImagePicker();

  bool _isLoading = true;
  bool _isProcessing = false;
  final AccountManager _accountManager = AccountManager();

  /// Выбранная вкладка сегментированного переключателя (0 = Стена, 1 = Подарки)
  int _selectedSegment = 0;

  /// Фактор расширения аватарки: 0.0 = маленькая круглая, 1.0 = большая квадратная
  double _expandFactor = 0.0;

  /// Флаг текущего режима движения (true = сворачивание, false = расширение)
  bool _isCollapsingMode = false;

  /// Яркость верхней части фото аватарки (0.0 = тёмное фото, 1.0 = светлое фото)
  double _topLuminance = 0.5;

  /// Рассчитывает относительную яркость (ITU-R BT.709) верхней 18% области фото аватарки
  Future<void> _updateTopLuminance() async {
    ImageProvider? provider;
    if (_avatarFile != null) {
      provider = FileImage(_avatarFile!);
    } else if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      provider = avatarImageProvider(_avatarUrl);
    } else if (_avatarUrls.isNotEmpty) {
      provider = avatarImageProvider(_avatarUrls.first);
    }

    if (provider == null) {
      if (mounted) {
        setState(() {
          _topLuminance = 0.5;
        });
      }
      return;
    }

    try {
      final ImageStream stream = provider.resolve(const ImageConfiguration());
      final Completer<ui.Image> completer = Completer<ui.Image>();
      late ImageStreamListener listener;
      listener = ImageStreamListener((ImageInfo info, bool _) {
        if (!completer.isCompleted) completer.complete(info.image);
        stream.removeListener(listener);
      }, onError: (dynamic error, _) {
        if (!completer.isCompleted) completer.completeError(error);
        stream.removeListener(listener);
      });
      stream.addListener(listener);

      final ui.Image image = await completer.future;
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return;

      final width = image.width;
      final height = image.height;

      // 1. Считывание верхней 18% области для _topLuminance
      final sampleHeight = (height * 0.18).clamp(1, height).toInt();
      double totalLuminance = 0;
      int countTop = 0;

      for (int y = 0; y < sampleHeight; y += 2) {
        for (int x = 0; x < width; x += 4) {
          final offset = (y * width + x) * 4;
          if (offset + 2 < byteData.lengthInBytes) {
            final r = byteData.getUint8(offset);
            final g = byteData.getUint8(offset + 1);
            final b = byteData.getUint8(offset + 2);
            final lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
            totalLuminance += lum;
            countTop++;
          }
        }
      }

      if (mounted) {
        setState(() {
          if (countTop > 0) {
            _topLuminance = totalLuminance / countTop;
          }
        });
      }
    } catch (_) {
      // Игнорируем ошибки считывания пикселей
    }
  }

  /// Зафиксировано ли раскрытое состояние аватарки
  bool _isExpanded = false;

  /// Контроллер анимации расширения аватарки
  late AnimationController _expandController;

  /// Контроллер прокрутки профиля в свёрнутом (круглом) состоянии аватарки
  late ScrollController _scrollController;

  /// Контроллер страниц аватарок для синхронизации свайпов
  late PageController _avatarPageController;

  /// Текущий выбранный индекс аватарки для сохранения Hero-тегов
  int _currentAvatarIndex = 0;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _surnameController = TextEditingController();
    _usernameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();

    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);

    _avatarPageController = PageController();

    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _expandController.value = 0.0;
    _expandController.addListener(() {
      setState(() {
        _expandFactor = _expandController.value;
      });
    });

    AvatarSyncService().addListener(_onAvatarSyncChanged);
    _loadUserProfile();
  }

  void _onScroll() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onAvatarSyncChanged() async {
    if (!mounted) return;
    final account = _accountManager.currentAccount;
    if (account != null) {
      final localHistory = await AvatarSyncService().getLocalAvatarUrls(account.userId);
      if (!mounted) return;
      setState(() {
        final currentAccAvatar = account.avatarUrl;
        if (currentAccAvatar != null && currentAccAvatar.isNotEmpty) {
          _avatarUrl = currentAccAvatar;
        }
        final combined = <String>[];
        for (final local in localHistory) {
          if (!combined.contains(local)) combined.add(local);
        }
        for (final old in _avatarUrls) {
          if (!combined.contains(old)) combined.add(old);
        }
        _avatarUrls = combined;
      });
      widget.onUpdate?.call();
    }
  }

  Future<void> _loadUserProfile() async {
    final account = _accountManager.currentAccount;

    if (account != null) {
      _nameController.text = account.name ?? '';
      _surnameController.text = account.surname ?? '';
      _usernameController.text = account.username ?? '';
      _emailController.text = account.email ?? '';
      _phoneController.text = account.phone ?? '';

      final localHistory = await AvatarSyncService().getLocalAvatarUrls(account.userId);
      if (localHistory.isNotEmpty) {
        _avatarUrl = localHistory.first;
        _avatarUrls = List.from(localHistory);
      } else if (account.avatarUrl != null && account.avatarUrl!.isNotEmpty) {
        _avatarUrl = account.avatarUrl;
        _avatarUrls = [_avatarUrl!];
      }

      // Теневой вызов очереди фоновой синхронизации
      AvatarSyncService().syncPendingAvatar(account.userId);
    }

    try {
      final result = await AuthService.getCurrentUser();
      debugPrint('[_loadUserProfile] result success=${result['success']}, user=${result['user']}');
      if (result['success'] == true && result['user'] != null && mounted) {
        final user = result['user'] as Map<String, dynamic>;
        debugPrint('[_loadUserProfile] avatar_url=${user['avatar_url']}, avatars=${user['avatars']}');
        
        final localHistory = account != null ? await AvatarSyncService().getLocalAvatarUrls(account.userId) : <String>[];

        setState(() {
          _nameController.text = user['name'] ?? _nameController.text;
          _surnameController.text = user['surname'] ?? _surnameController.text;
          _usernameController.text = user['username'] ?? _usernameController.text;
          _emailController.text = user['email'] ?? _emailController.text;
          _phoneController.text = user['phone'] ?? _phoneController.text;
          
          if (localHistory.isNotEmpty) {
            _avatarUrl = localHistory.first;
          } else {
            _avatarUrl = user['avatar_url'] ?? _avatarUrl;
          }

          // Parse avatars list (newest first)
          if (user['avatars'] != null) {
            final avatarsList = user['avatars'] as List<dynamic>;
            final serverUrls = avatarsList.map((a) => a['avatar_url'].toString()).toList();
            _avatarIds = avatarsList.map((a) => (a['id'] is int ? a['id'] as int : (a['id'] as num).toInt())).toList();
            
            final combined = <String>[];
            for (final l in localHistory) {
              if (!combined.contains(l)) combined.add(l);
            }
            for (final s in serverUrls) {
              if (!combined.contains(s)) combined.add(s);
            }
            _avatarUrls = combined;
            debugPrint('[_loadUserProfile] merged avatarUrls=$_avatarUrls, avatarIds=$_avatarIds');
          } else if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
            final combined = <String>[];
            for (final l in localHistory) {
              if (!combined.contains(l)) combined.add(l);
            }
            if (!combined.contains(_avatarUrl!)) combined.add(_avatarUrl!);
            _avatarUrls = combined;
            _avatarIds = [];
            debugPrint('[_loadUserProfile] fallback: avatarUrls=$_avatarUrls');
          } else {
            debugPrint('[_loadUserProfile] no avatars found');
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading profile from server: $e');
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      _updateTopLuminance();
    }
  }

  @override
  void dispose() {
    AvatarSyncService().removeListener(_onAvatarSyncChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _nameController.dispose();
    _surnameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _avatarPageController.dispose();
    _expandController.dispose();
    super.dispose();
  }

  // ============================================================
  // Анимация расширения аватарки с тяжестью и упругостью в середине
  // ============================================================

  void _animateToExpand(double target, {double velocity = 0.0}) {
    HapticUtils.impact();
    
    // Если сворачиваем к круглой аватарке (target == 0.0), плавно анимацией возвращаемся к первой фотографии
    if (target == 0.0 && _avatarPageController.hasClients) {
      final currentPage = _avatarPageController.page?.round() ?? 0;
      if (currentPage != 0) {
        _avatarPageController.animateToPage(
          0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOutCubic,
        );
      }
    }

    // Если разворачиваем (target == 1.0), делаем пружину гораздо жестче и легче для быстрого выстреливания
    final mass = target == 1.0 ? 0.85 : 1.1;
    final stiffness = target == 1.0 ? 550.0 : 380.0;
    
    final simulation = SpringSimulation(
      SpringDescription.withDampingRatio(
        mass: mass,
        stiffness: stiffness,
        ratio: 0.95,
      ),
      _expandController.value,
      target,
      velocity / 400.0,
    );
    _expandController.animateWith(simulation);
  }



  // ============================================================
  // Выбор фото (авто-сохранение)
  // ============================================================

  Future<void> _pickImage() async {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          title: Text(
            l10n.translate('profile_choose_photo'),
            style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1C1C1E)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt, color: isDark ? Colors.white70 : const Color(0xFF0088CC)),
                title: Text(
                  l10n.translate('profile_camera'),
                  style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF1C1C1E)),
                ),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: isDark ? Colors.white70 : const Color(0xFF0088CC)),
                title: Text(
                  l10n.translate('profile_gallery'),
                  style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF1C1C1E)),
                ),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    try {
      debugPrint('[_pickImage] Step 1: Opening image picker (source=$source)');
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
      );
      debugPrint('[_pickImage] Step 2: Image picker returned - pickedFile=${pickedFile?.path}');

      if (pickedFile != null && mounted) {
        debugPrint('[_pickImage] Step 3: Starting processAvatar for ${pickedFile.path}');
        final processedPath = await AvatarCropUtils.processAvatar(
          imagePath: pickedFile.path,
          context: context,
        );
        debugPrint('[_pickImage] Step 4: processAvatar returned - processedPath=$processedPath');

        if (processedPath != null && mounted) {
          final account = _accountManager.currentAccount;
          if (account != null) {
            setState(() => _isProcessing = true);
            try {
              debugPrint('[_pickImage] Step 5: Calling AvatarSyncService.setLocalAvatar()');
              final permanentPath = await AvatarSyncService().setLocalAvatar(
                account.userId,
                processedPath,
              );
              if (mounted) {
                setState(() {
                  _avatarFile = null;
                  _avatarUrl = permanentPath;
                  if (!_avatarUrls.contains(permanentPath)) {
                    _avatarUrls.insert(0, permanentPath);
                  }
                });
                widget.onUpdate?.call();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.translate('profile_photo_updated'))),
                );
              }
            } catch (e) {
              debugPrint('[_pickImage] Error setting local avatar: $e');
            } finally {
              if (mounted) {
                setState(() => _isProcessing = false);
              }
            }
          }
        } else {
          debugPrint('[_pickImage] processAvatar returned null or not mounted - skipping upload');
        }
      } else {
        debugPrint('[_pickImage] No file picked or not mounted');
      }
    } catch (e, stackTrace) {
      debugPrint('[_pickImage] EXCEPTION: $e');
      debugPrint('[_pickImage] STACK: $stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('profile_photo_error').replaceAll('{error}', e.toString()))),
      );
    }
  }

  // ============================================================
  // Удаление фото
  // ============================================================

  Future<void> _deleteAvatar() async {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        title: Text(
          l10n.translate('profile_delete_photo_confirm_title'),
          style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1C1C1E)),
        ),
        content: Text(
          l10n.translate('profile_delete_photo_confirm_message'),
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              l10n.translate('profile_cancel'),
              style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              l10n.translate('profile_delete_photo'),
              style: TextStyle(color: Colors.red.shade400),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    HapticUtils.heavy();
    setState(() => _isProcessing = true);

    try {
      final account = _accountManager.currentAccount;
      final topAvatar = _avatarUrls.isNotEmpty ? _avatarUrls.first : null;
      final isLocalAvatar = topAvatar != null && (topAvatar.startsWith('/') || topAvatar.startsWith('file:') || File(topAvatar).existsSync());

      if (isLocalAvatar && account != null) {
        // Локальное удаление отложенного/локального аватара
        await AvatarSyncService().removeAvatar(account.userId, topAvatar);
        setState(() {
          _avatarUrls.removeAt(0);
          _avatarUrl = _avatarUrls.isNotEmpty ? _avatarUrls.first : null;
          _avatarFile = null;
        });
        await _accountManager.updateAccountProfile(account.userId, avatarUrl: _avatarUrl);
        widget.onUpdate?.call();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.translate('profile_photo_deleted'))),
          );
        }
        return;
      }

      // Удаление серверного аватара по ID
      final avatarIdToDelete = _avatarIds.isNotEmpty ? _avatarIds.first : null;
      final result = await AuthService.deleteAvatar(avatarId: avatarIdToDelete);
      if (!mounted) return;

      if (result['success'] == true) {
        setState(() {
          if (_avatarIds.isNotEmpty) {
            _avatarIds.removeAt(0);
          }
          if (_avatarUrls.isNotEmpty) {
            _avatarUrls.removeAt(0);
          }
          _avatarUrl = _avatarUrls.isNotEmpty ? _avatarUrls.first : null;
          _avatarFile = null;
        });

        if (account != null) {
          await _accountManager.updateAccountProfile(account.userId, avatarUrl: _avatarUrl);
        }

        widget.onUpdate?.call();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('profile_photo_deleted'))),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('profile_photo_error')
              .replaceAll('{error}', result['message'] ?? ''))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('profile_photo_error')
            .replaceAll('{error}', e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  // ============================================================
  // QR-код
  // ============================================================

  void _showQrCode() {
    final l10n = context.l10n;
    final account = _accountManager.currentAccount;
    if (account != null) {
      QrCodeDialog.show(
        context,
        userId: account.userId,
        displayName: _getDisplayName(),
        username: _usernameController.text.isNotEmpty
            ? _usernameController.text
            : account.username ?? '',
        avatarUrl: _avatarUrl,
        scanHintLabel: l10n.translate('profile_qr_scan_hint'),
      );
    }
  }

  Future<void> _openEditProfile() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          initialName: _nameController.text,
          initialSurname: _surnameController.text,
          initialUsername: _usernameController.text,
          initialPhone: _phoneController.text,
          initialBio: null,
          initialEmail: _emailController.text,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        if (result['name'] != null) _nameController.text = result['name'];
        if (result['surname'] != null) _surnameController.text = result['surname'];
        if (result['username'] != null) _usernameController.text = result['username'];
        if (result['phone'] != null) _phoneController.text = result['phone'];
      });
      if (widget.onUpdate != null) {
        widget.onUpdate!();
      }

      if (result['synced'] == false) {
        final l10n = context.l10n;
        InAppNotificationBanner.showBottomSyncBanner(
          context,
          title: l10n.translate('edit_profile_sync_offline_title'),
          message: l10n.translate('edit_profile_sync_offline_msg'),
        );
      }
    }
  }

  void _copyProfileLink() {
    final account = _accountManager.currentAccount;
    final username = _usernameController.text.trim();
    final link = AppConfig.getProfileUrl(
      username.isNotEmpty ? username : (account?.userId ?? ''),
    );

    Clipboard.setData(ClipboardData(text: link));
    HapticUtils.selection();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.translate('profile_link_copied')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _openColorSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ProfileColorScreen(),
      ),
    );
  }

  void _showTodoFeatureBanner(String featureName) {
    HapticUtils.tap();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$featureName — ${context.l10n.translate('feature_in_development')}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (_expandController.isAnimating) return;

    final dy = details.delta.dy;

    // 1. Если аватарка в процессе расширения / сворачивания (или полностью развёрнута)
    if (_expandFactor > 0.0) {
      if (_isExpanded && !_isCollapsingMode) {
        _isCollapsingMode = true;
      } else if (!_isExpanded && _isCollapsingMode) {
        _isCollapsingMode = false;
      }

      final screenHeight = MediaQuery.of(context).size.height;
      final progress = _expandFactor.clamp(0.0, 1.0);

      final resistance = 1.0 + 2.5 * math.sin(progress * math.pi);
      final delta = (dy / (screenHeight * 0.30)) / resistance;

      final oldFactor = _expandFactor;
      final newFactor = (_expandFactor + delta).clamp(0.0, 1.0);

      const expandThreshold = 0.32;
      const collapseThreshold = 0.68;

      if (!_isExpanded && oldFactor < expandThreshold && newFactor >= expandThreshold) {
        _isExpanded = true;
        _isCollapsingMode = false;
        _animateToExpand(1.0, velocity: (details.primaryDelta ?? 1.0) * 100.0);
        return;
      }

      if (_isExpanded && oldFactor >= collapseThreshold && newFactor < collapseThreshold) {
        _isExpanded = false;
        _isCollapsingMode = true;
        if (_avatarPageController.hasClients && (_avatarPageController.page?.round() ?? 0) != 0) {
          _avatarPageController.animateToPage(
            0,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOutCubic,
          );
        }
        _animateToExpand(0.0, velocity: (details.primaryDelta ?? -1.0) * 100.0);
        return;
      }

      setState(() {
        _expandFactor = newFactor;
        _expandController.value = _expandFactor;
      });
      return;
    }

    // 2. Если аватарка полностью в круглом состоянии (_expandFactor == 0.0)
    final currentScroll = _scrollController.hasClients ? _scrollController.offset : 0.0;

    // Свайп вниз в самом верху экрана по любой области -> разворачиваем аватарку!
    if (dy > 0 && currentScroll <= 0.0) {
      final screenHeight = MediaQuery.of(context).size.height;
      final delta = dy / (screenHeight * 0.30);
      final newFactor = (_expandFactor + delta).clamp(0.0, 1.0);
      setState(() {
        _expandFactor = newFactor;
        _expandController.value = _expandFactor;
      });
    } else if (_scrollController.hasClients) {
      // Иначе — скроллим весь экран целиком!
      final maxExtent = _scrollController.position.maxScrollExtent;
      final targetOffset = (currentScroll - dy).clamp(0.0, math.max<double>(0.0, maxExtent));
      _scrollController.jumpTo(targetOffset);
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (_expandController.isAnimating) return;

    if (_expandFactor > 0.0 && _expandFactor < 1.0) {
      final velocity = details.primaryVelocity ?? 0.0;
      final isSwipeDown = velocity > 180;
      final isSwipeUp = velocity < -180;

      const expandThreshold = 0.32;
      const collapseThreshold = 0.68;

      if (_isExpanded) {
        if (isSwipeUp || _expandFactor < collapseThreshold) {
          _isExpanded = false;
          _animateToExpand(0.0, velocity: velocity);
        } else {
          _animateToExpand(1.0, velocity: velocity);
        }
      } else {
        if (isSwipeDown || _expandFactor >= expandThreshold) {
          _isExpanded = true;
          _animateToExpand(1.0, velocity: velocity);
        } else {
          _animateToExpand(0.0, velocity: velocity);
        }
      }
      return;
    }

    // Доводчик для зафиксированного положения шапки при прокрутке вверх
    if (_expandFactor == 0.0 && _scrollController.hasClients) {
      final currentScroll = _scrollController.offset;
      final velocity = details.primaryVelocity ?? 0.0;
      const snapOffset = 233.0; // Точная позиция фиксации панели инфо под шапкой

      if (currentScroll > 0.0 && currentScroll < snapOffset + 35.0) {
        final bool shouldSnapToHeader;
        if (velocity < -120) {
          // Свайп ВВЕРХ -> доводчик доводит до зафиксированного положения
          shouldSnapToHeader = true;
        } else if (velocity > 150) {
          // Свайп ВНИЗ -> доводчик доводит до самого верха (0.0)
          shouldSnapToHeader = false;
        } else {
          // Отпустили палец без высокой скорости -> выбираем ближайшее положение
          shouldSnapToHeader = currentScroll >= snapOffset * 0.42;
        }

        final target = shouldSnapToHeader ? snapOffset : 0.0;
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
        return;
      }

      if (velocity.abs() > 120) {
        final maxExtent = _scrollController.position.maxScrollExtent;
        final targetOffset = (currentScroll - velocity * 0.35).clamp(
          snapOffset,
          math.max<double>(snapOffset, maxExtent),
        );
        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 350),
          curve: Curves.decelerate,
        );
      }
    }
  }

  /// Вычисляет смещение аватарки (translation) в зависимости от текущего фактора расширения и режима (расширение / сворачивание).
  double _calculateAvatarTopTranslation({
    required double screenWidth,
    required double topOffset,
  }) {
    final progress = _expandFactor.clamp(0.0, 1.0);
    final startCenterY = topOffset + 55.0;
    final endCenterY = screenWidth / 2;

    final curvedFactor = Curves.easeInOutCubic.transform(progress);
    final currentCenterY = startCenterY + (endCenterY - startCenterY) * curvedFactor;
    final currentSize = _calculateCurrentAvatarSize(screenWidth);

    final currentTop = currentCenterY - currentSize / 2;
    return currentTop - topOffset;
  }

  /// Вычисляет текущий размер аватарки
  double _calculateCurrentAvatarSize(double screenWidth) {
    final progress = _expandFactor.clamp(0.0, 1.0);
    const expandThreshold = 0.32;
    const collapseThreshold = 0.68;

    if (_isCollapsingMode) {
      if (progress >= collapseThreshold) {
        return screenWidth;
      } else {
        final collapseProgress = (progress / collapseThreshold).clamp(0.0, 1.0);
        final collapseFactor = Curves.easeInQuart.transform(collapseProgress);
        return 110.0 + (screenWidth - 110.0) * collapseFactor;
      }
    } else {
      if (progress < expandThreshold) {
        final preProgress = (progress / expandThreshold).clamp(0.0, 1.0);
        final preFactor = Curves.easeOutCubic.transform(preProgress);
        return 110.0 + (145.0 - 110.0) * preFactor;
      } else {
        final expansionProgress = ((progress - expandThreshold) / (1.0 - expandThreshold)).clamp(0.0, 1.0);
        final fastSizeFactor = Curves.easeOutQuart.transform(expansionProgress);
        return 145.0 + (screenWidth - 145.0) * fastSizeFactor;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LiquidGlassProvider>(
      builder: (context, glassProvider, _) {
        final glassEnabled = glassProvider.enabled;
        final isLite = glassProvider.isLite;

        if (glassEnabled) {
          return _buildGlassProfile(context, isLite: isLite);
        }
        return _buildModernProfile(context);
      },
    );
  }

  void _openFullAvatarViewer() async {
    if (_avatarUrls.isEmpty) {
      _pickImage();
      return;
    }

    final currentIndex = _avatarPageController.hasClients
        ? (_avatarPageController.page?.round() ?? 0).clamp(0, _avatarUrls.length - 1)
        : 0;

    await AvatarGalleryViewer.open(
      context,
      avatarUrls: _avatarUrls,
      initialIndex: currentIndex,
      displayName: _getDisplayName(),
      onChoosePhoto: _pickImage,
      onDelete: (index) {
        _deleteAvatar();
      },
    onPageChanged: (index) {
      setState(() {
        _currentAvatarIndex = index;
      });
      if (_avatarPageController.hasClients) {
        _avatarPageController.jumpToPage(index);
      }
    },
    );

    // При закрытии полноэкранного просмотра: если мы в свёрнутом режиме (круглая аватарка)
    // и закрыли просмотр не на первой странице — плавно сменяем фото на самую актуальную (0)
    if (mounted && _expandFactor < 0.5 && _avatarPageController.hasClients) {
      final currentPage = _avatarPageController.page?.round() ?? 0;
      if (currentPage != 0) {
        _avatarPageController.animateToPage(
          0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOutCubic,
        );
      }
    }
  }

  // ============================================================
  // Liquid Glass дизайн
  // ============================================================

  Widget _buildGlassProfile(BuildContext context, {bool isLite = false}) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    Color backgroundColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF5F5F5);
    final profileTheme = context.watch<ProfileThemeProvider>();
    if (profileTheme.hasCustomColor) {
      final preset = profileTheme.currentPreset!;
      if (preset.isGradient && preset.gradientColors != null) {
        backgroundColor = preset.gradientColors!.reduce(
            (a, b) => b);
      } else {
        backgroundColor = preset.backgroundColor;
      }
    }
    final onSurfaceColor = isDark ? const Color(0xFFE5E5EA) : const Color(0xFF1C1C1E);

    final screenWidth = MediaQuery.of(context).size.width;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    const headerHeight = 48.0;
    final topOffset = statusBarHeight + headerHeight - 15.0;

    final avatarTopTranslation = _calculateAvatarTopTranslation(
      screenWidth: screenWidth,
      topOffset: topOffset,
    );
    final contentTranslation = avatarTopTranslation;

    final scrollOffset = (_scrollController.hasClients ? _scrollController.offset : 0.0).clamp(0.0, double.infinity);
    final effectiveAvatarTranslation = avatarTopTranslation - (1.0 - _expandFactor) * scrollOffset;

    final currentSize = _calculateCurrentAvatarSize(screenWidth);
    final avatarTopY = topOffset + effectiveAvatarTranslation;
    final usernameTopY = avatarTopY + currentSize + contentTranslation + 12.0;
    
    // Блюр начинается немного выше (над) именем пользователя и заканчивается на середине кнопок
    final blurTopY = usernameTopY - 0.0; 
    final blurBottomY = usernameTopY + 85.0; 
    final blurHeight = math.max(0.0, blurBottomY - blurTopY);
    final blurProgress = ((_expandFactor - 0.15) / 0.85).clamp(0.0, 1.0);
    final blurFactor = Curves.easeOutCubic.transform(blurProgress);

    final isPhotoTopLight = _topLuminance > 0.55;

    final targetIconBrightness = _expandFactor > 0.4
        ? (isPhotoTopLight ? Brightness.dark : Brightness.light)
        : (isDark ? Brightness.light : Brightness.dark);

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: targetIconBrightness,
      statusBarBrightness: targetIconBrightness == Brightness.dark ? Brightness.light : Brightness.dark,
    );

    final expandedHeaderColor = targetIconBrightness == Brightness.dark
        ? Colors.black.withValues(alpha: 0.85)
        : Colors.white;

    final headerIconColor = Color.lerp(
      onSurfaceColor.withValues(alpha: 0.7),
      expandedHeaderColor,
      _expandFactor,
    );


    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF0088CC)))
            : GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: _handleVerticalDragUpdate,
          onVerticalDragEnd: _handleVerticalDragEnd,
          child: Stack(
            children: [
              // 1. Основной фон экрана (адаптивный, включая цвет профиля)
              AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeInOutCubic,
                color: backgroundColor,
              ),

              // 2. Кастомный фоновый градиент ТОЛЬКО вокруг аватарки
              Builder(
                builder: (context) {
                  final profileTheme = context.watch<ProfileThemeProvider>();
                  if (!profileTheme.hasCustomColor) return const SizedBox.shrink();
                  final preset = profileTheme.currentPreset!;
                  if (!preset.isGradient) return const SizedBox.shrink();
                  
                  final headerBgHeight = topOffset + avatarTopTranslation + currentSize + 50.0;

                  return Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: math.max(0.0, headerBgHeight),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeInOutCubic,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: preset.gradientColors!,
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  );
                },
              ),

              // 2. Аватарка (с прозрачностью при прокрутке вверх)
              Positioned(
                top: topOffset,
                left: 0,
                right: 0,
                child: Transform.translate(
                  offset: Offset(0, effectiveAvatarTranslation),
                  child: Center(
                    child: Opacity(
                      opacity: _expandFactor > 0.0
                          ? 1.0
                          : (1.0 - (scrollOffset / 90.0)).clamp(0.0, 1.0),
                      child: Builder(
                        builder: (context) {
                          final profileTheme = context.watch<ProfileThemeProvider>();
                          Color avatarBgColor = backgroundColor;
                          if (profileTheme.hasCustomColor) {
                            final preset = profileTheme.currentPreset!;
                            if (preset.isGradient && preset.gradientColors != null) {
                              avatarBgColor = preset.gradientColors!.reduce(
                                  (a, b) => b);
                            } else {
                              avatarBgColor = preset.backgroundColor;
                            }
                          }
                          return ExpandableAvatar(
                            pageController: _avatarPageController,
                            initialPage: _currentAvatarIndex,
                            avatarUrls: _avatarUrls,
                            avatarFile: _avatarFile,
                            expandFactor: _expandFactor,
                            isCollapsing: _isCollapsingMode,
                            tintColor: avatarBgColor,
                            backgroundColor: avatarBgColor,
                            displayName: _getDisplayName(),
                            onTap: _openFullAvatarViewer,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),

              // 2. Бэкдроп блюр НАД аватаркой, но ЗА текстом и кнопками действия
              if (_expandFactor > 0.05 && blurFactor > 0.001)
                Positioned(
                  top: blurTopY,
                  left: 0,
                  right: 0,
                  height: blurHeight + 5,
                  child: IgnorePointer(
                    child: Inspire.tint.bottomToTop(
                      color: backgroundColor,
                      opacity: 1.0 * blurFactor,
                      extent: 0.85,
                      curve: Curves.easeOutCubic,
                      child: Inspire.backdropBlur(
                        config: InspireBlurConfig.bottomToTop(
                          sigma: 10.0 * blurFactor,
                          extent: 0.85,
                          fadeCurve: Curves.easeOutCubic,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
                
              if (_expandFactor > 0.05 && blurFactor > 0.001)
                Positioned(
                  top: blurBottomY,
                  left: 0,
                  right: 0,
                  bottom: -1000, // Уходим далеко вниз, чтобы гарантированно закрыть фон
                  child: IgnorePointer(
                    child: Container(
                      color: backgroundColor, // Прямоугольник цвета фона
                    ),
                  ),
                ),
              SingleChildScrollView(
                controller: _scrollController,
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  children: [
                    SizedBox(
                      height: topOffset + 110.0 + (_expandFactor > 0.0 ? (avatarTopTranslation + currentSize - 110.0) : 0.0),
                      width: double.infinity,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _openFullAvatarViewer,
                        onHorizontalDragUpdate: (details) {
                          if (_avatarUrls.length > 1 && _expandFactor > 0.5 && _avatarPageController.hasClients) {
                            final currentOffset = _avatarPageController.offset;
                            final newOffset = (currentOffset - details.delta.dx).clamp(
                              0.0,
                              _avatarPageController.position.maxScrollExtent,
                            );
                            _avatarPageController.jumpTo(newOffset);
                          }
                        },
                        onHorizontalDragEnd: (details) {
                          if (_avatarUrls.length > 1 && _expandFactor > 0.5 && _avatarPageController.hasClients) {
                            final double currentPage = _avatarPageController.page ?? 0.0;
                            final velocity = details.primaryVelocity ?? 0.0;
                            final int targetPage;
                            if (velocity < -250) {
                              targetPage = (currentPage.floor() + 1).clamp(0, _avatarUrls.length - 1);
                            } else if (velocity > 250) {
                              targetPage = (currentPage.ceil() - 1).clamp(0, _avatarUrls.length - 1);
                            } else {
                              targetPage = currentPage.round().clamp(0, _avatarUrls.length - 1);
                            }
                            _avatarPageController.animateToPage(
                              targetPage,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        },
                        child: const SizedBox.expand(),
                      ),
                    ),

                    Transform.translate(
                      offset: Offset(0, contentTranslation),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Opacity(
                          opacity: _expandFactor > 0.0
                              ? 1.0
                              : (1.0 - (scrollOffset / 75.0)).clamp(0.0, 1.0),
                          child: Column(
                            children: [
                              Text(
                                _getDisplayName(),
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: onSurfaceColor),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l10n.translate('profile_online'),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: context.watch<ProfileThemeProvider>().hasCustomColor
                                      ? context.watch<ProfileThemeProvider>().statusColor
                                      : const Color(0xFF0088CC).withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Transform.translate(
                      offset: Offset(0, contentTranslation),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: 32),
                          child: Column(
                            children: [
                              LiquidGlassProfileButtons(
                                enabled: true,
                                isLite: isLite,
                                onChoosePhoto: _pickImage,
                                onQrCode: _showQrCode,
                                onEdit: _openEditProfile,
                                onDeletePhoto: _deleteAvatar,
                                hasAvatar: _avatarUrl != null || _avatarFile != null,
                                collapseProgress: (scrollOffset / 180.0).clamp(0.0, 1.0),
                                choosePhotoLabel: l10n.translate('profile_choose_photo'),
                                qrCodeLabel: l10n.translate('profile_qr_code'),
                                editLabel: l10n.translate('profile_edit_btn'),
                                deletePhotoLabel: l10n.translate('profile_delete_photo'),
                              ),
                              const SizedBox(height: 12),
                              LiquidGlassMusicStatus(
                                enabled: true,
                                isLite: isLite,
                                trackTitle: null,
                                trackAuthor: null,
                                musicLabel: l10n.translate('profile_music'),
                              ),
                              const SizedBox(height: 12),
                              LiquidGlassInfoPanel(
                                enabled: true,
                                isLite: isLite,
                                phone: _phoneController.text.isNotEmpty ? _phoneController.text : null,
                                bio: null,
                                username: _usernameController.text.isNotEmpty ? _usernameController.text : null,
                                birthday: null,
                                age: null,
                                phoneLabel: l10n.translate('profile_phone'),
                                bioLabel: l10n.translate('profile_bio'),
                                usernameLabel: l10n.translate('profile_username'),
                                birthdayLabel: l10n.translate('profile_birthday'),
                                ageLabel: l10n.translate('profile_age'),
                              ),
                              const SizedBox(height: 12),
                              ProfileSegmentedControl(
                                enabled: true,
                                isLite: isLite,
                                selectedIndex: _selectedSegment,
                                onTabChanged: (index) {
                                  setState(() {
                                    _selectedSegment = index;
                                  });
                                },
                                wallLabel: l10n.translate('profile_tab_wall'),
                                giftsLabel: l10n.translate('profile_tab_gifts'),
                              ),
                              SizedBox(height: math.max(250.0, MediaQuery.of(context).size.height * 0.6)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 5. Аватарка (с вертикальным отражением нижних 15%)
              // Прогрессивный Backdrop Blur для всей верхней области от пакета inspire_blur
              if (statusBarHeight > 0 && _expandFactor > 0.01)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: statusBarHeight + 0.0,
                  child: InspireBackdropBlur(
                    clipBehavior: Clip.none,
                    config: InspireBlurConfig.topToBottom(
                      sigma: 10.0 * _expandFactor,
                      extent: 1.0,
                      fadeCurve: Curves.easeOutCubic,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),

              Positioned(
                top: statusBarHeight,
                left: 0,
                right: 0,
                child: _buildProfileHeader(
                  context,
                  l10n,
                  isDark,
                  onSurfaceColor,
                  iconColor: headerIconColor,
                  glassEnabled: true,
                  isLite: isLite,
                  scrollOffset: scrollOffset,
                ),
              ),

              // Индикатор загрузки
              if (_isProcessing)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.3),
                    child: const Center(
                      child: CircularProgressIndicator(color: Color(0xFF0088CC)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Современный дизайн БЕЗ Liquid Glass
  // ============================================================

  Widget _buildModernProfile(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    Color backgroundColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF5F5F5);
    final profileTheme = context.watch<ProfileThemeProvider>();
    if (profileTheme.hasCustomColor) {
      final preset = profileTheme.currentPreset!;
      if (preset.isGradient && preset.gradientColors != null) {
        backgroundColor = preset.gradientColors!.reduce(
            (a, b) => b);
      } else {
        backgroundColor = preset.backgroundColor;
      }
    }
    final onSurfaceColor = isDark ? const Color(0xFFE5E5EA) : const Color(0xFF1C1C1E);
    final brandColor = context.watch<ProfileThemeProvider>().primaryColor;

    final screenWidth = MediaQuery.of(context).size.width;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    const headerHeight = 48.0;
    final topOffset = statusBarHeight + headerHeight - 15.0;

    final avatarTopTranslation = _calculateAvatarTopTranslation(
      screenWidth: screenWidth,
      topOffset: topOffset,
    );
    final contentTranslation = avatarTopTranslation;

    final scrollOffset = (_scrollController.hasClients ? _scrollController.offset : 0.0).clamp(0.0, double.infinity);
    final effectiveAvatarTranslation = avatarTopTranslation - (1.0 - _expandFactor) * scrollOffset;

    final currentSize = _calculateCurrentAvatarSize(screenWidth);
    final avatarTopY = topOffset + effectiveAvatarTranslation;
    final usernameTopY = avatarTopY + currentSize + contentTranslation + 12.0;
    
    // Блюр начинается немного выше (над) именем пользователя и заканчивается на середине кнопок
    final blurTopY = usernameTopY - 0.0; 
    final blurBottomY = usernameTopY + 85.0; 
    final blurHeight = math.max(0.0, blurBottomY - blurTopY);
    final blurProgress = ((_expandFactor - 0.15) / 0.85).clamp(0.0, 1.0);
    final blurFactor = Curves.easeOutCubic.transform(blurProgress);

    final isPhotoTopLight = _topLuminance > 0.55;

    final targetIconBrightness = _expandFactor > 0.4
        ? (isPhotoTopLight ? Brightness.dark : Brightness.light)
        : (isDark ? Brightness.light : Brightness.dark);

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: targetIconBrightness,
      statusBarBrightness: targetIconBrightness == Brightness.dark ? Brightness.light : Brightness.dark,
    );

    final expandedHeaderColor = targetIconBrightness == Brightness.dark
        ? Colors.black.withValues(alpha: 0.85)
        : Colors.white;

    final headerIconColor = Color.lerp(
      onSurfaceColor.withValues(alpha: 0.7),
      expandedHeaderColor,
      _expandFactor,
    );

    final cardColor = isDark
        ? const Color.fromARGB(180, 44, 44, 46)
        : const Color.fromARGB(180, 255, 255, 255);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF0088CC)))
            : GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: _handleVerticalDragUpdate,
          onVerticalDragEnd: _handleVerticalDragEnd,
          child: Stack(
            children: [
              // 1. Основной фон экрана (адаптивный, включая цвет профиля)
              AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeInOutCubic,
                color: backgroundColor,
              ),

              // 2. Кастомный фоновый градиент ТОЛЬКО вокруг аватарки
              Builder(
                builder: (context) {
                  final profileTheme = context.watch<ProfileThemeProvider>();
                  if (!profileTheme.hasCustomColor) return const SizedBox.shrink();
                  final preset = profileTheme.currentPreset!;
                  if (!preset.isGradient) return const SizedBox.shrink();
                  
                  final headerBgHeight = topOffset + avatarTopTranslation + currentSize + 50.0;

                  return Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: math.max(0.0, headerBgHeight),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeInOutCubic,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: preset.gradientColors!,
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  );
                },
              ),

              // 2. Аватарка (с вертикальным отражением нижних 15%)
              Positioned(
                top: topOffset,
                left: 0,
                right: 0,
                child: Transform.translate(
                  offset: Offset(0, effectiveAvatarTranslation),
                  child: Center(
                    child: ExpandableAvatar(
                      pageController: _avatarPageController,
                      initialPage: _currentAvatarIndex,
                      avatarUrls: _avatarUrls,
                      avatarFile: _avatarFile,
                      expandFactor: _expandFactor,
                      isCollapsing: _isCollapsingMode,
                      tintColor: backgroundColor,
                      backgroundColor: backgroundColor,
                      displayName: _getDisplayName(),
                      onTap: _openFullAvatarViewer,
                    ),
                  ),
                ),
              ),

              // 2. Бэкдроп блюр НАД аватаркой, но ЗА текстом и кнопками действия
              if (_expandFactor > 0.05 && blurFactor > 0.001)
                Positioned(
                  top: blurTopY,
                  left: 0,
                  right: 0,
                  height: blurHeight,
                  child: IgnorePointer(
                    child: Inspire.tint.bottomToTop(
                      color: backgroundColor,
                      opacity: 1.0 * blurFactor,
                      extent: 0.85,
                      curve: Curves.easeOutCubic,
                      child: Inspire.backdropBlur(
                        config: InspireBlurConfig.bottomToTop(
                          sigma: 10.0 * blurFactor,
                          extent: 0.85,
                          fadeCurve: Curves.easeOutCubic,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
                
              SingleChildScrollView(
                controller: _scrollController,
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  children: [
                    SizedBox(
                      height: topOffset + 110.0 + (_expandFactor > 0.0 ? (avatarTopTranslation + currentSize - 110.0) : 0.0),
                      width: double.infinity,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _openFullAvatarViewer,
                        onHorizontalDragUpdate: (details) {
                          if (_avatarUrls.length > 1 && _expandFactor > 0.5 && _avatarPageController.hasClients) {
                            final currentOffset = _avatarPageController.offset;
                            final newOffset = (currentOffset - details.delta.dx).clamp(
                              0.0,
                              _avatarPageController.position.maxScrollExtent,
                            );
                            _avatarPageController.jumpTo(newOffset);
                          }
                        },
                        onHorizontalDragEnd: (details) {
                          if (_avatarUrls.length > 1 && _expandFactor > 0.5 && _avatarPageController.hasClients) {
                            final double currentPage = _avatarPageController.page ?? 0.0;
                            final velocity = details.primaryVelocity ?? 0.0;
                            final int targetPage;
                            if (velocity < -250) {
                              targetPage = (currentPage.floor() + 1).clamp(0, _avatarUrls.length - 1);
                            } else if (velocity > 250) {
                              targetPage = (currentPage.ceil() - 1).clamp(0, _avatarUrls.length - 1);
                            } else {
                              targetPage = currentPage.round().clamp(0, _avatarUrls.length - 1);
                            }
                            _avatarPageController.animateToPage(
                              targetPage,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        },
                        child: const SizedBox.expand(),
                      ),
                    ),

                    Transform.translate(
                      offset: Offset(0, contentTranslation),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Opacity(
                          opacity: _expandFactor > 0.0
                              ? 1.0
                              : (1.0 - (scrollOffset / 75.0)).clamp(0.0, 1.0),
                          child: Column(
                            children: [
                              Text(
                                _getDisplayName(),
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: onSurfaceColor),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l10n.translate('profile_online'),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: context.watch<ProfileThemeProvider>().hasCustomColor
                                      ? context.watch<ProfileThemeProvider>().statusColor
                                      : brandColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Transform.translate(
                      offset: Offset(0, contentTranslation),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: Column(
                            children: [
                              _buildModernButtons(
                                context,
                                l10n,
                                isDark,
                                cardColor,
                                onSurfaceColor,
                                brandColor,
                                collapseProgress: (scrollOffset / 180.0).clamp(0.0, 1.0),
                              ),
                              const SizedBox(height: 12),
                              LiquidGlassMusicStatus(
                                enabled: false,
                                trackTitle: null,
                                trackAuthor: null,
                                musicLabel: l10n.translate('profile_music'),
                              ),
                              const SizedBox(height: 12),
                              LiquidGlassInfoPanel(
                                enabled: false,
                                phone: _phoneController.text.isNotEmpty ? _phoneController.text : null,
                                bio: null,
                                username: _usernameController.text.isNotEmpty ? _usernameController.text : null,
                                birthday: null,
                                age: null,
                                phoneLabel: l10n.translate('profile_phone'),
                                bioLabel: l10n.translate('profile_bio'),
                                usernameLabel: l10n.translate('profile_username'),
                                birthdayLabel: l10n.translate('profile_birthday'),
                                ageLabel: l10n.translate('profile_age'),
                              ),
                              SizedBox(height: math.max(180.0, MediaQuery.of(context).size.height - 320.0)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Прогрессивный Backdrop Blur для всей верхней области от пакета inspire_blur
              if (statusBarHeight > 0 && _expandFactor > 0.01)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: statusBarHeight + 0.0,
                  child: InspireBackdropBlur(
                    clipBehavior: Clip.none,
                    config: InspireBlurConfig.topToBottom(
                      sigma: 10.0 * _expandFactor,
                      extent: 1.0,
                      fadeCurve: Curves.easeOutCubic,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),

              Positioned(
                top: statusBarHeight,
                left: 0,
                right: 0,
                child: _buildProfileHeader(
                  context,
                  l10n,
                  isDark,
                  onSurfaceColor,
                  iconColor: headerIconColor,
                  glassEnabled: false,
                  scrollOffset: scrollOffset,
                ),
              ),

              if (_isProcessing)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.3),
                    child: const Center(
                      child: CircularProgressIndicator(color: Color(0xFF0088CC)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Кнопки в современном режиме (без стекла)
  Widget _buildModernButtons(
    BuildContext context,
    AppLocalizations l10n,
    bool isDark,
    Color cardColor,
    Color onSurfaceColor,
    Color brandColor, {
    double collapseProgress = 0.0,
  }) {
    return LiquidGlassProfileButtons(
      enabled: false,
      onChoosePhoto: _pickImage,
      onQrCode: _showQrCode,
      onEdit: _openEditProfile,
      onDeletePhoto: _deleteAvatar,
      hasAvatar: _avatarUrl != null || _avatarFile != null,
      collapseProgress: collapseProgress,
      choosePhotoLabel: l10n.translate('profile_choose_photo'),
      qrCodeLabel: l10n.translate('profile_qr_code'),
      editLabel: l10n.translate('profile_edit_btn'),
      deletePhotoLabel: l10n.translate('profile_delete_photo'),
    );
  }

  // ============================================================
  // Общая шапка
  // ============================================================

  Widget _buildProfileHeader(
    BuildContext context,
    AppLocalizations l10n,
    bool isDark,
    Color onSurfaceColor, {
    Color? iconColor,
    bool glassEnabled = false,
    bool isLite = false,
    double scrollOffset = 0.0,
  }) {
    final effectiveIconColor = iconColor ?? (isDark ? Colors.white : Colors.black87);
    final titleOpacity = ((scrollOffset - 75.0) / 35.0).clamp(0.0, 1.0) *
        (1.0 - _expandFactor * 10.0).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _RoundHeaderButton(
            icon: Icons.arrow_back_ios_new,
            iconColor: effectiveIconColor,
            isDark: isDark,
            glassEnabled: glassEnabled,
            isLite: isLite,
            onTap: () => Navigator.maybePop(context),
          ),
          if (titleOpacity > 0.001)
            Expanded(
              child: Opacity(
                opacity: titleOpacity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    _getDisplayName(),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: onSurfaceColor,
                    ),
                  ),
                ),
              ),
            )
          else
            const Spacer(),
          _MorphingHeaderMenuButton(
            iconColor: effectiveIconColor,
            isDark: isDark,
            glassEnabled: glassEnabled,
            isLite: isLite,
            onEditProfile: _openEditProfile,
            onChoosePhoto: _pickImage,
            onChooseMusic: () => _showTodoFeatureBanner(l10n.translate('profile_menu_choose_music')),
            onChangeColor: _openColorSettings,
            onCopyLink: _copyProfileLink,
          ),
        ],
      ),
    );
  }

  String _getDisplayName() {
    final name = _nameController.text.trim();
    final surname = _surnameController.text.trim();
    if (name.isEmpty && surname.isEmpty) {
      return _usernameController.text.isNotEmpty
          ? '@${_usernameController.text}'
          : '';
    }
    return '$name $surname'.trim();
  }
}

/// Круглая кнопка в шапке профиля ("<-" и "три полоски")
/// С поддержкой более прозрачного Liquid Glass и отключением LiquidStretch в обычном режиме.
class _RoundHeaderButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final bool isDark;
  final bool glassEnabled;
  final bool isLite;
  final VoidCallback? onTap;

  const _RoundHeaderButton({
    Key? key,
    required this.icon,
    required this.iconColor,
    required this.isDark,
    this.glassEnabled = false,
    this.isLite = false,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const size = 42.0;

    Widget buttonContent;

    if (glassEnabled) {
      final glassProvider = context.watch<LiquidGlassProvider>();
      final glassStyle = glassProvider.createStyle(
        context: context,
        refractionIndex: 1.25,
        refractionWidth: 24.0,
        blur: 6.0,
        color: isDark
            ? const Color.fromARGB(12, 20, 20, 35)
            : const Color.fromARGB(15, 240, 240, 250),
        isLiteOverride: isLite,
        shape: const LiquidGlassShape.roundedRectangle(
          cornerRadius: size / 2,
        ),
      );

      final buttonChild = Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: isDark
            ? null
            : BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.04),
                  width: 0.5,
                ),
              ),
        child: Icon(icon, size: 22, color: iconColor),
      );

      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: LiquidGlassLens(
          style: glassStyle,
          child: buttonChild,
        ),
      );
    } else {
      // Modern вариант без стекла (без LiquidStretch)
      buttonContent = Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDark
              ? const Color.fromARGB(180, 44, 44, 46)
              : const Color.fromARGB(220, 255, 255, 255),
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.08),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 22, color: iconColor),
      );

      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: buttonContent,
      );
    }
  }
}

class _MorphMenuItemData {
  final String id;
  final String label;
  final Widget Function(Color color, double size) iconBuilder;

  const _MorphMenuItemData({
    required this.id,
    required this.label,
    required this.iconBuilder,
  });
}

class _ThreeDotsGlyph extends StatelessWidget {
  final double size;
  final Color? color;
  final VoidCallback onTap;

  const _ThreeDotsGlyph({
    super.key,
    required this.size,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = color ?? (isDark ? Colors.white : const Color(0xFF1C1C1E));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: iconoir.MoreVert(
            width: 22.0,
            height: 22.0,
            color: iconColor,
          ),
        ),
      ),
    );
  }
}

class _TopMorphMenu extends StatelessWidget {
  final double width;
  final List<_MorphMenuItemData> items;
  final ValueChanged<String> onItemTap;

  const _TopMorphMenu({
    super.key,
    required this.width,
    required this.items,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    final double totalHeight = items.length * 44.0 + 12.0;
    return SizedBox(
      width: width,
      height: totalHeight,
      child: OverflowBox(
        minWidth: width,
        maxWidth: width,
        minHeight: 0,
        maxHeight: totalHeight,
        alignment: Alignment.topCenter,
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < items.length; i++)
                    _MorphMenuRow(
                      key: ValueKey(items[i].id),
                      item: items[i],
                      onTap: () => onItemTap(items[i].id),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MorphMenuRow extends StatelessWidget {
  final _MorphMenuItemData item;
  final VoidCallback onTap;

  const _MorphMenuRow({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final itemColor = isDark ? Colors.white : const Color(0xFF1C1C1E);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 44.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0),
          child: Row(
            children: [
              item.iconBuilder(itemColor, 20.0),
              const SizedBox(width: 10.0),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.0,
                    fontWeight: FontWeight.w500,
                    color: itemColor,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MorphingHeaderMenuButton extends StatefulWidget {
  final Color iconColor;
  final bool isDark;
  final bool glassEnabled;
  final bool isLite;
  final VoidCallback onEditProfile;
  final VoidCallback onChoosePhoto;
  final VoidCallback onChooseMusic;
  final VoidCallback onChangeColor;
  final VoidCallback onCopyLink;

  const _MorphingHeaderMenuButton({
    Key? key,
    required this.iconColor,
    required this.isDark,
    this.glassEnabled = false,
    this.isLite = false,
    required this.onEditProfile,
    required this.onChoosePhoto,
    required this.onChooseMusic,
    required this.onChangeColor,
    required this.onCopyLink,
  }) : super(key: key);

  @override
  State<_MorphingHeaderMenuButton> createState() => _MorphingHeaderMenuButtonState();
}

class _MorphingHeaderMenuButtonState extends State<_MorphingHeaderMenuButton> {
  final LayerLink _layerLink = LayerLink();
  final OverlayPortalController _overlayPortalController = OverlayPortalController();
  bool _isOpen = false;
  static const double _ctrlSize = 42.0;
  static const double _menuWidth = 200.0;

  @override
  void initState() {
    super.initState();
    _overlayPortalController.show();
  }

  void _toggleMenu() {
    if (_isOpen) {
      _closeMenu();
    } else {
      _openMenu();
    }
  }

  void _openMenu() {
    if (_isOpen) return;
    HapticUtils.tap();
    setState(() {
      _isOpen = true;
    });
  }

  void _closeMenu() {
    if (!_isOpen) return;
    setState(() {
      _isOpen = false;
    });
  }

  void _closeMenuWithCallback(VoidCallback callback) {
    if (!_isOpen) {
      callback();
      return;
    }
    setState(() {
      _isOpen = false;
    });
    callback();
  }

  void _handleMenuAction(String id) {
    switch (id) {
      case 'edit_info':
        _closeMenuWithCallback(widget.onEditProfile);
        break;
      case 'choose_photo':
        _closeMenuWithCallback(widget.onChoosePhoto);
        break;
      case 'choose_music':
        _closeMenuWithCallback(widget.onChooseMusic);
        break;
      case 'change_color':
        _closeMenuWithCallback(widget.onChangeColor);
        break;
      case 'copy_link':
        _closeMenuWithCallback(widget.onCopyLink);
        break;
    }
  }

  List<_MorphMenuItemData> _getMenuItems(BuildContext context) {
    final l10n = context.l10n;
    return [
      _MorphMenuItemData(
        id: 'edit_info',
        label: l10n.translate('profile_menu_edit_info'),
        iconBuilder: (color, size) => iconoir.EditPencil(color: color, width: size, height: size),
      ),
      _MorphMenuItemData(
        id: 'choose_photo',
        label: l10n.translate('profile_menu_choose_photo'),
        iconBuilder: (color, size) => iconoir.Camera(color: color, width: size, height: size),
      ),
      _MorphMenuItemData(
        id: 'choose_music',
        label: l10n.translate('profile_menu_choose_music'),
        iconBuilder: (color, size) => iconoir.MusicDoubleNote(color: color, width: size, height: size),
      ),
      _MorphMenuItemData(
        id: 'change_color',
        label: l10n.translate('profile_menu_change_color'),
        iconBuilder: (color, size) => iconoir.Palette(color: color, width: size, height: size),
      ),
      _MorphMenuItemData(
        id: 'copy_link',
        label: l10n.translate('profile_menu_copy_link'),
        iconBuilder: (color, size) => iconoir.Link(color: color, width: size, height: size),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final glassProvider = context.watch<LiquidGlassProvider>();
    final morphStyle = glassProvider.createStyle(
      context: context,
      cornerRadius: _ctrlSize / 2,
      refractionIndex: 1.1,
      refractionWidth: 24.0,
      isLiteOverride: widget.isLite,
    );

    final menuItems = _getMenuItems(context);

    return OverlayPortal(
      controller: _overlayPortalController,
      overlayChildBuilder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_isOpen,
                child: GestureDetector(
                  onTap: _closeMenu,
                  behavior: HitTestBehavior.opaque,
                ),
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topRight,
              followerAnchor: Alignment.topRight,
              child: widget.glassEnabled
                  ? LiquidGlassMorph(
                      key: const ValueKey<String>('profile_header_menu_morph'),
                      alignment: Alignment.topRight,
                      motion: LiquidGlassMorphMotion.fluid,
                      smoothness: 28,
                      style: morphStyle,
                      child: _isOpen
                          ? _TopMorphMenu(
                              key: const ValueKey<String>('profile_menu'),
                              width: _menuWidth,
                              items: menuItems,
                              onItemTap: _handleMenuAction,
                            )
                          : _ThreeDotsGlyph(
                              key: const ValueKey<String>('profile_glyph'),
                              size: _ctrlSize,
                              color: widget.iconColor,
                              onTap: _toggleMenu,
                            ),
                    )
                  : AnimatedContainer(
                      key: const ValueKey<String>('profile_header_menu_matte'),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topRight,
                      child: Container(
                        decoration: BoxDecoration(
                          color: widget.isDark
                              ? const Color(0xFA2C2C2E)
                              : const Color(0xFAFFFFFF),
                          borderRadius: BorderRadius.circular(_ctrlSize / 2),
                          border: Border.all(
                            color: widget.isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.black.withValues(alpha: 0.08),
                            width: 0.5,
                          ),
                        ),
                        child: _isOpen
                            ? _TopMorphMenu(
                                key: const ValueKey<String>('profile_menu'),
                                width: _menuWidth,
                                items: menuItems,
                                onItemTap: _handleMenuAction,
                              )
                            : _ThreeDotsGlyph(
                                key: const ValueKey<String>('profile_glyph'),
                                size: _ctrlSize,
                                color: widget.iconColor,
                                onTap: _toggleMenu,
                              ),
                      ),
                    ),
            ),
          ],
        );
      },
      child: CompositedTransformTarget(
        link: _layerLink,
        child: const SizedBox(
          width: _ctrlSize,
          height: _ctrlSize,
        ),
      ),
    );
  }
}
