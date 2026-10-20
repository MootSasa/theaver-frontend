import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:image_picker/image_picker.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../services/account_manager.dart';
import '../../services/auth_service.dart';
import '../../services/avatar_sync_service.dart';
import '../../services/chat_actions_helper.dart';
import '../../services/chat_service.dart';
import '../../services/database/app_database.dart';
import '../../services/glass_toast_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/profile_instant_cache.dart';
import '../../services/profile_theme_provider.dart';
import '../../utils/avatar_crop_utils.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../../widgets/notifications/in_app_notification_banner.dart';
import '../../widgets/profile/avatar_gallery_viewer.dart';
import '../../widgets/profile/expandable_avatar.dart';
import '../../widgets/profile/liquid_glass_info_panel.dart';
import '../../widgets/profile/liquid_glass_music_status.dart';
import '../../widgets/profile/liquid_glass_profile_buttons.dart';
import '../../widgets/profile/profile_content_tabs.dart';
import '../../widgets/profile/profile_section_pill.dart';
import '../../widgets/profile/qr_code_dialog.dart';
import '../chat/channel_screen.dart';
import '../chat/edit_group_channel_screen.dart';
import '../chat/group_chat_screen.dart';
import '../chat/private_chat_screen.dart';
import 'edit_profile_screen.dart';
import 'profile_color_screen.dart';

/// Тип сущности, чей профиль открыт.
enum ProfileEntityType {
  self,
  user,
  group,
  channel,
}

/// Универсальный экран профиля в стиле Telegram (свой профиль, собеседник, группа, канал).
///
/// Поддерживает:
/// - **Liquid Glass** (`liquid_glass_easy: ^5.0.0`, режимы `full` и `lite`) и **Material Design**.
/// - 3-состояния аватарки (круглая `110dp`, пружинное раскрытие с порогом `0.38` в полноширинную
///   галерею `1:1` с мягким растворением нижней кромки в фон и наложением имени/статуса, и сворачивание при скролле).
/// - Динамический ряд круглых кнопок быстрых действий (3–5 кнопок, только иконки `iconoir_flutter`).
/// - Компактную капсулу музыкального статуса (`LiquidGlassMusicStatus`).
/// - Чистую информационную карточку без боковых иконок (`LiquidGlassInfoPanel`) с копированием,
///   кликабельными ссылками/`@упоминаниями` и кнопкой QR-кода.
/// - Морфинг-капсулу выбора разделов (`ProfileSectionPill`), которая при скролле вниз закрепляется
///   в центре верхней шапки между кнопками «Назад» и «Ещё (•••)».
class ProfileScreen extends StatefulWidget {
  final ProfileEntityType? entityType;
  final Function()? onUpdate;
  final String? userId;
  final String? initialName;
  final String? initialAvatarUrl;
  final bool? initialIsOnline;
  final DateTime? initialLastSeen;
  final String? chatId;
  final String? heroTag;
  final VoidCallback? onVoiceCall;
  final VoidCallback? onVideoCall;
  final VoidCallback? onSearchInChat;
  final ValueChanged<String>? onJumpToMessageId;

  const ProfileScreen({
    Key? key,
    this.entityType,
    this.onUpdate,
    this.userId,
    this.initialName,
    this.initialAvatarUrl,
    this.initialIsOnline,
    this.initialLastSeen,
    this.chatId,
    this.heroTag,
    this.onVoiceCall,
    this.onVideoCall,
    this.onSearchInChat,
    this.onJumpToMessageId,
  }) : super(key: key);

  @override
  ProfileScreenState createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  late TextEditingController _nameController;
  late TextEditingController _surnameController;
  late TextEditingController _usernameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;

  String? _avatarUrl;
  List<String> _avatarUrls = [];
  List<int> _avatarIds = [];
  File? _avatarFile;
  final ImagePicker _imagePicker = ImagePicker();

  bool _isLoading = false;
  bool _isProcessing = false;
  final AccountManager _accountManager = AccountManager();

  late ProfileEntityType _entityType;

  bool get _isSelf => _entityType == ProfileEntityType.self;
  bool get _isUser => _entityType == ProfileEntityType.user;
  bool get _isGroup => _entityType == ProfileEntityType.group;
  bool get _isChannel => _entityType == ProfileEntityType.channel;

  String get _heroKey =>
      widget.heroTag ??
      widget.userId ??
      widget.chatId ??
      widget.initialName ??
      'self';

  String? _resolvedChatId;
  String? _bio;
  DateTime? _birthday;
  bool _isOnline = false;
  DateTime? _lastSeen;
  bool _isMuted = false;
  bool _isBlocked = false;

  // Поля для групп и каналов
  String _inviteLink = '';
  bool _isPublic = false;
  bool _historyForNew = true;
  int _slowModeInterval = 0;
  int _memberCount = 0;
  String _myRole = 'member';
  List<ProfileMemberItem> _members = [];

  // Музыкальный статус
  String? _musicTitle;
  String? _musicAuthor;

  // Оформление профиля собеседника
  ProfileColorPreset? _peerColorPreset;

  // Общие материалы из локальной БД Drift
  List<DbMessage> _mediaMessages = [];
  List<DbMessage> _fileMessages = [];
  List<DbMessage> _linkMessages = [];
  List<DbMessage> _voiceMessages = [];

  /// Выбранная вкладка разделов
  int _selectedSectionIndex = 0;

  /// Ключи и измерения для единственного экземпляра капсулы разделов (`ProfileSectionPill`)
  final GlobalKey _profileStackKey = GlobalKey();
  final GlobalKey _sectionPillSlotKey = GlobalKey();
  final GlobalKey<ProfileSectionPillState> _sectionPillKey =
      GlobalKey<ProfileSectionPillState>();
  final GlobalKey<_MorphingHeaderMenuButtonState> _headerMenuKey =
      GlobalKey<_MorphingHeaderMenuButtonState>();
  bool _isSectionMenuOpen = false;
  bool _isHeaderMenuOpen = false;
  bool _ignoreDragForMenuDismiss = false;
  bool get _isAnyMenuOpen => _isSectionMenuOpen || _isHeaderMenuOpen;

  void _closeAllMenus() {
    if (_isSectionMenuOpen) {
      _sectionPillKey.currentState?.closeMenu();
      setState(() {
        _isSectionMenuOpen = false;
      });
    }
    if (_isHeaderMenuOpen) {
      _headerMenuKey.currentState?.closeMenu();
      setState(() {
        _isHeaderMenuOpen = false;
      });
    }
  }

  double _measuredSlotStackY = 460.0;
  double _measuredAtScrollOffset = 0.0;
  double _measuredAtTopSpacerHeight = 160.0;
  bool _hasSlotMeasurement = false;

  /// Логическое состояние аватарки (false = свёрнута в круг, true = развёрнута на всю ширину)
  bool _isAvatarExpanded = false;

  /// Фактор расширения аватарки: 0.0 = маленькая круглая, 1.0 = большая квадратная
  double _expandFactor = 0.0;

  /// Накопленный свайп вниз до порога авто-открытия (`_expandThreshold`)
  double _rawExpandDrag = 0.0;
  static const double _expandThreshold = 60.0;

  /// Накопленный свайп вверх до порога авто-сворачивания (`_collapseThreshold`)
  double _rawCollapseDrag = 0.0;
  static const double _collapseThreshold = 88.0;
  static const double _maxCollapseTensionShift = 52.0;

  /// Значение `_expandFactor`, при котором аватарка становится полностью круглой (`borderRadius == size / 2`)
  static const double _collapseCircleHoldFactor = 0.38;

  /// Ход пальца вверх после порога для полного завершения доводки (`0.38 -> 0.0`) при удерживаемом пальце
  static const double _collapseFinishDragDistance = 85.0;

  /// Полный ход доводчика верхней шапки при скролле (круглая аватарка + имя/статус + ряд кнопок быстрых действий)
  static const double _headerCollapseSnapExtent = 245.0;

  /// Текущее нелинейное смещение экрана вверх при накоплении энергии пружины перед сворачиванием
  double _collapseVisualShift = 0.0;
  double _collapseSnapStartShift = 0.0;
  double _collapseTensionReturnStart = 0.0;
  bool _autoExpandedInCurrentGesture = false;
  bool _isPointerDown = false;
  bool _isCollapseHoldingOnFinger = false;
  double _postThresholdCollapseDrag = 0.0;
  double _expandPreviewBaseFactor = 0.0;

  /// Прогресс перетягивания вниз уже раскрытой аватарки (0.0 .. 1.0) для перемещения в полноэкранный просмотр
  double _overExpandProgress = 0.0;
  bool _didTriggerFullscreenOnOverPull = false;
  bool _isAvatarViewerOpen = false;

  /// Яркость верхней части фото аватарки (0.0 = тёмное фото, 1.0 = светлое фото)
  double _topLuminance = 0.5;

  late AnimationController _expandController;
  late AnimationController _overExpandController;
  late AnimationController _collapseTensionController;
  late ScrollController _scrollController;
  late PageController _avatarPageController;
  int _currentAvatarIndex = 0;

  final FocusNode _keyboardFocusNode = FocusNode();
  Timer? _wheelSnapTimer;
  double _lastWheelDy = 0.0;
  double _horizontalWheelAccum = 0.0;
  DateTime? _lastHorizontalSwitchTime;

  bool get _canEditGroupOrChannel =>
      (_isGroup || _isChannel) && (_myRole == 'owner' || _myRole == 'admin');

  bool get _canAddGroupMembers =>
      _isGroup && (_myRole == 'owner' || _myRole == 'admin' || _isPublic);

  @override
  void initState() {
    super.initState();
    _entityType = _resolveEntityType();
    _resolvedChatId = widget.chatId;

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

    _overExpandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _overExpandController.addListener(() {
      setState(() {
        _overExpandProgress = _overExpandController.value;
      });
    });

    _collapseTensionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _collapseTensionController.addListener(() {
      final t = Curves.easeOutCubic.transform(_collapseTensionController.value);
      setState(() {
        _collapseVisualShift = _collapseTensionReturnStart * (1.0 - t);
      });
    });

    // Мгновенная синхронная гидратация всех данных профиля на Frame 0 (без lazy-загрузки)
    _hydrateSynchronouslyFromCache();
    _initializeProfileData();
  }

  /// Мгновенно (синхронно до первого build) заполняет все поля профиля из `ProfileInstantCache` и `AccountManager`.
  void _hydrateSynchronouslyFromCache() {
    _isLoading = false;
    final cache = ProfileInstantCache.instance;

    if (_isSelf) {
      final acc = _accountManager.currentAccount;
      if (acc != null) {
        _nameController.text = acc.name ?? '';
        _surnameController.text = acc.surname ?? '';
        _usernameController.text = acc.username ?? '';
        _emailController.text = acc.email ?? '';
        _phoneController.text = acc.phone ?? '';
        _bio = acc.bio;
        _birthday = acc.birthday;
        if (acc.avatarUrl != null && acc.avatarUrl!.isNotEmpty) {
          _avatarUrl = acc.avatarUrl;
          _avatarUrls = [acc.avatarUrl!];
        }
      }

      final snap = cache.getSelfSnapshotSync();
      if (snap != null) {
        if (snap.name.isNotEmpty) _nameController.text = snap.name;
        if (snap.surname.isNotEmpty) _surnameController.text = snap.surname;
        if (snap.username.isNotEmpty) _usernameController.text = snap.username;
        if (snap.email.isNotEmpty) _emailController.text = snap.email;
        if (snap.phone.isNotEmpty) _phoneController.text = snap.phone;
        if (snap.bio != null) _bio = snap.bio;
        if (snap.birthday != null) _birthday = snap.birthday;
        if (snap.avatarUrl != null && snap.avatarUrl!.isNotEmpty) {
          _avatarUrl = snap.avatarUrl;
        }
        if (snap.avatarUrls.isNotEmpty) {
          _avatarUrls = List<String>.from(snap.avatarUrls);
        }
        if (snap.avatarIds.isNotEmpty) {
          _avatarIds = List<int>.from(snap.avatarIds);
        }
        _musicTitle = snap.musicTitle;
        _musicAuthor = snap.musicAuthor;
        if ((_resolvedChatId == null || _resolvedChatId!.isEmpty) &&
            snap.resolvedChatId != null &&
            snap.resolvedChatId!.isNotEmpty) {
          _resolvedChatId = snap.resolvedChatId;
        }
      }
    } else if (_isUser) {
      _initInitialEntityData();
      final uid = widget.userId ?? '';
      if (uid.isNotEmpty) {
        _peerColorPreset = cache.getUserColorPresetSync(uid);
        final snap = cache.getUserSnapshotSync(uid);
        if (snap != null) {
          if (snap.name.isNotEmpty) _nameController.text = snap.name;
          if (snap.surname.isNotEmpty) _surnameController.text = snap.surname;
          if (snap.username.isNotEmpty) {
            _usernameController.text = snap.username;
          }
          if (snap.phone.isNotEmpty) _phoneController.text = snap.phone;
          if (snap.bio != null) _bio = snap.bio;
          if (snap.birthday != null) _birthday = snap.birthday;
          if (snap.avatarUrl != null && snap.avatarUrl!.isNotEmpty) {
            _avatarUrl = snap.avatarUrl;
          }
          if (snap.avatarUrls.isNotEmpty) {
            _avatarUrls = List<String>.from(snap.avatarUrls);
          }
          if (widget.initialIsOnline == null) _isOnline = snap.isOnline;
          if (widget.initialLastSeen == null && snap.lastSeen != null) {
            _lastSeen = snap.lastSeen;
          }
          _isMuted = snap.isMuted;
          _isBlocked = snap.isBlocked;
          if ((_resolvedChatId == null || _resolvedChatId!.isEmpty) &&
              snap.resolvedChatId != null &&
              snap.resolvedChatId!.isNotEmpty) {
            _resolvedChatId = snap.resolvedChatId;
          }
        }
        if (cache.isUserBlockedSync(uid)) {
          _isBlocked = true;
        }
      }
      if (_resolvedChatId != null && _resolvedChatId!.isNotEmpty) {
        if (cache.isChatMutedSync(_resolvedChatId)) {
          _isMuted = true;
        }
      }
    } else {
      // Group or Channel
      _initInitialEntityData();
      final cid = _resolvedChatId ?? '';
      if (cid.isNotEmpty) {
        final snap = cache.getGroupSnapshotSync(cid);
        if (snap != null) {
          if (snap.name.isNotEmpty) _nameController.text = snap.name;
          _bio = snap.description;
          _inviteLink = snap.inviteLink;
          _isPublic = snap.isPublic;
          _historyForNew = snap.historyForNew;
          _slowModeInterval = snap.slowModeInterval;
          _memberCount = snap.memberCount;
          _myRole = snap.myRole;
          if (snap.avatarUrl != null && snap.avatarUrl!.isNotEmpty) {
            _avatarUrl = snap.avatarUrl;
            if (!_avatarUrls.contains(snap.avatarUrl!)) {
              _avatarUrls = [snap.avatarUrl!, ..._avatarUrls];
            }
          }
          if (snap.members.isNotEmpty) {
            _members = List<ProfileMemberItem>.from(snap.members);
          }
          _isMuted = snap.isMuted;
        }
        if (cache.isChatMutedSync(cid)) {
          _isMuted = true;
        }
      }
    }

    // Мгновенно подставляем кэшированные вкладки (Медиа, Файлы, Ссылки, Голосовые)
    final shared = cache.getSharedContentSync(_resolvedChatId);
    if (shared != null) {
      _mediaMessages = shared.mediaMessages;
      _fileMessages = shared.fileMessages;
      _linkMessages = shared.linkMessages;
      _voiceMessages = shared.voiceMessages;
    }

    // Мгновенно подставляем кэшированную яркость аватарки
    final primaryAvatar =
        _avatarUrls.isNotEmpty ? _avatarUrls.first : _avatarUrl;
    final cachedLum = cache.getAvatarLuminanceSync(primaryAvatar);
    if (cachedLum != null) {
      _topLuminance = cachedLum;
    }
  }

  ProfileEntityType _resolveEntityType() {
    if (widget.entityType == ProfileEntityType.group ||
        widget.entityType == ProfileEntityType.channel ||
        widget.entityType == ProfileEntityType.self) {
      return widget.entityType!;
    }
    if (widget.userId == null || widget.userId!.isEmpty) {
      return ProfileEntityType.self;
    }
    final currentUserId = _accountManager.currentAccount?.userId;
    if (currentUserId != null && currentUserId == widget.userId) {
      return ProfileEntityType.self;
    }
    return widget.entityType ?? ProfileEntityType.user;
  }

  Future<void> _initializeProfileData() async {
    if (_isSelf) {
      AvatarSyncService().addListener(_onAvatarSyncChanged);
      unawaited(_loadMusicStatusPref());
      unawaited(_loadUserProfile());
      unawaited(_loadSharedContentForSelf());
    } else if (_isUser) {
      unawaited(_loadPeerThemePreset());
      unawaited(_loadMuteAndBlockState());
      unawaited(_loadOtherUserProfile());
      unawaited(_loadSharedContentForPeerUser());
    } else {
      // Group or Channel
      unawaited(_loadMuteAndBlockState());
      unawaited(_loadGroupOrChannelProfile());
      if (_resolvedChatId != null && _resolvedChatId!.isNotEmpty) {
        unawaited(_loadSharedContentForChat(_resolvedChatId!));
      }
    }
  }

  void _onScroll() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _wheelSnapTimer?.cancel();
    _keyboardFocusNode.dispose();
    if (_isSelf) {
      AvatarSyncService().removeListener(_onAvatarSyncChanged);
    }
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _nameController.dispose();
    _surnameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _avatarPageController.dispose();
    _collapseTensionController.dispose();
    _overExpandController.dispose();
    _expandController.dispose();
    super.dispose();
  }

  // ============================================================
  // Загрузка данных (Self / User / Group / Channel)
  // ============================================================

  Future<void> _loadMusicStatusPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = _accountManager.currentAccount?.userId ?? 'default';
      final title = prefs.getString('${uid}_profile_music_title');
      final author = prefs.getString('${uid}_profile_music_author');
      if (mounted && (_musicTitle != title || _musicAuthor != author)) {
        setState(() {
          _musicTitle = title;
          _musicAuthor = author;
        });
      }
    } catch (_) {}
  }

  void _onAvatarSyncChanged() async {
    if (!mounted) return;
    final account = _accountManager.currentAccount;
    if (account != null) {
      final localHistory =
          await AvatarSyncService().getLocalAvatarUrls(account.userId);
      if (!mounted) return;
      setState(() {
        final currentAccAvatar = account.avatarUrl;
        if (currentAccAvatar != null && currentAccAvatar.isNotEmpty) {
          _avatarUrl = currentAccAvatar;
        }
        final combined = <String>[];
        for (final local in localHistory) {
          if (local.isNotEmpty && !combined.contains(local)) {
            combined.add(local);
          }
        }
        for (final old in _avatarUrls) {
          if (old.isNotEmpty && !combined.contains(old)) combined.add(old);
        }
        if (_avatarUrl != null &&
            _avatarUrl!.isNotEmpty &&
            !combined.contains(_avatarUrl!)) {
          combined.add(_avatarUrl!);
        }
        _avatarUrls = combined;
        if (_avatarUrls.isNotEmpty &&
            (_avatarUrl == null || _avatarUrl!.isEmpty)) {
          _avatarUrl = _avatarUrls.first;
        }
      });
      _saveSelfSnapshotToInstantCache();
      widget.onUpdate?.call();
    }
  }

  void _saveSelfSnapshotToInstantCache() {
    final acc = _accountManager.currentAccount;
    if (acc == null) return;
    ProfileInstantCache.instance.putUserSnapshot(
      CachedUserProfileSnapshot(
        userId: acc.userId,
        name: _nameController.text,
        surname: _surnameController.text,
        username: _usernameController.text,
        email: _emailController.text,
        phone: _phoneController.text,
        bio: _bio,
        birthday: _birthday,
        avatarUrl: _avatarUrl,
        avatarUrls: List<String>.from(_avatarUrls),
        avatarIds: List<int>.from(_avatarIds),
        isOnline: true,
        musicTitle: _musicTitle,
        musicAuthor: _musicAuthor,
        resolvedChatId: _resolvedChatId,
      ),
    );
  }

  Future<void> _loadUserProfile() async {
    final account = _accountManager.currentAccount;

    if (account != null) {
      final localHistory =
          await AvatarSyncService().getLocalAvatarUrls(account.userId);
      if (localHistory.isNotEmpty && mounted) {
        setState(() {
          _avatarUrl = localHistory.first;
          final combined = <String>[
            ...localHistory,
            for (final old in _avatarUrls)
              if (!localHistory.contains(old)) old,
          ];
          _avatarUrls = combined;
        });
      }

      AvatarSyncService().syncPendingAvatar(account.userId);
    }

    try {
      final result = await AuthService.getCurrentUser();
      if (result['success'] == true && result['user'] != null && mounted) {
        final user = result['user'] as Map<String, dynamic>;
        final localHistory = account != null
            ? await AvatarSyncService().getLocalAvatarUrls(account.userId)
            : <String>[];

        if (!mounted) return;
        setState(() {
          _nameController.text = user['name'] ?? _nameController.text;
          _surnameController.text = user['surname'] ?? _surnameController.text;
          _usernameController.text =
              user['username'] ?? _usernameController.text;
          _emailController.text = user['email'] ?? _emailController.text;
          _phoneController.text = user['phone'] ?? _phoneController.text;
          if (user['bio'] != null) _bio = user['bio'].toString();
          if (user['birthday'] != null) {
            _birthday = DateTime.tryParse(user['birthday'].toString());
          }

          if (localHistory.isNotEmpty) {
            _avatarUrl = localHistory.first;
          } else {
            _avatarUrl = user['avatar_url'] ?? _avatarUrl;
          }

          if (user['avatars'] != null) {
            final avatarsList = user['avatars'] as List<dynamic>;
            final serverUrls = avatarsList
                .map((a) => a['avatar_url'].toString())
                .where((s) => s.isNotEmpty)
                .toList();
            _avatarIds = avatarsList
                .map((a) =>
                    (a['id'] is int ? a['id'] as int : (a['id'] as num).toInt()))
                .toList();

            final combined = <String>[];
            for (final l in localHistory) {
              if (l.isNotEmpty && !combined.contains(l)) combined.add(l);
            }
            for (final s in serverUrls) {
              if (s.isNotEmpty && !combined.contains(s)) combined.add(s);
            }
            if (_avatarUrl != null &&
                _avatarUrl!.isNotEmpty &&
                !combined.contains(_avatarUrl!)) {
              combined.add(_avatarUrl!);
            }
            _avatarUrls = combined;
            if (_avatarUrls.isNotEmpty &&
                (_avatarUrl == null || _avatarUrl!.isEmpty)) {
              _avatarUrl = _avatarUrls.first;
            }
          } else if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
            final combined = <String>[];
            for (final l in localHistory) {
              if (l.isNotEmpty && !combined.contains(l)) combined.add(l);
            }
            if (!combined.contains(_avatarUrl!)) combined.add(_avatarUrl!);
            _avatarUrls = combined;
            _avatarIds = [];
          }
        });
        _saveSelfSnapshotToInstantCache();
      }
    } catch (e) {
      debugPrint('Error loading profile from server: $e');
    }

    if (mounted) {
      _updateTopLuminance();
    }
  }

  void _initInitialEntityData() {
    _isLoading = false;
    if (widget.initialName != null && widget.initialName!.isNotEmpty) {
      if (_isGroup || _isChannel) {
        _nameController.text = widget.initialName!.trim();
      } else {
        final parts = widget.initialName!.trim().split(' ');
        _nameController.text = parts.first;
        if (parts.length > 1) {
          _surnameController.text = parts.sublist(1).join(' ');
        }
      }
    }
    if (widget.initialAvatarUrl != null &&
        widget.initialAvatarUrl!.isNotEmpty) {
      _avatarUrl = widget.initialAvatarUrl;
      _avatarUrls = [widget.initialAvatarUrl!];
    }
    _isOnline = widget.initialIsOnline ?? false;
    _lastSeen = widget.initialLastSeen;
    _updateTopLuminance();
  }

  Future<void> _loadPeerThemePreset() async {
    if (widget.userId == null || widget.userId!.isEmpty) return;
    final themeProvider = context.read<ProfileThemeProvider>();
    final cached = themeProvider.getCachedUserPreset(widget.userId!);
    if (cached != null && mounted && _peerColorPreset?.id != cached.id) {
      setState(() => _peerColorPreset = cached);
    }
    final fetched = await themeProvider.fetchUserPreset(widget.userId!);
    if (fetched != null && mounted && _peerColorPreset?.id != fetched.id) {
      setState(() => _peerColorPreset = fetched);
    }
  }

  Future<void> _loadMuteAndBlockState() async {
    try {
      if (_resolvedChatId != null && _resolvedChatId!.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final muted = prefs.getBool('muted_chat_$_resolvedChatId') ?? false;
        if (mounted && _isMuted != muted) {
          setState(() => _isMuted = muted);
        }
      }
      if (_isUser && widget.userId != null && widget.userId!.isNotEmpty) {
        final token = await AuthService.getToken();
        if (token != null) {
          final dio = Dio();
          final resp = await dio.get(
            '${AppConfig.baseUrl}/api/security/blocked',
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          );
          if (resp.statusCode == 200 && resp.data is Map) {
            final list = resp.data['blocked_users'] as List?;
            if (list != null) {
              final blocked = list.any(
                  (u) => (u['id'] ?? u['user_id'])?.toString() == widget.userId);
              if (mounted && _isBlocked != blocked) {
                setState(() => _isBlocked = blocked);
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _loadOtherUserProfile() async {
    if (widget.userId == null || widget.userId!.isEmpty) return;
    try {
      final res = await AuthService.getUserProfile(widget.userId!);
      if (res['success'] == true && res['user'] != null && mounted) {
        final u = res['user'] as Map<String, dynamic>;
        setState(() {
          final displayName =
              u['display_name']?.toString() ?? u['name']?.toString();
          if (displayName != null && displayName.isNotEmpty) {
            final parts = displayName.trim().split(' ');
            _nameController.text = parts.first;
            _surnameController.text = parts.length > 1
                ? parts.sublist(1).join(' ')
                : (u['surname']?.toString() ?? '');
          }
          if (u['username'] != null) {
            _usernameController.text = u['username'].toString();
          }
          if (u['phone'] != null) {
            _phoneController.text = u['phone'].toString();
          }
          if (u['bio'] != null) {
            _bio = u['bio'].toString();
          }
          if (u['birthday'] != null) {
            _birthday = DateTime.tryParse(u['birthday'].toString());
          }
          if (u['is_online'] is bool) {
            _isOnline = u['is_online'] as bool;
          }
          if (u['last_seen'] != null) {
            _lastSeen = DateTime.tryParse(u['last_seen'].toString());
          }
          if (u['avatar_url'] != null &&
              u['avatar_url'].toString().isNotEmpty) {
            final serverUrl = u['avatar_url'].toString();
            _avatarUrl = serverUrl;
            if (!_avatarUrls.contains(serverUrl)) {
              _avatarUrls = [serverUrl, ..._avatarUrls];
            }
          }
          if (u['avatars'] != null) {
            final list = u['avatars'] as List<dynamic>;
            final urls = list
                .map((a) => a['avatar_url'].toString())
                .where((s) => s.isNotEmpty)
                .toList();
            if (urls.isNotEmpty) {
              _avatarUrls = urls;
            }
          }
        });
        ProfileInstantCache.instance.putUserSnapshot(
          CachedUserProfileSnapshot(
            userId: widget.userId!,
            name: _nameController.text,
            surname: _surnameController.text,
            username: _usernameController.text,
            phone: _phoneController.text,
            bio: _bio,
            birthday: _birthday,
            avatarUrl: _avatarUrl,
            avatarUrls: List<String>.from(_avatarUrls),
            isOnline: _isOnline,
            lastSeen: _lastSeen,
            isMuted: _isMuted,
            isBlocked: _isBlocked,
            resolvedChatId: _resolvedChatId,
            colorPresetId: _peerColorPreset?.id,
          ),
        );
        _updateTopLuminance();
      }
    } catch (e) {
      debugPrint('[ProfileScreen] Error loading peer user profile: $e');
    }
  }

  Future<void> _loadGroupOrChannelProfile() async {
    final cid = _resolvedChatId;
    if (cid == null || cid.isEmpty) return;

    try {
      final token = await AuthService.getToken();
      final dio = Dio();
      final settingsFuture = dio.get(
        '${AppConfig.baseUrl}/api/chats/$cid/group-settings',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final membersFuture = dio.get(
        '${AppConfig.baseUrl}/api/chats/$cid/members',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final results = await Future.wait([
        settingsFuture.catchError((_) => Response(
              requestOptions: RequestOptions(path: ''),
              statusCode: 400,
            )),
        membersFuture.catchError((_) => Response(
              requestOptions: RequestOptions(path: ''),
              statusCode: 400,
            )),
      ]);

      final settingsResp = results[0];
      final membersResp = results[1];
      final currentUid = _accountManager.currentAccount?.userId;

      if (!mounted) return;
      setState(() {
        if (settingsResp.statusCode == 200 && settingsResp.data is Map) {
          final data = settingsResp.data as Map;
          if (data['name'] != null && data['name'].toString().isNotEmpty) {
            _nameController.text = data['name'].toString();
          }
          _bio = (data['description'] ?? '').toString();
          _inviteLink = (data['invite_link'] ?? '').toString();
          _isPublic = data['is_public'] == true;
          _historyForNew = data['history_for_new'] ?? true;
          _slowModeInterval = (data['slow_mode_interval'] as num?)?.toInt() ?? 0;
          _memberCount = (data['member_count'] as num?)?.toInt() ?? 0;
          final srvAvatar = data['avatar_url']?.toString();
          if (srvAvatar != null && srvAvatar.isNotEmpty) {
            _avatarUrl = srvAvatar;
            if (!_avatarUrls.contains(srvAvatar)) {
              _avatarUrls = [srvAvatar, ..._avatarUrls];
            }
          }
        }

        if (membersResp.statusCode == 200 && membersResp.data is Map) {
          final rawMembers = membersResp.data['members'] as List?;
          if (rawMembers != null) {
            _members = rawMembers
                .whereType<Map>()
                .map((m) =>
                    ProfileMemberItem.fromJson(Map<String, dynamic>.from(m)))
                .toList();
            if (_memberCount == 0) {
              _memberCount = _members.length;
            }
            if (currentUid != null) {
              final me =
                  _members.where((m) => m.userId == currentUid).firstOrNull;
              if (me != null) {
                _myRole = me.role;
              }
            }
          }
        }
      });
      ProfileInstantCache.instance.putGroupSnapshot(
        CachedGroupProfileSnapshot(
          chatId: cid,
          name: _nameController.text,
          description: _bio ?? '',
          inviteLink: _inviteLink,
          isPublic: _isPublic,
          historyForNew: _historyForNew,
          slowModeInterval: _slowModeInterval,
          memberCount: _memberCount,
          myRole: _myRole,
          avatarUrl: _avatarUrl,
          members: List<ProfileMemberItem>.from(_members),
          isMuted: _isMuted,
        ),
      );
      _updateTopLuminance();
    } catch (e) {
      debugPrint('[ProfileScreen] Error loading group/channel profile: $e');
    }
  }

  Future<void> _loadSharedContentForSelf() async {
    try {
      final savedChat = await AppDatabase().getSavedChat();
      if (savedChat != null) {
        _resolvedChatId = savedChat.chatId;
        await _loadSharedContentForChat(savedChat.chatId);
        _saveSelfSnapshotToInstantCache();
      }
    } catch (_) {}
  }

  Future<void> _loadSharedContentForPeerUser() async {
    try {
      if (_resolvedChatId == null || _resolvedChatId!.isEmpty) {
        if (widget.userId != null && widget.userId!.isNotEmpty) {
          final dbChat =
              await AppDatabase().getPrivateChatWithUser(widget.userId!);
          if (dbChat != null) {
            _resolvedChatId = dbChat.chatId;
          }
        }
      }
      if (_resolvedChatId != null && _resolvedChatId!.isNotEmpty) {
        await _loadSharedContentForChat(_resolvedChatId!);
      }
    } catch (_) {}
  }

  Future<void> _loadSharedContentForChat(String cid) async {
    if (cid.isEmpty) return;
    try {
      final db = AppDatabase();
      final results = await Future.wait([
        db.getSharedMediaForChat(cid),
        db.getSharedFilesForChat(cid),
        db.getSharedLinksForChat(cid),
        db.getSharedVoiceForChat(cid),
      ]);
      ProfileInstantCache.instance.putSharedContent(
        cid,
        CachedSharedContentSnapshot(
          mediaMessages: results[0],
          fileMessages: results[1],
          linkMessages: results[2],
          voiceMessages: results[3],
        ),
      );
      if (!mounted) return;
      setState(() {
        _mediaMessages = results[0];
        _fileMessages = results[1];
        _linkMessages = results[2];
        _voiceMessages = results[3];
      });
    } catch (e) {
      debugPrint('[ProfileScreen] Error loading shared content for $cid: $e');
    }
  }

  // ============================================================
  // Расчёт яркости верхней части аватарки
  // ============================================================

  Future<void> _updateTopLuminance() async {
    String? avatarKey;
    ImageProvider? provider;
    if (_avatarFile != null) {
      avatarKey = _avatarFile!.path;
      provider = FileImage(_avatarFile!);
    } else if (_avatarUrls.isNotEmpty) {
      final index = _currentAvatarIndex.clamp(0, _avatarUrls.length - 1);
      avatarKey = _avatarUrls[index];
      provider = avatarImageProvider(avatarKey);
    } else if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      avatarKey = _avatarUrl;
      provider = avatarImageProvider(avatarKey);
    }

    if (provider == null) {
      if (mounted) {
        setState(() => _topLuminance = 0.5);
      }
      return;
    }

    final cachedLum = ProfileInstantCache.instance.getAvatarLuminanceSync(avatarKey);
    if (cachedLum != null && mounted) {
      if ((_topLuminance - cachedLum).abs() > 0.001) {
        setState(() => _topLuminance = cachedLum);
      }
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
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return;

      final width = image.width;
      final height = image.height;
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

      if (countTop > 0) {
        final computed = totalLuminance / countTop;
        if (avatarKey != null) {
          ProfileInstantCache.instance.setAvatarLuminance(avatarKey, computed);
        }
        if (mounted && (_topLuminance - computed).abs() > 0.005) {
          setState(() {
            _topLuminance = computed;
          });
        }
      }
    } catch (_) {}
  }

  // ============================================================
  // Текст статуса и цвет темы профиля
  // ============================================================

  String _tr(AppLocalizations l10n, String key, String fallback) {
    final val = l10n.translate(key);
    return (val.isNotEmpty && val != key) ? val : fallback;
  }

  String _getStatusText(AppLocalizations l10n) {
    if (_isSelf) {
      return _tr(l10n, 'profile_online', 'в сети');
    }
    if (_isGroup) {
      final count = _memberCount > 0 ? _memberCount : _members.length;
      final onlineCount = _members.where((m) => m.isOnline).length;
      final base = '$count ${_tr(l10n, 'group_info_members', 'участников')}';
      if (onlineCount > 0) {
        return '$base, $onlineCount ${_tr(l10n, 'profile_online', 'в сети')}';
      }
      return base;
    }
    if (_isChannel) {
      final count = _memberCount > 0 ? _memberCount : _members.length;
      final tmpl = _tr(l10n, 'chat_status_subscribers_count', '{count} подписчиков');
      return tmpl.replaceAll('{count}', count.toString());
    }
    if (_isOnline) {
      return _tr(l10n, 'chat_online', 'в сети');
    } else if (_lastSeen != null) {
      return DateTimeUtils.formatLastSeen(_lastSeen, context);
    } else {
      return _tr(l10n, 'chat_offline', 'был(а) недавно');
    }
  }

  ProfileColorPreset? _getActiveColorPreset(ProfileThemeProvider profileTheme) {
    if (_isSelf && profileTheme.hasCustomColor) {
      return profileTheme.currentPreset;
    }
    if (_isUser && _peerColorPreset != null) {
      return _peerColorPreset;
    }
    return null;
  }

  Color _getStatusColor(
    BuildContext context,
    ProfileColorPreset? activePreset,
    Color fallbackColor,
  ) {
    if (activePreset != null) {
      return activePreset.statusColor;
    }
    if (_isUser && _isOnline) {
      return const Color(0xFF34C759);
    }
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.65)
        : const Color(0xFF6C6C70);
  }

  // ============================================================
  // Динамические круглые кнопки быстрых действий (3–5 кнопок, iconoir)
  // ============================================================

  List<ProfileActionButtonItem> _buildQuickActionButtons(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    if (_isSelf) {
      return [
        ProfileActionButtonItem(
          iconBuilder: (color, size) =>
              iconoir.Camera(color: color, width: size, height: size),
          label: _tr(l10n, 'profile_choose_photo', 'Фото'),
          onTap: _pickImage,
        ),
        ProfileActionButtonItem(
          iconBuilder: (color, size) =>
              iconoir.EditPencil(color: color, width: size, height: size),
          label: _tr(l10n, 'profile_edit_btn', 'Изменить'),
          onTap: _openEditProfile,
        ),
        ProfileActionButtonItem(
          iconBuilder: (color, size) =>
              iconoir.Palette(color: color, width: size, height: size),
          label: _tr(l10n, 'profile_menu_change_color', 'Цвет'),
          onTap: _openColorSettings,
        ),
      ];
    }

    if (_isUser) {
      return [
        ProfileActionButtonItem(
          iconBuilder: (color, size) =>
              iconoir.ChatBubble(color: color, width: size, height: size),
          label: _tr(l10n, 'chat_title', 'Чат'),
          onTap: _openOrReturnToChat,
        ),
        ProfileActionButtonItem(
          iconBuilder: (color, size) =>
              iconoir.Phone(color: color, width: size, height: size),
          label: _tr(l10n, 'call', 'Звонок'),
          onTap: widget.onVoiceCall ??
              () => _showToast(_tr(l10n, 'call_not_supported', 'Звонки скоро появятся')),
        ),
        ProfileActionButtonItem(
          iconBuilder: (color, size) =>
              iconoir.VideoCamera(color: color, width: size, height: size),
          label: _tr(l10n, 'video', 'Видео'),
          onTap: widget.onVideoCall ??
              () => _showToast(_tr(
                  l10n, 'video_call_not_supported', 'Видеозвонки скоро появятся')),
        ),
        ProfileActionButtonItem(
          iconBuilder: (color, size) => _isMuted
              ? iconoir.BellOff(color: color, width: size, height: size)
              : iconoir.Bell(color: color, width: size, height: size),
          label: _tr(l10n, _isMuted ? 'chat_unmute' : 'chat_mute', 'Звук'),
          onTap: _toggleMute,
        ),
      ];
    }

    if (_isGroup) {
      return [
        ProfileActionButtonItem(
          iconBuilder: (color, size) =>
              iconoir.ChatBubble(color: color, width: size, height: size),
          label: _tr(l10n, 'chat_title', 'Чат'),
          onTap: () => Navigator.maybePop(context),
        ),
        ProfileActionButtonItem(
          iconBuilder: (color, size) => _isMuted
              ? iconoir.BellOff(color: color, width: size, height: size)
              : iconoir.Bell(color: color, width: size, height: size),
          label: _tr(l10n, _isMuted ? 'chat_unmute' : 'chat_mute', 'Звук'),
          onTap: _toggleMute,
        ),
        ProfileActionButtonItem(
          iconBuilder: (color, size) =>
              iconoir.Search(color: color, width: size, height: size),
          label: _tr(l10n, 'search', 'Поиск'),
          onTap: _handleSearchInChat,
        ),
        if (_canAddGroupMembers)
          ProfileActionButtonItem(
            iconBuilder: (color, size) =>
                iconoir.UserPlus(color: color, width: size, height: size),
            label: _tr(l10n, 'group_add_members', 'Добавить'),
            onTap: _showAddMemberDialog,
          ),
        if (_canEditGroupOrChannel)
          ProfileActionButtonItem(
            iconBuilder: (color, size) =>
                iconoir.EditPencil(color: color, width: size, height: size),
            label: _tr(l10n, 'profile_edit_btn', 'Изменить'),
            onTap: _openEditGroupOrChannel,
          ),
      ];
    }

    // Channel (4–5 кнопок)
    return [
      ProfileActionButtonItem(
        iconBuilder: (color, size) =>
            iconoir.ChatBubble(color: color, width: size, height: size),
        label: _tr(l10n, 'channel', 'Канал'),
        onTap: () => Navigator.maybePop(context),
      ),
      ProfileActionButtonItem(
        iconBuilder: (color, size) => _isMuted
            ? iconoir.BellOff(color: color, width: size, height: size)
            : iconoir.Bell(color: color, width: size, height: size),
        label: _tr(l10n, _isMuted ? 'chat_unmute' : 'chat_mute', 'Звук'),
        onTap: _toggleMute,
      ),
      ProfileActionButtonItem(
        iconBuilder: (color, size) =>
            iconoir.Search(color: color, width: size, height: size),
        label: _tr(l10n, 'search', 'Поиск'),
        onTap: _handleSearchInChat,
      ),
      ProfileActionButtonItem(
        iconBuilder: (color, size) =>
            iconoir.ShareIos(color: color, width: size, height: size),
        label: _tr(l10n, 'share', 'Поделиться'),
        onTap: _copyProfileLink,
      ),
      if (_canEditGroupOrChannel)
        ProfileActionButtonItem(
          iconBuilder: (color, size) =>
              iconoir.EditPencil(color: color, width: size, height: size),
          label: _tr(l10n, 'profile_edit_btn', 'Изменить'),
          onTap: _openEditGroupOrChannel,
        ),
    ];
  }

  // ============================================================
  // Список вкладок (разделов) для текущего типа профиля
  // ============================================================

  List<ProfileSectionItem> _buildSections(AppLocalizations l10n) {
    final mediaItem = ProfileSectionItem(
      type: ProfileSectionType.media,
      label: _tr(l10n, 'profile_tab_media', 'Медиа'),
      count: _mediaMessages.length,
    );
    final filesItem = ProfileSectionItem(
      type: ProfileSectionType.files,
      label: _tr(l10n, 'profile_tab_files', 'Файлы'),
      count: _fileMessages.length,
    );
    final linksItem = ProfileSectionItem(
      type: ProfileSectionType.links,
      label: _tr(l10n, 'profile_tab_links', 'Ссылки'),
      count: _linkMessages.length,
    );
    final voiceItem = ProfileSectionItem(
      type: ProfileSectionType.voice,
      label: _tr(l10n, 'profile_tab_voice', 'Голосовые'),
      count: _voiceMessages.length,
    );
    final giftsItem = ProfileSectionItem(
      type: ProfileSectionType.gifts,
      label: _tr(l10n, 'profile_tab_gifts', 'Подарки'),
      count: 0,
    );
    final wallItem = ProfileSectionItem(
      type: ProfileSectionType.wall,
      label: _tr(l10n, 'profile_tab_wall', 'Стена'),
      count: 0,
    );

    if (_isGroup) {
      return [
        ProfileSectionItem(
          type: ProfileSectionType.members,
          label: _tr(l10n, 'group_info_members_section', 'Участники'),
          count: _members.isNotEmpty ? _members.length : _memberCount,
        ),
        giftsItem,
        mediaItem,
        filesItem,
        linksItem,
        voiceItem,
      ];
    }

    if (_isChannel) {
      return [
        giftsItem,
        mediaItem,
        filesItem,
        linksItem,
        voiceItem,
      ];
    }

    // Self & Peer User
    return [
      wallItem,
      giftsItem,
      mediaItem,
      filesItem,
      linksItem,
      voiceItem,
    ];
  }

  void _selectSection(int index) {
    if (_selectedSectionIndex == index) return;
    setState(() {
      _selectedSectionIndex = index;
    });
  }

  // ============================================================
  // Действия профиля и меню
  // ============================================================

  void _showToast(String message, {Widget? iconWidget}) {
    if (!mounted) return;
    GlassToastService().show(
      context,
      message,
      iconWidget: iconWidget,
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _openOrReturnToChat() async {
    HapticUtils.tap();
    if (widget.chatId != null && widget.chatId!.isNotEmpty) {
      Navigator.maybePop(context);
      return;
    }
    if (_resolvedChatId != null && _resolvedChatId!.isNotEmpty) {
      Navigator.push(
        context,
        SwipeBackPageRoute(
          builder: (_) => PrivateChatScreen(
            chatId: _resolvedChatId!,
            otherUserId: widget.userId,
            otherUserName: _getDisplayName(),
            otherUserAvatar: _avatarUrl,
            otherUserOnline: _isOnline,
          ),
        ),
      );
      return;
    }
    if (widget.userId != null && widget.userId!.isNotEmpty) {
      final res = await ChatService.createChat(
        chatType: 'private',
        participantIds: [widget.userId!],
      );
      if (res['success'] == true && res['chat'] is Chat && mounted) {
        final cid = (res['chat'] as Chat).id;
        _resolvedChatId = cid;
        Navigator.push(
          context,
          SwipeBackPageRoute(
            builder: (_) => PrivateChatScreen(
              chatId: cid,
              otherUserId: widget.userId,
              otherUserName: _getDisplayName(),
              otherUserAvatar: _avatarUrl,
              otherUserOnline: _isOnline,
            ),
          ),
        );
      }
    }
  }

  void _toggleMute() {
    HapticUtils.selection();
    final cid = _resolvedChatId;
    if (cid != null && cid.isNotEmpty) {
      ChatActionsHelper.toggleMute(
        chatId: cid,
        currentMuted: _isMuted,
        onMuteChanged: (val) async {
          if (mounted) setState(() => _isMuted = val);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('muted_chat_$cid', val);
        },
      );
    } else {
      setState(() => _isMuted = !_isMuted);
    }
  }

  void _handleSearchInChat() {
    HapticUtils.tap();
    if (widget.onSearchInChat != null) {
      Navigator.maybePop(context);
      widget.onSearchInChat!();
      return;
    }
    final cid = _resolvedChatId;
    if (cid != null && cid.isNotEmpty) {
      ChatActionsHelper.openSearch(
        context: context,
        chatId: cid,
        chatName: _getDisplayName(),
      );
    }
  }

  Future<void> _handleClearHistory() async {
    final cid = _resolvedChatId;
    if (cid == null || cid.isEmpty) return;
    await ChatActionsHelper.showClearHistoryDialog(
      context: context,
      chatId: cid,
      onHistoryCleared: () {
        if (mounted) {
          setState(() {
            _mediaMessages.clear();
            _fileMessages.clear();
            _linkMessages.clear();
            _voiceMessages.clear();
          });
        }
      },
    );
  }

  Future<void> _handleBlockToggle() async {
    final uid = widget.userId;
    if (uid == null || uid.isEmpty) return;
    HapticUtils.tap();
    final l10n = context.l10n;
    try {
      final token = await AuthService.getToken();
      if (token == null) return;
      final dio = Dio();
      if (_isBlocked) {
        await dio.delete(
          '${AppConfig.baseUrl}/api/security/blocked/$uid',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        if (mounted) {
          setState(() => _isBlocked = false);
          _showToast(_tr(l10n, 'profile_user_unblocked', 'Пользователь разблокирован'));
        }
      } else {
        await dio.post(
          '${AppConfig.baseUrl}/api/security/blocked',
          data: {'user_id': uid},
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        if (mounted) {
          setState(() => _isBlocked = true);
          _showToast(_tr(l10n, 'profile_user_blocked', 'Пользователь заблокирован'));
        }
      }
    } catch (e) {
      if (mounted) {
        _showToast(_tr(
          l10n,
          'profile_block_status_error',
          'Не удалось изменить статус блокировки',
        ));
      }
    }
  }

  Future<void> _handleDeleteOrLeaveChat() async {
    final cid = _resolvedChatId;
    if (cid == null || cid.isEmpty) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = context.l10n;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        title: Text(
          _isGroup
              ? _tr(l10n, 'profile_leave_group_title', 'Покинуть группу?')
              : (_isChannel
                  ? _tr(l10n, 'profile_leave_channel_title', 'Покинуть канал?')
                  : _tr(l10n, 'profile_delete_chat_title', 'Удалить чат?')),
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: Text(
          _isGroup || _isChannel
              ? _tr(
                  l10n,
                  'profile_leave_confirm_message',
                  'Вы уверены, что хотите выйти?',
                )
              : _tr(
                  l10n,
                  'profile_delete_chat_confirm_message',
                  'Чат и вся переписка будут удалены.',
                ),
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_tr(l10n, 'profile_cancel', 'Отмена')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              _isGroup || _isChannel
                  ? _tr(l10n, 'profile_leave_action', 'Покинуть')
                  : _tr(l10n, 'profile_delete_action', 'Удалить'),
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      final token = await AuthService.getToken();
      final dio = Dio();
      await dio.delete(
        '${AppConfig.baseUrl}/api/chats/$cid',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      await AppDatabase().deleteChat(cid);
      await AppDatabase().deleteMessagesForChat(cid);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (_) {
      if (mounted) {
        _showToast(_tr(l10n, 'profile_delete_chat_error', 'Ошибка при удалении чата'));
      }
    }
  }

  Future<void> _openEditGroupOrChannel() async {
    final cid = _resolvedChatId;
    if (cid == null || cid.isEmpty) return;
    HapticUtils.tap();

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      SwipeBackPageRoute(
        builder: (_) => EditGroupChannelScreen(
          chatId: cid,
          isChannel: _isChannel,
          initialName: _getDisplayName(),
          initialDescription: _bio ?? '',
          initialAvatarUrl: _avatarUrl,
          initialIsPublic: _isPublic,
          initialHistoryForNew: _historyForNew,
          initialSlowModeInterval: _slowModeInterval,
          inviteLink: _inviteLink,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        if (result['name'] != null) {
          _nameController.text = result['name'].toString();
        }
        if (result['description'] != null) {
          _bio = result['description'].toString();
        }
        if (result['avatar_url'] != null) {
          final url = result['avatar_url'].toString();
          _avatarUrl = url;
          if (url.isNotEmpty && !_avatarUrls.contains(url)) {
            _avatarUrls.insert(0, url);
          }
        }
        if (result['is_public'] is bool) {
          _isPublic = result['is_public'] as bool;
        }
        if (result['history_for_new'] is bool) {
          _historyForNew = result['history_for_new'] as bool;
        }
        if (result['slow_mode_interval'] is int) {
          _slowModeInterval = result['slow_mode_interval'] as int;
        }
      });
      widget.onUpdate?.call();
    }
  }

  Future<void> _showAddMemberDialog() async {
    final cid = _resolvedChatId;
    if (cid == null || cid.isEmpty) return;
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = context.l10n;

    final query = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        title: Text(
          _tr(l10n, 'profile_add_member_title', 'Добавить участника'),
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            hintText: _tr(
              l10n,
              'profile_add_member_hint',
              'Введите @username или ID пользователя',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_tr(l10n, 'profile_cancel', 'Отмена')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(_tr(l10n, 'common_add', 'Добавить')),
          ),
        ],
      ),
    );

    if (query == null || query.isEmpty || !mounted) return;
    try {
      final token = await AuthService.getToken();
      final dio = Dio();
      String targetUserId = query.replaceFirst('@', '');

      // Если введён username — ищем пользователя через поиск
      final searchResp = await dio.get(
        '${AppConfig.baseUrl}/api/users/search',
        queryParameters: {'q': targetUserId},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (searchResp.statusCode == 200 && searchResp.data is Map) {
        final users = searchResp.data['users'] as List?;
        if (users != null && users.isNotEmpty) {
          targetUserId = (users.first['id'] ?? users.first['user_id']).toString();
        }
      }

      await dio.post(
        '${AppConfig.baseUrl}/api/chats/$cid/members',
        data: {'user_id': targetUserId},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      await _loadGroupOrChannelProfile();
      if (mounted) {
        _showToast(_tr(l10n, 'profile_member_added', 'Участник добавлен'));
      }
    } catch (_) {
      if (mounted) {
        _showToast(
            _tr(l10n, 'profile_member_add_error', 'Не удалось добавить участника'));
      }
    }
  }

  Future<void> _handleToggleMemberRole(ProfileMemberItem member) async {
    final cid = _resolvedChatId;
    if (cid == null || cid.isEmpty) return;
    final newRole = member.role == 'admin' ? 'member' : 'admin';
    final l10n = context.l10n;
    try {
      final token = await AuthService.getToken();
      final dio = Dio();
      await dio.put(
        '${AppConfig.baseUrl}/api/chats/$cid/members/${member.userId}/role',
        data: {'role': newRole},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      await _loadGroupOrChannelProfile();
      if (mounted) {
        _showToast(newRole == 'admin'
            ? _tr(l10n, 'profile_member_promoted_admin', 'Назначен администратором')
            : _tr(
                l10n,
                'profile_member_demoted_admin',
                'Права администратора сняты',
              ));
      }
    } catch (_) {
      if (mounted) {
        _showToast(_tr(l10n, 'profile_member_role_error', 'Не удалось изменить роль'));
      }
    }
  }

  Future<void> _handleRemoveMember(ProfileMemberItem member) async {
    final cid = _resolvedChatId;
    if (cid == null || cid.isEmpty) return;
    final l10n = context.l10n;
    try {
      final token = await AuthService.getToken();
      final dio = Dio();
      await dio.delete(
        '${AppConfig.baseUrl}/api/chats/$cid/members/${member.userId}',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      setState(() {
        _members.removeWhere((m) => m.userId == member.userId);
        if (_memberCount > 0) _memberCount--;
      });
      if (mounted) {
        final tmpl = _tr(
          l10n,
          'profile_member_removed',
          '{name} удалён(а) из чата',
        );
        _showToast(tmpl.replaceAll('{name}', member.displayName));
      }
    } catch (_) {
      if (mounted) {
        _showToast(
            _tr(l10n, 'profile_member_remove_error', 'Не удалось удалить участника'));
      }
    }
  }

  void _handleJumpToMessage(DbMessage msg) {
    final targetMsgId = msg.serverId ?? msg.localId;
    if (widget.onJumpToMessageId != null) {
      Navigator.maybePop(context);
      widget.onJumpToMessageId!(targetMsgId);
      return;
    }

    final cid = msg.chatId;
    if (_isGroup) {
      Navigator.push(
        context,
        SwipeBackPageRoute(
          builder: (_) => GroupChatScreen(
            chatId: cid,
            groupName: _getDisplayName(),
            initialMessageId: targetMsgId,
          ),
        ),
      );
    } else if (_isChannel) {
      Navigator.push(
        context,
        SwipeBackPageRoute(
          builder: (_) => ChannelScreen(
            channelId: cid,
            channelName: _getDisplayName(),
            channelAvatar: _avatarUrl,
            highlightMessageId: targetMsgId,
          ),
        ),
      );
    } else {
      final l10n = context.l10n;
      Navigator.push(
        context,
        SwipeBackPageRoute(
          builder: (_) => PrivateChatScreen(
            chatId: cid,
            otherUserId: _isSelf ? null : widget.userId,
            otherUserName: _isSelf
                ? _tr(l10n, 'profile_saved_messages', 'Избранное')
                : _getDisplayName(),
            otherUserAvatar: _avatarUrl,
            initialMessageId: targetMsgId,
          ),
        ),
      );
    }
  }

  Future<void> _showMusicDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = context.l10n;
    final titleCtrl = TextEditingController(text: _musicTitle ?? '');
    final authorCtrl = TextEditingController(text: _musicAuthor ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        title: Text(
          _tr(l10n, 'profile_menu_choose_music', 'Музыка в профиле'),
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                labelText:
                    _tr(l10n, 'profile_music_track_title', 'Название трека'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: authorCtrl,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                labelText:
                    _tr(l10n, 'profile_music_track_artist', 'Исполнитель'),
              ),
            ),
          ],
        ),
        actions: [
          if (_musicTitle != null && _musicTitle!.isNotEmpty)
            TextButton(
              onPressed: () {
                titleCtrl.clear();
                authorCtrl.clear();
                Navigator.pop(ctx, true);
              },
              child: Text(
                _tr(l10n, 'profile_delete_action', 'Удалить'),
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_tr(l10n, 'profile_cancel', 'Отмена')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_tr(l10n, 'profile_save', 'Сохранить')),
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      final newTitle = titleCtrl.text.trim();
      final newAuthor = authorCtrl.text.trim();
      final prefs = await SharedPreferences.getInstance();
      final uid = _accountManager.currentAccount?.userId ?? 'default';
      if (newTitle.isEmpty) {
        await prefs.remove('${uid}_profile_music_title');
        await prefs.remove('${uid}_profile_music_author');
      } else {
        await prefs.setString('${uid}_profile_music_title', newTitle);
        await prefs.setString('${uid}_profile_music_author', newAuthor);
      }
      setState(() {
        _musicTitle = newTitle.isEmpty ? null : newTitle;
        _musicAuthor = newAuthor.isEmpty ? null : newAuthor;
      });
    }
  }

  // ============================================================
  // Анимация расширения аватарки
  // ============================================================

  void _animateToExpand(double target, {double velocity = 0.0}) {
    final willExpand = target >= 0.5;
    if (willExpand != _isAvatarExpanded) {
      HapticUtils.selection();
    }
    _isAvatarExpanded = willExpand;
    _rawExpandDrag = 0.0;
    _rawCollapseDrag = 0.0;
    _expandPreviewBaseFactor = 0.0;
    if (willExpand) {
      _collapseVisualShift = 0.0;
      _collapseSnapStartShift = 0.0;
    }

    final mass = target == 1.0 ? 0.98 : 0.98;
    final stiffness = target == 1.0 ? 380.0 : 350.0;

    final simulation = SpringSimulation(
      SpringDescription.withDampingRatio(
        mass: mass,
        stiffness: stiffness,
        ratio: 0.97,
      ),
      _expandController.value,
      target,
      velocity / 550.0,
      tolerance: const Tolerance(distance: 0.005, velocity: 0.01),
    );
    _expandController.animateWith(simulation).then((_) {
      if (mounted && !_expandController.isAnimating) {
        setState(() {
          _expandFactor = target;
          _expandController.value = target;
          if (target == 0.0) {
            _collapseSnapStartShift = 0.0;
            _expandPreviewBaseFactor = 0.0;
            _currentAvatarIndex = 0;
          }
        });
      }
    });
  }

  /// Переход аватарки в круглую форму после накопления энергии пружины и пересечения порога:
  /// - если палец удерживает экран (`holdAtCircle == true`), пружина доводит аватарку только до момента,
  ///   когда она становится полностью круглой (`_collapseCircleHoldFactor = 0.38`);
  /// - если палец отпущен (`holdAtCircle == false`), пружина сразу доводит анимацию до конца (`0.0`).
  void _triggerAutoCollapse({
    double velocity = 0.0,
    bool holdAtCircle = false,
  }) {
    HapticUtils.selection();
    _isAvatarExpanded = false;
    _isCollapseHoldingOnFinger = holdAtCircle;
    _postThresholdCollapseDrag = 0.0;
    _expandPreviewBaseFactor = holdAtCircle ? _collapseCircleHoldFactor : 0.0;
    _collapseSnapStartShift = _collapseVisualShift;
    _rawCollapseDrag = 0.0;
    _collapseVisualShift = 0.0;
    _rawExpandDrag = 0.0;

    final targetFactor = holdAtCircle ? _collapseCircleHoldFactor : 0.0;

    final simulation = SpringSimulation(
      SpringDescription.withDampingRatio(
        mass: 0.92,
        stiffness: 430.0,
        ratio: 0.98,
      ),
      _expandController.value,
      targetFactor,
      math.min(-1.25, velocity / 550.0),
      tolerance: const Tolerance(distance: 0.005, velocity: 0.01),
    );
    _expandController.animateWith(simulation).then((_) {
      if (mounted && !_expandController.isAnimating && !_isAvatarExpanded) {
        setState(() {
          _expandFactor = targetFactor;
          _expandController.value = targetFactor;
          if (targetFactor == 0.0) {
            _currentAvatarIndex = 0;
            _collapseSnapStartShift = 0.0;
            _expandPreviewBaseFactor = 0.0;
            _isCollapseHoldingOnFinger = false;
          }
        });
      }
    });
  }

  /// Доводит сворачивание аватарки до самого конца (`0.0`) при отпускании пальца.
  /// Если палец был отпущен прямо во время первой фазы анимации (`1.0 -> 0.38`),
  /// сохраняет текущую скорость пружины (`_expandController.velocity`) для бесшовного движения.
  void _finishCollapseToZero({double velocity = 0.0}) {
    _isCollapseHoldingOnFinger = false;
    _postThresholdCollapseDrag = 0.0;
    _expandPreviewBaseFactor = 0.0;
    _rawExpandDrag = 0.0;

    final currentVel = _expandController.isAnimating
        ? math.min(_expandController.velocity, velocity / 550.0)
        : math.min(-0.85, velocity / 550.0);

    final simulation = SpringSimulation(
      SpringDescription.withDampingRatio(
        mass: 0.92,
        stiffness: 430.0,
        ratio: 0.98,
      ),
      _expandController.value,
      0.0,
      currentVel,
      tolerance: const Tolerance(distance: 0.005, velocity: 0.01),
    );
    _expandController.animateWith(simulation).then((_) {
      if (mounted && !_expandController.isAnimating && !_isAvatarExpanded) {
        setState(() {
          _expandFactor = 0.0;
          _expandController.value = 0.0;
          _collapseSnapStartShift = 0.0;
          _expandPreviewBaseFactor = 0.0;
          _currentAvatarIndex = 0;
        });
      }
    });
  }

  double _computeCollapseVisualShift(double rawDrag) {
    final u = (rawDrag / _collapseThreshold).clamp(0.0, 1.0);
    // Нелинейное замедление перед порогом (пружина накапливает энергию)
    return _maxCollapseTensionShift * (1.0 - math.pow(1.0 - u, 2.4));
  }

  // ============================================================
  // Выбор и удаление фото
  // ============================================================

  Future<void> _pickImage() async {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? Colors.white70 : const Color(0xFF0088CC);

    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          title: Text(
            l10n.translate('profile_choose_photo'),
            style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF1C1C1E)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: iconoir.Camera(
                    width: 22, height: 22, color: accentColor),
                title: Text(
                  l10n.translate('profile_camera'),
                  style: TextStyle(
                      color:
                          isDark ? Colors.white70 : const Color(0xFF1C1C1E)),
                ),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: iconoir.MediaImage(
                    width: 22, height: 22, color: accentColor),
                title: Text(
                  l10n.translate('profile_gallery'),
                  style: TextStyle(
                      color:
                          isDark ? Colors.white70 : const Color(0xFF1C1C1E)),
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
      final XFile? pickedFile = await _imagePicker.pickImage(source: source);
      if (pickedFile != null && mounted) {
        final processedPath = await AvatarCropUtils.processAvatar(
          imagePath: pickedFile.path,
          context: context,
        );

        if (processedPath != null && mounted) {
          final account = _accountManager.currentAccount;
          if (account != null) {
            setState(() => _isProcessing = true);
            try {
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
                _showToast(l10n.translate('profile_photo_updated'));
              }
            } finally {
              if (mounted) {
                setState(() => _isProcessing = false);
              }
            }
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      _showToast(l10n
          .translate('profile_photo_error')
          .replaceAll('{error}', e.toString()));
    }
  }

  Future<void> _deleteAvatar() async {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        title: Text(
          l10n.translate('profile_delete_photo_confirm_title'),
          style:
              TextStyle(color: isDark ? Colors.white : const Color(0xFF1C1C1E)),
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
      final isLocalAvatar = topAvatar != null &&
          !kIsWeb &&
          (topAvatar.startsWith('/') ||
              topAvatar.startsWith('file:') ||
              File(topAvatar).existsSync());

      if (isLocalAvatar && account != null) {
        await AvatarSyncService().removeAvatar(account.userId, topAvatar);
        setState(() {
          _avatarUrls.removeAt(0);
          _avatarUrl = _avatarUrls.isNotEmpty ? _avatarUrls.first : null;
          _avatarFile = null;
        });
        await _accountManager.updateAccountProfile(account.userId,
            avatarUrl: _avatarUrl);
        widget.onUpdate?.call();
        if (mounted) {
          _showToast(l10n.translate('profile_photo_deleted'));
        }
        return;
      }

      final avatarIdToDelete =
          _avatarIds.isNotEmpty ? _avatarIds.first : null;
      final result = await AuthService.deleteAvatar(avatarId: avatarIdToDelete);
      if (!mounted) return;

      if (result['success'] == true) {
        setState(() {
          if (_avatarIds.isNotEmpty) _avatarIds.removeAt(0);
          if (_avatarUrls.isNotEmpty) _avatarUrls.removeAt(0);
          _avatarUrl = _avatarUrls.isNotEmpty ? _avatarUrls.first : null;
          _avatarFile = null;
        });

        if (account != null) {
          await _accountManager.updateAccountProfile(account.userId,
              avatarUrl: _avatarUrl);
        }

        widget.onUpdate?.call();
        if (mounted) {
          _showToast(l10n.translate('profile_photo_deleted'));
        }
      } else {
        _showToast(l10n
            .translate('profile_photo_error')
            .replaceAll('{error}', result['message'] ?? ''));
      }
    } catch (e) {
      if (mounted) {
        _showToast(l10n
            .translate('profile_photo_error')
            .replaceAll('{error}', e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showQrCode() {
    final l10n = context.l10n;
    final id = _isSelf
        ? (_accountManager.currentAccount?.userId ?? '')
        : (widget.userId ?? _resolvedChatId ?? '');
    final uname = _usernameController.text.isNotEmpty
        ? _usernameController.text
        : (_inviteLink.isNotEmpty ? _inviteLink : id);

    QrCodeDialog.show(
      context,
      userId: id,
      displayName: _getDisplayName(),
      username: uname,
      avatarUrl: _avatarUrl,
      scanHintLabel: l10n.translate('profile_qr_scan_hint'),
    );
  }

  Future<void> _addBirthdayToCalendar() async {
    final parsed = _birthday;
    if (parsed == null) return;

    final l10n = AppLocalizations.of(context);
    final displayName = _getDisplayName().trim();
    final bdayLabel = l10n != null
        ? _tr(l10n, 'profile_birthday', 'День рождения')
        : 'День рождения';
    final capLabel = bdayLabel.isNotEmpty
        ? '${bdayLabel[0].toUpperCase()}${bdayLabel.substring(1)}'
        : 'День рождения';
    final title = displayName.isNotEmpty ? '$capLabel: $displayName' : capLabel;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var nextBday = DateTime(now.year, parsed.month, parsed.day);
    if (nextBday.isBefore(today)) {
      nextBday = DateTime(now.year + 1, parsed.month, parsed.day);
    }
    final nextDay = nextBday.add(const Duration(days: 1));

    if (!kIsWeb && Platform.isAndroid) {
      try {
        const channel = MethodChannel('app.theaver.messenger/calendar');
        final startUtcMs =
            DateTime.utc(nextBday.year, nextBday.month, nextBday.day)
                .millisecondsSinceEpoch;
        final endUtcMs =
            DateTime.utc(nextDay.year, nextDay.month, nextDay.day)
                .millisecondsSinceEpoch;
        final ok = await channel.invokeMethod<bool>('addBirthdayEvent', {
          'title': title,
          'beginTime': startUtcMs,
          'endTime': endUtcMs,
          'beginTimeMillis': startUtcMs,
          'endTimeMillis': endUtcMs,
          'chooserTitle': capLabel,
        });
        if (ok == true) return;
      } catch (_) {
        // Fallback to .ics intent below if MethodChannel isn't registered yet
      }
    }

    try {
      String fmtDate(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}'
          '${d.month.toString().padLeft(2, '0')}'
          '${d.day.toString().padLeft(2, '0')}';

      final nowUtc = DateTime.now().toUtc();
      final dtStamp = '${fmtDate(nowUtc)}T'
          '${nowUtc.hour.toString().padLeft(2, '0')}'
          '${nowUtc.minute.toString().padLeft(2, '0')}'
          '${nowUtc.second.toString().padLeft(2, '0')}Z';

      final uid =
          'birthday-${widget.userId ?? 'self'}-${parsed.month}-${parsed.day}@theaver.app';
      final cleanTitle =
          title.replaceAll('\r', ' ').replaceAll('\n', ' ').trim();
      final icsContent = [
        'BEGIN:VCALENDAR',
        'VERSION:2.0',
        'PRODID:-//Theaver//Messenger//RU',
        'CALSCALE:GREGORIAN',
        'METHOD:PUBLISH',
        'BEGIN:VEVENT',
        'UID:$uid',
        'DTSTAMP:$dtStamp',
        'DTSTART:${fmtDate(nextBday)}T090000',
        'DTEND:${fmtDate(nextBday)}T100000',
        'RRULE:FREQ=YEARLY',
        'SUMMARY:$cleanTitle',
        'DESCRIPTION:$cleanTitle',
        'STATUS:CONFIRMED',
        'END:VEVENT',
        'END:VCALENDAR',
      ].join('\r\n');

      final tempDir = await getTemporaryDirectory();
      final icsFile = File('${tempDir.path}/birthday.ics');
      await icsFile.writeAsString(icsContent, flush: true);
      await OpenFile.open(icsFile.path, type: 'text/calendar');
    } catch (_) {}
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
          initialBio: _bio,
          initialBirthday: _birthday,
          initialEmail: _emailController.text,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        if (result['name'] != null) _nameController.text = result['name'];
        if (result['surname'] != null) {
          _surnameController.text = result['surname'];
        }
        if (result['username'] != null) {
          _usernameController.text = result['username'];
        }
        if (result['phone'] != null) _phoneController.text = result['phone'];
        if (result.containsKey('bio')) _bio = result['bio'] as String?;
        if (result.containsKey('birthday')) {
          _birthday = result['birthday'] as DateTime?;
        }
      });
      _saveSelfSnapshotToInstantCache();
      widget.onUpdate?.call();

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
    String link;
    if (_inviteLink.isNotEmpty) {
      link = _inviteLink;
    } else {
      final username = _usernameController.text.trim();
      final fallbackId = _isSelf
          ? (_accountManager.currentAccount?.userId ?? '')
          : (widget.userId ?? _resolvedChatId ?? '');
      link = AppConfig.getProfileUrl(
        username.isNotEmpty ? username : fallbackId,
      );
    }

    Clipboard.setData(ClipboardData(text: link));
    HapticUtils.selection();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _showToast(
      context.l10n.translate('profile_link_copied'),
      iconWidget: iconoir.Copy(
        width: 18,
        height: 18,
        color: isDark ? Colors.white : Colors.black87,
      ),
    );
  }

  void _openColorSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ProfileColorScreen(),
      ),
    );
  }

  // ============================================================
  // Обработка жестов и скролла
  // ============================================================

  void _updateSlotMeasurement({
    required double scrollOffset,
    required double topSpacerHeight,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final stackCtx = _profileStackKey.currentContext;
      final slotCtx = _sectionPillSlotKey.currentContext;
      if (stackCtx == null || slotCtx == null) return;

      final stackBox = stackCtx.findRenderObject() as RenderBox?;
      final slotBox = slotCtx.findRenderObject() as RenderBox?;
      if (stackBox == null ||
          slotBox == null ||
          !stackBox.hasSize ||
          !slotBox.hasSize) {
        return;
      }

      final slotTopLeft =
          slotBox.localToGlobal(Offset.zero, ancestor: stackBox);
      final currentScroll =
          _scrollController.hasClients ? _scrollController.offset : scrollOffset;

      final prevPredicted = _hasSlotMeasurement
          ? (_measuredSlotStackY -
              (currentScroll - _measuredAtScrollOffset) +
              (topSpacerHeight - _measuredAtTopSpacerHeight))
          : -1000.0;

      _measuredSlotStackY = slotTopLeft.dy;
      _measuredAtScrollOffset = currentScroll;
      _measuredAtTopSpacerHeight = topSpacerHeight;

      if (!_hasSlotMeasurement ||
          (slotTopLeft.dy - prevPredicted).abs() > 1.0) {
        setState(() {
          _hasSlotMeasurement = true;
        });
      } else {
        _hasSlotMeasurement = true;
      }
    });
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (_isAnyMenuOpen) {
      _closeAllMenus();
      return;
    }

    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final dx = isShiftPressed && event.scrollDelta.dx == 0.0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    final dy = isShiftPressed && event.scrollDelta.dx == 0.0
        ? 0.0
        : event.scrollDelta.dy;

    if (dx.abs() > dy.abs() && dx.abs() > 0.5) {
      _handleHorizontalWheelDelta(dx);
      return;
    }

    if (dy == 0.0) return;
    _scrollByMouseDelta(dy);
  }

  void _handlePointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (_isAnyMenuOpen) {
      _closeAllMenus();
      return;
    }
    final dx = -event.panDelta.dx;
    final dy = -event.panDelta.dy;
    if (dx.abs() > dy.abs() * 1.3 && dx.abs() > 1.0) {
      _handleHorizontalWheelDelta(dx);
      return;
    }
    if (dy != 0.0) {
      _scrollByMouseDelta(dy);
    }
  }

  void _scheduleWheelSnap() {
    _wheelSnapTimer?.cancel();
    _wheelSnapTimer =
        Timer(const Duration(milliseconds: 200), _snapHeaderAfterWheel);
  }

  void _scrollByMouseDelta(double wheelDy) {
    if (wheelDy == 0.0) return;
    _wheelSnapTimer?.cancel();
    _lastWheelDy = wheelDy;

    final currentScroll =
        _scrollController.hasClients ? _scrollController.offset : 0.0;

    // 1. Прокрутка колёсика ВВЕРХ (wheelDy < 0, эквивалент тяги пальцем вниз dy > 0):
    // - сначала возвращаем список к 0, если он прокручен вниз;
    // - в верхней точке (scrollOffset == 0) разворачиваем аватарку из круга в большой квадрат (0.0 -> 1.0).
    if (wheelDy < 0) {
      double remainingUp = -wheelDy;

      if (!_isAvatarExpanded && currentScroll > 0.0) {
        final nextScroll = math.max(0.0, currentScroll - remainingUp);
        final consumed = currentScroll - nextScroll;
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(nextScroll);
        }
        remainingUp -= consumed;
        if (remainingUp <= 0.01) {
          _scheduleWheelSnap();
          return;
        }
      }

      if (_isAvatarExpanded) {
        if (_rawCollapseDrag > 0.0) {
          if (_collapseTensionController.isAnimating) {
            _collapseTensionController.stop();
          }
          _rawCollapseDrag =
              (_rawCollapseDrag - remainingUp).clamp(0.0, _collapseThreshold);
          setState(() {
            _collapseVisualShift =
                _computeCollapseVisualShift(_rawCollapseDrag);
          });
        }
        _scheduleWheelSnap();
        return;
      }

      if (_expandController.isAnimating) {
        _scheduleWheelSnap();
        return;
      }

      _rawExpandDrag += remainingUp;
      if (_rawExpandDrag >= _expandThreshold) {
        _autoExpandedInCurrentGesture = true;
        _animateToExpand(1.0, velocity: 540.0);
        _scheduleWheelSnap();
        return;
      }

      final u = (_rawExpandDrag / _expandThreshold).clamp(0.0, 1.0);
      final previewFactor = (_expandPreviewBaseFactor +
              (_collapseCircleHoldFactor - _expandPreviewBaseFactor) *
                  0.58 *
                  (1.0 - math.pow(1.0 - u, 2.0)))
          .clamp(0.0, _collapseCircleHoldFactor);
      setState(() {
        _expandFactor = previewFactor;
        _expandController.value = previewFactor;
      });
      _scheduleWheelSnap();
      return;
    }

    // 2. Прокрутка колёсика ВНИЗ (wheelDy > 0, эквивалент свайпа пальцем вверх dy < 0):
    // - если аватарка развёрнута в большой квадрат (_isAvatarExpanded), накапливаем натяжение
    //   и сворачиваем её обратно в круг (1.0 -> 0.0);
    // - когда аватарка в круге, прокручиваем основной контент профиля вниз.
    final downDy = wheelDy;

    if (_isAvatarExpanded) {
      if (_collapseTensionController.isAnimating) {
        _collapseTensionController.stop();
      }
      if (_expandController.isAnimating) {
        _expandController.stop();
        _expandFactor = 1.0;
        _expandController.value = 1.0;
      }

      _rawCollapseDrag += downDy;
      final nextShift = _computeCollapseVisualShift(_rawCollapseDrag);

      if (_rawCollapseDrag >= _collapseThreshold) {
        _collapseVisualShift = nextShift;
        _triggerAutoCollapse(
          velocity: -680.0,
          holdAtCircle: false,
        );
        _scheduleWheelSnap();
        return;
      }

      setState(() {
        _expandFactor = 1.0;
        _expandController.value = 1.0;
        _collapseVisualShift = nextShift;
      });
      _scheduleWheelSnap();
      return;
    }

    if (_rawExpandDrag > 0.0 && !_expandController.isAnimating) {
      _rawExpandDrag = (_rawExpandDrag - downDy).clamp(0.0, _expandThreshold);
      final u = (_rawExpandDrag / _expandThreshold).clamp(0.0, 1.0);
      final previewFactor = (_expandPreviewBaseFactor +
              (_collapseCircleHoldFactor - _expandPreviewBaseFactor) *
                  0.58 *
                  (1.0 - math.pow(1.0 - u, 2.0)))
          .clamp(0.0, _collapseCircleHoldFactor);
      setState(() {
        _expandFactor = previewFactor;
        _expandController.value = previewFactor;
      });
      if (_rawExpandDrag > 0.0) {
        _scheduleWheelSnap();
        return;
      }
    }

    // Пока квадратная аватарка заканчивает пружинное сворачивание в круг,
    // ждём завершения перехода, чтобы не было скачка шапки.
    if (_expandController.isAnimating && _expandFactor > 0.05) {
      _scheduleWheelSnap();
      return;
    }
    if (_expandFactor > 0.0) {
      _expandController.stop();
      setState(() {
        _expandFactor = 0.0;
        _expandController.value = 0.0;
        _collapseSnapStartShift = 0.0;
        _expandPreviewBaseFactor = 0.0;
        _currentAvatarIndex = 0;
      });
    }

    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final target = (currentScroll + downDy).clamp(0.0, maxScroll);
      if ((target - currentScroll).abs() > 0.01) {
        _scrollController.jumpTo(target);
      }
    }

    _scheduleWheelSnap();
  }

  void _snapHeaderAfterWheel() {
    if (!mounted || _isPointerDown) return;
    _autoExpandedInCurrentGesture = false;

    if (_isAvatarExpanded) {
      if (_rawCollapseDrag > 0.0) {
        _rawCollapseDrag = 0.0;
        _collapseTensionReturnStart = _collapseVisualShift;
        _collapseTensionController.forward(from: 0.0);
        return;
      }
      if (_expandFactor < 0.999 && !_expandController.isAnimating) {
        _animateToExpand(1.0);
      }
      return;
    }

    if (_rawExpandDrag > 0.0 && !_expandController.isAnimating) {
      _animateToExpand(0.0);
      return;
    }

    if (_expandFactor > 0.001 && !_expandController.isAnimating) {
      _finishCollapseToZero();
      return;
    }

    if (!_scrollController.hasClients) return;
    final currentOffset = _scrollController.offset;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final snapThreshold = math.min(_headerCollapseSnapExtent, maxScroll);

    if (snapThreshold > 1.0 &&
        currentOffset > 0.5 &&
        currentOffset < snapThreshold - 0.5) {
      final double target;
      if (_lastWheelDy > 20.0 && currentOffset >= snapThreshold * 0.22) {
        target = snapThreshold;
      } else if (_lastWheelDy < -20.0 &&
          currentOffset <= snapThreshold * 0.78) {
        target = 0.0;
      } else {
        target = currentOffset >= snapThreshold * 0.45 ? snapThreshold : 0.0;
      }
      if ((target - currentOffset).abs() > 0.5) {
        final durationMs =
            (200 + (target - currentOffset).abs() * 0.40).clamp(200.0, 420.0);
        _scrollController.animateTo(
          target,
          duration: Duration(milliseconds: durationMs.round()),
          curve: Curves.decelerate,
        );
      }
    }
  }

  void _handleHorizontalWheelDelta(double dx) {
    final now = DateTime.now();
    if (_lastHorizontalSwitchTime != null &&
        now.difference(_lastHorizontalSwitchTime!).inMilliseconds < 280) {
      return;
    }
    if ((_horizontalWheelAccum > 0 && dx < 0) ||
        (_horizontalWheelAccum < 0 && dx > 0)) {
      _horizontalWheelAccum = 0.0;
    }
    _horizontalWheelAccum += dx;
    if (_horizontalWheelAccum.abs() >= 36.0) {
      final sections = _buildSections(context.l10n);
      final safeIdx = _selectedSectionIndex.clamp(
          0, math.max<int>(0, sections.length - 1));
      if (_horizontalWheelAccum > 0 && safeIdx < sections.length - 1) {
        _lastHorizontalSwitchTime = now;
        _horizontalWheelAccum = 0.0;
        HapticUtils.selection();
        _selectSection(safeIdx + 1);
      } else if (_horizontalWheelAccum < 0 && safeIdx > 0) {
        _lastHorizontalSwitchTime = now;
        _horizontalWheelAccum = 0.0;
        HapticUtils.selection();
        _selectSection(safeIdx - 1);
      }
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_isAnyMenuOpen) {
        _closeAllMenus();
      } else {
        Navigator.maybePop(context);
      }
      return KeyEventResult.handled;
    }

    final sections = _buildSections(context.l10n);
    final safeIdx =
        _selectedSectionIndex.clamp(0, math.max<int>(0, sections.length - 1));

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (safeIdx > 0) {
        HapticUtils.selection();
        _selectSection(safeIdx - 1);
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (safeIdx < sections.length - 1) {
        HapticUtils.selection();
        _selectSection(safeIdx + 1);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _handleVerticalDragStart(DragStartDetails details) {
    _wheelSnapTimer?.cancel();
    if (_isAnyMenuOpen) {
      _ignoreDragForMenuDismiss = true;
      _closeAllMenus();
      return;
    }
    _ignoreDragForMenuDismiss = false;
    _isPointerDown = true;
    _isCollapseHoldingOnFinger = false;
    _postThresholdCollapseDrag = 0.0;
    if (_collapseTensionController.isAnimating) {
      _collapseTensionController.stop();
    }
    if (_overExpandController.isAnimating) {
      _overExpandController.stop();
    }
    if (_expandController.isAnimating) {
      _expandController.stop();
      if (_isAvatarExpanded && _expandFactor < 0.5) {
        _isAvatarExpanded = false;
      }
    }
    _expandPreviewBaseFactor = _isAvatarExpanded
        ? 0.0
        : _expandFactor.clamp(0.0, _collapseCircleHoldFactor);
    _didTriggerFullscreenOnOverPull = false;
    _autoExpandedInCurrentGesture = false;
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (_ignoreDragForMenuDismiss || _isAnyMenuOpen) return;
    final dy = details.delta.dy;
    if (dy == 0.0) return;

    final screenHeight = MediaQuery.of(context).size.height;
    final currentScroll =
        _scrollController.hasClients ? _scrollController.offset : 0.0;

    // 1. Движение пальца ВНИЗ (dy > 0):
    // - если аватарка свёрнута и список прокручен вниз — сначала возвращаем скролл к 0;
    // - если аватарка свёрнута (или сворачивание ещё не завершено) и мы вверху —
    //   тянем обычную пружину раскрытия до порога _expandThreshold,
    //   после которого аватарка САМА раскрывается до конца (даже если палец удерживает экран);
    // - если аватарка уже раскрыта — делаем over-pull зум и открываем просмотрщик на весь экран.
    if (dy > 0) {
      double remainingDy = dy;

      if (_isCollapseHoldingOnFinger) {
        // 1) Если пользователь уже увёл круглую аватарку выше точки порога (0.38 -> 0.0),
        // при движении пальца вниз сначала доводим круг обратно до порога 0.38.
        if (!_expandController.isAnimating && _postThresholdCollapseDrag > 0.0) {
          final consumed = math.min(remainingDy, _postThresholdCollapseDrag);
          _postThresholdCollapseDrag = (_postThresholdCollapseDrag - consumed)
              .clamp(0.0, _collapseFinishDragDistance);
          remainingDy -= consumed;

          final finishProgress =
              (_postThresholdCollapseDrag / _collapseFinishDragDistance)
                  .clamp(0.0, 1.0);
          final nextFactor = _collapseCircleHoldFactor *
              (1.0 - Curves.easeOutQuad.transform(finishProgress));
          _expandPreviewBaseFactor = nextFactor;
          setState(() {
            _expandFactor = nextFactor;
            _expandController.value = nextFactor;
          });
          if (_postThresholdCollapseDrag > 0.0 && remainingDy <= 0.01) {
            return;
          }
        }

        // 2) При прохождении порога на раскрытие (даже если палец не отпущен) —
        // срабатывает автоматическая доводка до конца анимации раскрытия (1.0),
        // точно так же, как при обычном раскрытии аватарки.
        _rawExpandDrag += remainingDy;
        const double reverseOpenThreshold = 16.0;
        if (_rawExpandDrag >= reverseOpenThreshold) {
          _isCollapseHoldingOnFinger = false;
          _postThresholdCollapseDrag = 0.0;
          _expandPreviewBaseFactor = 0.0;
          _rawExpandDrag = 0.0;
          _autoExpandedInCurrentGesture = true;
          _animateToExpand(1.0, velocity: 540.0);
          return;
        }
        return;
      }

      if (!_isAvatarExpanded && currentScroll > 0.0) {
        final nextScroll = math.max(0.0, currentScroll - remainingDy);
        final consumed = currentScroll - nextScroll;
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(nextScroll);
        }
        remainingDy -= consumed;
        if (remainingDy <= 0.01) {
          return;
        }
      }

      if (_isAvatarExpanded) {
        // Если пользователь сначала немного потянул вверх (накопил натяжение сворачивания),
        // а затем повёл палец обратно вниз — плавно ослабляем натяжение пружины.
        if (_rawCollapseDrag > 0.0) {
          _rawCollapseDrag =
              (_rawCollapseDrag - remainingDy).clamp(0.0, _collapseThreshold);
          setState(() {
            _collapseVisualShift =
                _computeCollapseVisualShift(_rawCollapseDrag);
          });
          return;
        }

        // Если аватарка только что сама раскрылась в текущем жесте или ещё анимируется —
        // не запускаем мгновенно полноэкранный зум до следующего жеста.
        if (_autoExpandedInCurrentGesture || _expandController.isAnimating) {
          return;
        }

        if (_expandFactor >= 0.98) {
          if (_didTriggerFullscreenOnOverPull) return;
          _overExpandController.stop();

          final screenWidth = MediaQuery.of(context).size.width;
          final maxPullDistance =
              math.max(120.0, (screenHeight - screenWidth) / 2.0);
          final overDelta = remainingDy / maxPullDistance;
          final nextOver = (_overExpandProgress + overDelta).clamp(0.0, 1.0);

          setState(() {
            _expandFactor = 1.0;
            _expandController.value = 1.0;
            _overExpandProgress = nextOver;
          });

          if (nextOver >= 0.42 && !_didTriggerFullscreenOnOverPull) {
            _didTriggerFullscreenOnOverPull = true;
            HapticUtils.impact();
            _openFullAvatarViewer(fromOverPull: true);
          }
          return;
        }
      }

      // Аватарка свёрнута: накапливаем движение вниз до порога _expandThreshold.
      // Если уже идёт автоматическая анимация — не перебиваем её.
      if (_expandController.isAnimating) {
        return;
      }

      _rawExpandDrag += remainingDy;
      if (_rawExpandDrag >= _expandThreshold) {
        // Порог пройден — аватарка САМА раскрывается до конца, даже если палец на экране!
        _autoExpandedInCurrentGesture = true;
        _animateToExpand(1.0, velocity: 540.0);
        return;
      }

      final u = (_rawExpandDrag / _expandThreshold).clamp(0.0, 1.0);
      final previewFactor = (_expandPreviewBaseFactor +
              (_collapseCircleHoldFactor - _expandPreviewBaseFactor) *
                  0.58 *
                  (1.0 - math.pow(1.0 - u, 2.0)))
          .clamp(0.0, _collapseCircleHoldFactor);
      setState(() {
        _expandFactor = previewFactor;
        _expandController.value = previewFactor;
      });
      return;
    }

    // 2. Движение пальца ВВЕРХ (dy < 0):
    // - сначала убираем over-pull смещение (если было);
    // - если аватарка развёрнута (_isAvatarExpanded):
    //   Фаза А (до порога _collapseThreshold): аватарка НЕ меняет размер (_expandFactor == 1.0),
    //   идёт вверх со скоростью вдвое меньшей движения экрана и замедляется перед порогом
    //   (пружина накапливает энергию).
    //   Фаза Б (при переходе порога): пружина высвобождается и доводит аватарку до круглой формы
    //   (`_collapseCircleHoldFactor = 0.38`), если палец удерживает экран;
    //   при дальнейшем движении пальца вверх анимация завершается полностью (`0.38 -> 0.0`),
    //   а при отпускании пальца — сама доводится до конца (`0.0`).
    if (_overExpandProgress > 0.0 && !_didTriggerFullscreenOnOverPull) {
      final screenWidth = MediaQuery.of(context).size.width;
      final maxPullDistance =
          math.max(120.0, (screenHeight - screenWidth) / 2.0);
      final overDelta = dy / maxPullDistance;
      final nextOver = (_overExpandProgress + overDelta).clamp(0.0, 1.0);
      setState(() {
        _overExpandProgress = nextOver;
      });
      return;
    }

    if (_isAvatarExpanded) {
      if (_expandController.isAnimating) {
        _expandController.stop();
        _expandFactor = 1.0;
        _expandController.value = 1.0;
      }

      _rawCollapseDrag += (-dy);
      final nextShift = _computeCollapseVisualShift(_rawCollapseDrag);

      if (_rawCollapseDrag >= _collapseThreshold) {
        // Порог пройден — пружина срабатывает и доводит аватарку до круглой формы!
        _collapseVisualShift = nextShift;
        _triggerAutoCollapse(
          velocity: -680.0,
          holdAtCircle: _isPointerDown,
        );
        return;
      }

      setState(() {
        _expandFactor = 1.0;
        _expandController.value = 1.0;
        _collapseVisualShift = nextShift;
      });
      return;
    }

    // Если палец удерживается после пересечения порога сворачивания:
    // - пока идёт быстрый переход из квадрата в круг (1.0 -> 0.38), ждём достижения круглой формы;
    // - как только круглая форма (0.38) достигнута, дальнейшее ведение пальцем вверх
    //   плавно доводит анимацию от круглой формы до самого конца (0.38 -> 0.0).
    if (_isCollapseHoldingOnFinger) {
      double upDy = -dy;
      if (_rawExpandDrag > 0.0) {
        final consumed = math.min(upDy, _rawExpandDrag);
        _rawExpandDrag = (_rawExpandDrag - consumed).clamp(0.0, 16.0);
        upDy -= consumed;
        if (upDy <= 0.01) {
          return;
        }
      }

      if (_expandController.isAnimating &&
          _expandFactor > _collapseCircleHoldFactor + 0.015) {
        return;
      }
      if (_expandController.isAnimating) {
        _expandController.stop();
      }

      _postThresholdCollapseDrag = (_postThresholdCollapseDrag + upDy)
          .clamp(0.0, _collapseFinishDragDistance);
      final finishProgress =
          (_postThresholdCollapseDrag / _collapseFinishDragDistance)
              .clamp(0.0, 1.0);
      final nextFactor = _collapseCircleHoldFactor *
          (1.0 - Curves.easeOutQuad.transform(finishProgress));
      _expandPreviewBaseFactor = nextFactor;

      if (_postThresholdCollapseDrag >= _collapseFinishDragDistance ||
          nextFactor <= 0.002) {
        setState(() {
          _expandFactor = 0.0;
          _expandController.value = 0.0;
          _currentAvatarIndex = 0;
          _collapseSnapStartShift = 0.0;
          _isCollapseHoldingOnFinger = false;
          _postThresholdCollapseDrag = 0.0;
          _expandPreviewBaseFactor = 0.0;
          _rawExpandDrag = 0.0;
        });
      } else {
        setState(() {
          _expandFactor = nextFactor;
          _expandController.value = nextFactor;
        });
      }
      return;
    }

    // Если пользователь чуть-чуть потянул свёрнутую аватарку вниз (не дойдя до порога)
    // и тут же ведёт палец обратно вверх — сначала возвращаем предпросмотр к базовой точке.
    if (_rawExpandDrag > 0.0 && !_expandController.isAnimating) {
      _rawExpandDrag = (_rawExpandDrag + dy).clamp(0.0, _expandThreshold);
      final u = (_rawExpandDrag / _expandThreshold).clamp(0.0, 1.0);
      final previewFactor = (_expandPreviewBaseFactor +
              (_collapseCircleHoldFactor - _expandPreviewBaseFactor) *
                  0.58 *
                  (1.0 - math.pow(1.0 - u, 2.0)))
          .clamp(0.0, _collapseCircleHoldFactor);
      setState(() {
        _expandFactor = previewFactor;
        _expandController.value = previewFactor;
      });
      if (_rawExpandDrag > 0.0) {
        return;
      }
    }

    // Аватарка полностью свёрнута — прокручиваем основной список профиля
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final target = (currentScroll - dy).clamp(0.0, maxScroll);
      _scrollController.jumpTo(target);
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    _isPointerDown = false;
    if (_ignoreDragForMenuDismiss || _isAnyMenuOpen) {
      _ignoreDragForMenuDismiss = false;
      _isCollapseHoldingOnFinger = false;
      return;
    }

    final velocity = details.primaryVelocity ?? 0.0;

    if (_overExpandProgress > 0.0) {
      if (!_didTriggerFullscreenOnOverPull &&
          (velocity > 500.0 || _overExpandProgress >= 0.35)) {
        _didTriggerFullscreenOnOverPull = true;
        HapticUtils.impact();
        _openFullAvatarViewer(fromOverPull: true);
      } else if (!_didTriggerFullscreenOnOverPull) {
        _overExpandController.value = _overExpandProgress;
        _overExpandController.reverse();
      }
      _didTriggerFullscreenOnOverPull = false;
      _autoExpandedInCurrentGesture = false;
      return;
    }

    _didTriggerFullscreenOnOverPull = false;
    _autoExpandedInCurrentGesture = false;

    // Если палец отпущен во время анимации сворачивания в круг (1.0 -> 0.38)
    // или после того, как аватарка дошла до круглой формы (0.38) и удерживалась пальцем:
    // - если пользователь смахнул обратно вниз (как при обычном раскрытии) — раскрываем аватарку (1.0);
    // - иначе автоматически доводим анимацию сворачивания до самого конца (0.0).
    if (_isCollapseHoldingOnFinger) {
      if (velocity > 650.0) {
        _isCollapseHoldingOnFinger = false;
        _postThresholdCollapseDrag = 0.0;
        _expandPreviewBaseFactor = 0.0;
        _rawExpandDrag = 0.0;
        _animateToExpand(1.0, velocity: velocity);
      } else {
        _finishCollapseToZero(velocity: velocity);
      }
      return;
    }

    if (_isAvatarExpanded) {
      if (_rawCollapseDrag > 0.0) {
        // Если пользователь резко смахнул вверх — тоже срабатывает сворачивание сразу до конца (0.0)
        if (velocity < -650.0) {
          _triggerAutoCollapse(velocity: velocity, holdAtCircle: false);
        } else {
          // Иначе плавно возвращаем натянутую пружину обратно в исходное развёрнутое положение
          _rawCollapseDrag = 0.0;
          _collapseTensionReturnStart = _collapseVisualShift;
          _collapseTensionController.forward(from: 0.0);
        }
        return;
      }
      if (_expandFactor < 0.999 && !_expandController.isAnimating) {
        _animateToExpand(1.0, velocity: velocity);
      }
      return;
    }

    // Аватарка в свёрнутом состоянии: если был небольшой недотянутый предпросмотр вниз
    if (_rawExpandDrag > 0.0 && !_expandController.isAnimating) {
      if (velocity > 650.0) {
        _animateToExpand(1.0, velocity: velocity);
      } else {
        _animateToExpand(0.0, velocity: velocity);
      }
      return;
    }

    if (_expandFactor > 0.001 && !_expandController.isAnimating) {
      _finishCollapseToZero(velocity: velocity);
      return;
    }

    // Инерция и доводка скролла при свёрнутой аватарке (охватывает аватарку, имя и кнопки быстрых действий)
    if (_scrollController.hasClients) {
      final currentOffset = _scrollController.offset;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final snapThreshold = math.min(_headerCollapseSnapExtent, maxScroll);

      double target = currentOffset;
      if (velocity.abs() > 80.0) {
        target = (currentOffset - velocity * 0.20).clamp(0.0, maxScroll);
      }

      if (snapThreshold > 1.0 &&
          target > 0.5 &&
          target < snapThreshold - 0.5) {
        if (velocity < -240.0) {
          target = snapThreshold;
        } else if (velocity > 240.0) {
          target = 0.0;
        } else {
          target = target >= snapThreshold * 0.45 ? snapThreshold : 0.0;
        }
      }

      if ((target - currentOffset).abs() > 0.5) {
        final durationMs =
            (230 + (target - currentOffset).abs() * 0.45).clamp(230.0, 480.0);
        _scrollController.animateTo(
          target,
          duration: Duration(milliseconds: durationMs.round()),
          curve: Curves.decelerate,
        );
      }
    }
  }

  double _calculateAvatarTopTranslation({
    required double screenWidth,
    required double topOffset,
  }) {
    final progress = _expandFactor.clamp(0.0, 1.0);
    final startCenterY = topOffset + 55.0;
    final endCenterY = screenWidth / 2;

    final currentCenterY = startCenterY +
        (endCenterY - startCenterY) * Curves.easeInOutCubic.transform(progress);
    final currentSize = _calculateCurrentAvatarSize(screenWidth);

    final currentTop = currentCenterY - currentSize / 2;
    return currentTop - topOffset;
  }

  double _calculateCurrentAvatarSize(double screenWidth) {
    return ExpandableAvatar.calculateAvatarSize(screenWidth, _expandFactor);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LiquidGlassProvider>(
      builder: (context, glassProvider, _) {
        final glassEnabled = glassProvider.enabled;
        final isLite = glassProvider.isLite;
        return _buildProfileLayout(
          context,
          isGlass: glassEnabled,
          isLite: isLite,
        );
      },
    );
  }

  Widget _textHeroFlightShuttleBuilder(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final targetWidget = flightDirection == HeroFlightDirection.push
        ? toHeroContext.widget
        : fromHeroContext.widget;
    return Material(
      type: MaterialType.transparency,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: targetWidget,
      ),
    );
  }

  void _openFullAvatarViewer({bool fromOverPull = false}) async {
    final effectiveUrls = <String>[];
    if (_avatarUrls.isNotEmpty) {
      effectiveUrls.addAll(_avatarUrls);
    } else if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      effectiveUrls.add(_avatarUrl!);
    } else if (_avatarFile != null) {
      effectiveUrls.add(_avatarFile!.path);
    }

    if (effectiveUrls.isEmpty) {
      if (_isSelf) {
        _pickImage();
      } else if (_canEditGroupOrChannel) {
        _openEditGroupOrChannel();
      }
      return;
    }

    final currentIndex =
        _currentAvatarIndex.clamp(0, effectiveUrls.length - 1);

    // Если открываем из свёрнутого круга — переключаем тег Hero на внутренний перед пушем маршрута
    if (_expandFactor < 0.85 && !_isAvatarViewerOpen) {
      setState(() {
        _isAvatarViewerOpen = true;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    } else {
      _isAvatarViewerOpen = true;
    }

    if (fromOverPull) {
      // После старта Hero-перелёта плавно возвращаем смещение интерфейса на экране профиля к 0,
      // пока сама аватарка летит в центр полноэкранного просмотрщика.
      Future.delayed(const Duration(milliseconds: 60), () {
        if (mounted) {
          _overExpandController.value = _overExpandProgress;
          _overExpandController.reverse();
        }
      });
    }

    await AvatarGalleryViewer.open(
      context,
      avatarUrls: effectiveUrls,
      initialIndex: currentIndex,
      displayName: _getDisplayName(),
      onChoosePhoto: _isSelf ? _pickImage : null,
      onDelete: _isSelf ? (_) => _deleteAvatar() : null,
      onPageChanged: (index) {
        setState(() {
          _currentAvatarIndex = index;
        });
      },
    );

    if (mounted) {
      setState(() {
        _isAvatarViewerOpen = false;
        if (_expandFactor < 0.5) {
          _currentAvatarIndex = 0;
        }
      });
    }
  }

  // ============================================================
  // Основная раскладка профиля (Liquid Glass & Material)
  // ============================================================

  Widget _buildProfileLayout(
    BuildContext context, {
    required bool isGlass,
    required bool isLite,
  }) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final profileTheme = context.watch<ProfileThemeProvider>();
    final activePreset = _getActiveColorPreset(profileTheme);

    Color backgroundColor =
        isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF5F5F7);
    if (activePreset != null) {
      if (activePreset.isGradient && activePreset.gradientColors != null) {
        backgroundColor = activePreset.gradientColors!.last;
      } else {
        backgroundColor = activePreset.backgroundColor;
      }
    }

    final bool hasColoredTheme = activePreset != null;
    final bool effectiveIsDark = isDark || hasColoredTheme;
    final onSurfaceColor = hasColoredTheme
        ? Colors.white
        : (isDark ? const Color(0xFFE5E5EA) : const Color(0xFF1C1C1E));

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final statusBarHeight = MediaQuery.of(context).padding.top;

    // Шапка расположена ниже полосок-индикаторов фотографий (которые находятся на statusBarHeight + 6.0)
    final headerTopY = statusBarHeight + 14.0;
    const headerHeight = 44.0;
    final topOffset = headerTopY + headerHeight - 12.0;

    final avatarTopTranslation = _calculateAvatarTopTranslation(
      screenWidth: screenWidth,
      topOffset: topOffset,
    );

    final scrollOffset = (_scrollController.hasClients
            ? _scrollController.offset
            : 0.0)
        .clamp(0.0, double.infinity);

    // Смещение преднатяжения пружины при сворачивании:
    // - пока аватарка развёрнута (Фаза А), экран идёт вверх на _collapseVisualShift,
    //   а сама аватарка идёт вверх ВДВОЕ МЕДЛЕННЕЕ (-0.5 * effectiveCollapseShift) без изменения размера;
    // - когда порог пройден (Фаза Б), смещение плавно сходит к 0 вместе с _expandFactor.
    final effectiveCollapseShift = _isAvatarExpanded
        ? _collapseVisualShift
        : (_collapseSnapStartShift * _expandFactor);

    // При потягивании раскрытой аватарки вниз:
    // её верхний край остаётся у верхнего края экрана (avatarTopY = 0),
    // сама аватарка чуть увеличивается на extraOverPullSize,
    // а её нижний край и весь интерфейс под ней смещаются вниз синхронно на extraOverPullSize.
    final extraOverPullSize = 36.0 *
        Curves.easeOutCubic.transform(_overExpandProgress.clamp(0.0, 1.0));

    final effectiveAvatarTranslation = avatarTopTranslation -
        (1.0 - _expandFactor) * scrollOffset -
        0.5 * effectiveCollapseShift;

    final baseAvatarSize = _calculateCurrentAvatarSize(screenWidth);
    final currentSize = baseAvatarSize + extraOverPullSize;
    final avatarTopY = topOffset + effectiveAvatarTranslation;
    final avatarBottomY = avatarTopY + currentSize;

    final blurProgress = ((_expandFactor - 0.38) / 0.62).clamp(0.0, 1.0);
    final blurFactor = Curves.easeOutCubic.transform(blurProgress);

    // Опережение нижнего экрана относительно аватарки при натяжении сворачивания:
    // нижняя граница альфа-растворения и блюра аватарки поднимается синхронно с экраном,
    // чтобы имя пользователя всегда оставалось ниже зоны блюра на 12dp.
    final bottomCollapseOverlap = 0.5 * effectiveCollapseShift;
    final effectiveAvatarBottomY =
        avatarBottomY - bottomCollapseOverlap * blurFactor;

    // Деликатный оптический блюр нижней кромки аватарки (без цветного тинта,
    // т.к. само фото плавно уходит в alpha = 0 через ShaderMask поверх реального градиента)
    final dissolveOverlayHeight = 36.0 * blurFactor;
    final dissolveTopY = effectiveAvatarBottomY - dissolveOverlayHeight;

    final topSpacerHeight = math.max(
      0.0,
      topOffset +
          avatarTopTranslation +
          currentSize -
          effectiveCollapseShift,
    );

    final buttonsCollapseProgress = _expandFactor > 0.0
        ? 0.0
        : (scrollOffset / _headerCollapseSnapExtent).clamp(0.0, 1.0);

    if (!_isLoading) {
      _updateSlotMeasurement(
        scrollOffset: scrollOffset,
        topSpacerHeight: topSpacerHeight,
      );
    }

    final currentSlotY = _hasSlotMeasurement
        ? (_measuredSlotStackY -
            (scrollOffset - _measuredAtScrollOffset) +
            (topSpacerHeight - _measuredAtTopSpacerHeight))
        : (topSpacerHeight + 290.0 - scrollOffset);

    // Капсула разделов останавливается ровно на одном уровне с кнопками "<" и "•••"
    final minPillTopY = headerTopY;
    final pillTopY = math.max(minPillTopY, currentSlotY);

    // Прогресс приближения кнопки "Стена / Медиа / ..." к верхнему краю экрана:
    // карточка информации плавно ускоряется вверх и полностью уходит за верхнюю границу экрана (y < 0),
    // а для строки состояния включается LiquidGlassScrollEdge (затемнение + размытие).
    final double distanceToTopBar = currentSlotY - headerTopY;
    final double pillApproachProgress = _expandFactor > 0.0
        ? 0.0
        : (1.0 - (distanceToTopBar / 150.0)).clamp(0.0, 1.0);
    final double infoCardExitOffset =
        -Curves.easeInQuad.transform(pillApproachProgress) *
            (statusBarHeight + 115.0);
    final double statusBarDimProgress =
        Curves.easeInOutCubic.transform(pillApproachProgress);
    final double statusBarEdgeProgress = math.max(
      blurFactor,
      statusBarDimProgress,
    ).clamp(0.0, 1.0);

    final isPhotoTopLight = _topLuminance > 0.55;
    final targetIconBrightness = _expandFactor > 0.38
        ? (isPhotoTopLight ? Brightness.dark : Brightness.light)
        : (effectiveIsDark ? Brightness.light : Brightness.dark);

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: targetIconBrightness,
      statusBarBrightness: targetIconBrightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
    );

    // Единый цвет иконок для всех кнопок интерфейса (<, •••, быстрые действия, капсула разделов)
    final headerIconColor = effectiveIsDark
        ? Colors.white.withValues(alpha: 0.92)
        : const Color(0xFF1C1C1E);

    final sections = _buildSections(l10n);
    final int safeSectionIdx =
        _selectedSectionIndex.clamp(0, math.max<int>(0, sections.length - 1));

    return PopScope(
      canPop: !_isAnyMenuOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isAnyMenuOpen) {
          _closeAllMenus();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: Scaffold(
          backgroundColor: backgroundColor,
          body: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF0088CC)))
              : Focus(
                  focusNode: _keyboardFocusNode,
                  autofocus: true,
                  onKeyEvent: _handleKeyEvent,
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerSignal: _handlePointerSignal,
                    onPointerPanZoomUpdate: _handlePointerPanZoomUpdate,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragStart: _handleVerticalDragStart,
                      onVerticalDragUpdate: _handleVerticalDragUpdate,
                      onVerticalDragEnd: _handleVerticalDragEnd,
                      child: Stack(
                    key: _profileStackKey,
                    children: [
                      // 1. Основной адаптивный фон экрана
                      Positioned.fill(
                        child: ColoredBox(
                          color: backgroundColor,
                        ),
                      ),

                      // 2. Фиксированный градиент фона (не смещается при скролле экрана профиля)
                      if (activePreset != null &&
                          activePreset.isGradient &&
                          activePreset.gradientColors != null)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: activePreset.gradientColors!,
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ),

                      // 3. Контент профиля (управляется единым вертикальным жестом)
                      SingleChildScrollView(
                        controller: _scrollController,
                        physics: const NeverScrollableScrollPhysics(),
                        child: Column(
                          children: [
                            // Верхний спейсер под аватарку
                            IgnorePointer(
                              child: SizedBox(
                                height: topSpacerHeight,
                                width: double.infinity,
                              ),
                            ),

                            // Имя и статус
                            Padding(
                              padding: const EdgeInsets.only(
                                  top: 12, left: 20, right: 20),
                              child: Opacity(
                                opacity: _expandFactor > 0.0
                                    ? 1.0
                                    : (1.0 - ((scrollOffset - 15.0) / 115.0))
                                        .clamp(0.0, 1.0),
                                child: Column(
                                  children: [
                                    Hero(
                                      tag: 'profile_name_$_heroKey',
                                      flightShuttleBuilder:
                                          _textHeroFlightShuttleBuilder,
                                      child: Material(
                                        type: MaterialType.transparency,
                                        child: Text(
                                          _getDisplayName(),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 23,
                                            fontWeight: FontWeight.w700,
                                            color: onSurfaceColor,
                                            letterSpacing: -0.3,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Hero(
                                      tag: 'profile_status_$_heroKey',
                                      flightShuttleBuilder:
                                          _textHeroFlightShuttleBuilder,
                                      child: Material(
                                        type: MaterialType.transparency,
                                        child: Text(
                                          _getStatusText(l10n),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: _getStatusColor(
                                              context,
                                              activePreset,
                                              const Color(0xFF0088CC)
                                                  .withValues(alpha: 0.85),
                                            ),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Контент под шапкой: кнопки действий, музыка, инфо-панель, слот под капсулу и вкладки
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Column(
                                children: [
                                  // Динамический ряд круглых кнопок быстрых действий (3–5 кнопок)
                                  LiquidGlassProfileButtons(
                                    enabled: isGlass,
                                    isLite: isLite,
                                    hasColoredTheme: hasColoredTheme,
                                    customButtons: _buildQuickActionButtons(
                                        context, l10n),
                                    collapseProgress: buttonsCollapseProgress,
                                    extraFlyUpDistance: statusBarHeight + 76.0,
                                  ),

                                  // Блок информации о пользователе/группе/канале уходит вверх за край экрана
                                  // при приближении кнопки "Стена / Медиа / ..." к верхней шапке
                                  IgnorePointer(
                                    ignoring: pillApproachProgress > 0.6,
                                    child: Transform.translate(
                                      offset: Offset(0, infoCardExitOffset),
                                      child: Column(
                                        children: [
                                          // Компактная капсула музыкального статуса (если задана)
                                          if (_musicTitle != null &&
                                              _musicTitle!
                                                  .trim()
                                                  .isNotEmpty) ...[
                                            const SizedBox(height: 12),
                                            LiquidGlassMusicStatus(
                                              enabled: isGlass,
                                              isLite: isLite,
                                              hasColoredTheme: hasColoredTheme,
                                              trackTitle: _musicTitle,
                                              trackAuthor: _musicAuthor,
                                              onTap: _isSelf
                                                  ? _showMusicDialog
                                                  : null,
                                            ),
                                          ],

                                          const SizedBox(height: 14),

                                          // Чистая инфо-панель без иконок слева
                                          LiquidGlassInfoPanel(
                                            enabled: isGlass,
                                            isLite: isLite,
                                            hasColoredTheme: hasColoredTheme,
                                            phone: _phoneController
                                                    .text.isNotEmpty
                                                ? _phoneController.text
                                                : null,
                                            bio: _bio,
                                            username: _usernameController
                                                    .text.isNotEmpty
                                                ? _usernameController.text
                                                : null,
                                            inviteLink: _inviteLink.isNotEmpty
                                                ? _inviteLink
                                                : null,
                                            birthday: _formatBirthday(
                                                _birthday, l10n),
                                            age: _calculateAge(_birthday)
                                                ?.toString(),
                                            onBirthdayTap: _birthday != null
                                                ? _addBirthdayToCalendar
                                                : null,
                                            onQrCodeTap: (_usernameController
                                                        .text.isNotEmpty ||
                                                    _inviteLink.isNotEmpty ||
                                                    _isSelf)
                                                ? _showQrCode
                                                : null,
                                            phoneLabel: _tr(l10n,
                                                'profile_phone', 'телефон'),
                                            bioLabel: (_isGroup || _isChannel)
                                                ? _tr(
                                                    l10n,
                                                    'group_info_description',
                                                    'описание')
                                                : _tr(l10n, 'profile_bio',
                                                    'о себе'),
                                            usernameLabel: _tr(
                                                l10n,
                                                'profile_username',
                                                'имя пользователя'),
                                            inviteLinkLabel: _tr(
                                                l10n,
                                                'group_info_invite_link',
                                                'ссылка-приглашение'),
                                            birthdayLabel: _tr(
                                                l10n,
                                                'profile_birthday',
                                                'дата рождения'),
                                            ageLabel: _tr(l10n,
                                                'profile_age_years', 'лет'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 16),

                                  // Слот-ориентир для единой капсулы выбора разделов (`ProfileSectionPill`)
                                  SizedBox(
                                    key: _sectionPillSlotKey,
                                    height: 44.0,
                                    width: double.infinity,
                                  ),

                                  const SizedBox(height: 12),

                                  // Контент выбранной вкладки естественной высоты (без искусственного ограничения SizedBox/PageView)
                                  GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onHorizontalDragEnd: (details) {
                                      final vx = details.primaryVelocity ?? 0.0;
                                      if (vx < -280 &&
                                          safeSectionIdx <
                                              sections.length - 1) {
                                        _selectSection(safeSectionIdx + 1);
                                      } else if (vx > 280 &&
                                          safeSectionIdx > 0) {
                                        _selectSection(safeSectionIdx - 1);
                                      }
                                    },
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minHeight: math.max(
                                          340.0,
                                          screenHeight - headerTopY - 56.0,
                                        ),
                                      ),
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 48),
                                        child: AnimatedSwitcher(
                                          duration: const Duration(
                                              milliseconds: 220),
                                          switchInCurve: Curves.easeOutCubic,
                                          switchOutCurve: Curves.easeInCubic,
                                          layoutBuilder: (currentChild,
                                              previousChildren) {
                                            return Stack(
                                              alignment: Alignment.topCenter,
                                              children: <Widget>[
                                                ...previousChildren,
                                                if (currentChild != null)
                                                  currentChild,
                                              ],
                                            );
                                          },
                                          child: KeyedSubtree(
                                            key: ValueKey<ProfileSectionType>(
                                              sections[safeSectionIdx].type,
                                            ),
                                            child: ProfileSectionPageContent(
                                              sectionType:
                                                  sections[safeSectionIdx].type,
                                              glassEnabled: isGlass,
                                              isLite: isLite,
                                              chatId: _resolvedChatId ?? '',
                                              chatType: _isGroup
                                                  ? 'group'
                                                  : (_isChannel
                                                      ? 'channel'
                                                      : 'private'),
                                              chatTitle: _getDisplayName(),
                                              currentUserId: _accountManager
                                                  .currentAccount?.userId,
                                              members: _members,
                                              mediaMessages: _mediaMessages,
                                              fileMessages: _fileMessages,
                                              linkMessages: _linkMessages,
                                              voiceMessages: _voiceMessages,
                                              canAddMembers:
                                                  _canAddGroupMembers,
                                              canManageMembers:
                                                  _canEditGroupOrChannel,
                                              onAddMemberTap:
                                                  _showAddMemberDialog,
                                              onMemberTap: (m) {
                                                Navigator.push(
                                                  context,
                                                  SwipeBackPageRoute(
                                                    builder: (_) =>
                                                        ProfileScreen(
                                                      entityType:
                                                          ProfileEntityType
                                                              .user,
                                                      userId: m.userId,
                                                      initialName:
                                                          m.displayName,
                                                      initialAvatarUrl:
                                                          m.avatarUrl,
                                                      initialIsOnline:
                                                          m.isOnline,
                                                    ),
                                                  ),
                                                );
                                              },
                                              onToggleAdminRole:
                                                  _handleToggleMemberRole,
                                              onRemoveMember:
                                                  _handleRemoveMember,
                                              onJumpToMessage:
                                                  _handleJumpToMessage,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 4. Аватарка с непрерывным морфингом и ShaderMask альфа-растворением нижней кромки
                      Positioned(
                        top: avatarTopY,
                        left: (screenWidth - currentSize) / 2,
                        width: currentSize,
                        height: currentSize,
                        child: IgnorePointer(
                          ignoring: _expandFactor == 0.0 && scrollOffset > 80.0,
                          child: Opacity(
                            opacity: _expandFactor > 0.0
                                ? 1.0
                                : (1.0 - ((scrollOffset - 35.0) / 115.0))
                                    .clamp(0.0, 1.0),
                            child: ExpandableAvatar(
                              pageController: _avatarPageController,
                              initialPage: _currentAvatarIndex,
                              avatarUrls: _avatarUrls,
                              avatarFile: _avatarFile,
                              expandFactor: _expandFactor,
                              overExpandProgress: _overExpandProgress,
                              bottomCollapseOverlap: bottomCollapseOverlap,
                              tintColor: backgroundColor,
                              backgroundColor: backgroundColor,
                              displayName: _getDisplayName(),
                              chatAvatarHeroTag:
                                  (_expandFactor >= 0.85 || _isAvatarViewerOpen)
                                      ? null
                                      : 'profile_avatar_$_heroKey',
                              onTap: _openFullAvatarViewer,
                              onVerticalDragStart: _handleVerticalDragStart,
                              onVerticalDragUpdate: _handleVerticalDragUpdate,
                              onVerticalDragEnd: _handleVerticalDragEnd,
                              onPageChanged: (index) {
                                setState(() {
                                  _currentAvatarIndex = index;
                                });
                                _updateTopLuminance();
                              },
                            ),
                          ),
                        ),
                      ),

                      // 5. Мягкое оптическое размытие нижней зоны альфа-перехода аватарки (LiquidGlassScrollEdge)
                      if (_expandFactor > 0.38 && blurFactor > 0.001)
                        Positioned(
                          top: dissolveTopY,
                          left: 0,
                          right: 0,
                          height: dissolveOverlayHeight,
                          child: LiquidGlassScrollEdge(
                            edge: LiquidGlassEdge.bottom,
                            style: LiquidGlassScrollEdgeStyle.soft,
                            blur: 6.0 * blurFactor,
                            color: Colors.transparent,
                          ),
                        ),

                      // 6. Верхний edge blur + затемнение для строки состояния (LiquidGlassScrollEdge):
                      // работает как при раскрытой квадратной аватарке, так и при приближении капсулы разделов к верху
                      if (statusBarHeight > 0 && statusBarEdgeProgress > 0.005)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: statusBarHeight + 12.0 * statusBarEdgeProgress,
                          child: LiquidGlassScrollEdge(
                            edge: LiquidGlassEdge.top,
                            style: LiquidGlassScrollEdgeStyle.soft,
                            blur: math.max(
                                  context.read<LiquidGlassProvider>().blur,
                                  10.0,
                                ) *
                                statusBarEdgeProgress,
                            color: Colors.black.withValues(
                              alpha: (effectiveIsDark ? 0.36 : 0.20) *
                                  statusBarEdgeProgress,
                            ),
                          ),
                        ),

                      // 6.5. Полноэкранный барьер закрытия открытого меню ("•••" или "Стена / Медиа / ..."):
                      // перехватывает любые тапы и свайпы вне активного открытого меню, закрывает его
                      // и не позволяет сработать никаким элементам под ним.
                      if (_isAnyMenuOpen)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _closeAllMenus,
                            onVerticalDragStart: (_) => _closeAllMenus(),
                            onHorizontalDragStart: (_) => _closeAllMenus(),
                            child: const SizedBox.expand(),
                          ),
                        ),

                      // 7. ЕДИНАЯ кнопка выбора разделов ("Стена / Медиа / ..."),
                      // которая едет вместе со скроллом и останавливается на уровне верхнего бара (headerTopY)
                      Positioned(
                        top: pillTopY,
                        left: 68,
                        right: 68,
                        child: IgnorePointer(
                          ignoring: _isHeaderMenuOpen,
                          child: Center(
                            child: ProfileSectionPill(
                              key: _sectionPillKey,
                              sections: sections,
                              selectedIndex: safeSectionIdx,
                              onSectionSelected: _selectSection,
                              glassEnabled: isGlass,
                              isLite: isLite,
                              hasColoredTheme: hasColoredTheme,
                              onOpenChanged: (isOpen) {
                                if (_isSectionMenuOpen != isOpen) {
                                  setState(() {
                                    _isSectionMenuOpen = isOpen;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ),

                      // 8. Верхняя шапка профиля (Назад | Морфинг-меню •••) на одном уровне headerTopY
                      Positioned(
                        top: headerTopY,
                        left: 0,
                        right: 0,
                        child: _buildProfileHeader(
                          context,
                          l10n,
                          effectiveIsDark,
                          onSurfaceColor,
                          iconColor: headerIconColor,
                          glassEnabled: isGlass,
                          isLite: isLite,
                        ),
                      ),

                      // 9. Индикатор загрузки
                      if (_isProcessing)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.3),
                            child: const Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFF0088CC)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ),
      ),
    );
  }

  // ============================================================
  // Верхняя шапка профиля
  // ============================================================

  Widget _buildProfileHeader(
    BuildContext context,
    AppLocalizations l10n,
    bool isDark,
    Color onSurfaceColor, {
    required Color iconColor,
    required bool glassEnabled,
    required bool isLite,
  }) {
    final menuItems = _buildHeaderMorphMenuItems(context, l10n);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IgnorePointer(
            ignoring: _isAnyMenuOpen,
            child: _RoundHeaderButton(
              iconBuilder: (color, size) => iconoir.NavArrowLeft(
                color: color,
                width: size,
                height: size,
              ),
              iconColor: iconColor,
              isDark: isDark,
              glassEnabled: glassEnabled,
              isLite: isLite,
              onTap: () {
                HapticUtils.tap();
                Navigator.maybePop(context);
              },
            ),
          ),
          IgnorePointer(
            ignoring: _isSectionMenuOpen,
            child: _MorphingHeaderMenuButton(
              key: _headerMenuKey,
              iconColor: iconColor,
              isDark: isDark,
              glassEnabled: glassEnabled,
              isLite: isLite,
              items: menuItems,
              onItemSelected: _handleHeaderMenuAction,
              onOpenChanged: (isOpen) {
                if (_isHeaderMenuOpen != isOpen) {
                  setState(() {
                    _isHeaderMenuOpen = isOpen;
                  });
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  List<_MorphMenuItemData> _buildHeaderMorphMenuItems(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    if (_isSelf) {
      return [
        _MorphMenuItemData(
          id: 'edit_info',
          label: _tr(l10n, 'profile_menu_edit_info', 'Изменить профиль'),
          iconBuilder: (color, size) =>
              iconoir.EditPencil(color: color, width: size, height: size),
        ),
        _MorphMenuItemData(
          id: 'choose_photo',
          label: _tr(l10n, 'profile_menu_choose_photo', 'Выбрать фото'),
          iconBuilder: (color, size) =>
              iconoir.Camera(color: color, width: size, height: size),
        ),
        _MorphMenuItemData(
          id: 'choose_music',
          label: _tr(l10n, 'profile_menu_choose_music', 'Музыка в профиле'),
          iconBuilder: (color, size) =>
              iconoir.MusicDoubleNote(color: color, width: size, height: size),
        ),
        _MorphMenuItemData(
          id: 'change_color',
          label: _tr(l10n, 'profile_menu_change_color', 'Цвет профиля'),
          iconBuilder: (color, size) =>
              iconoir.Palette(color: color, width: size, height: size),
        ),
        _MorphMenuItemData(
          id: 'copy_link',
          label: _tr(l10n, 'profile_menu_copy_link', 'Скопировать ссылку'),
          iconBuilder: (color, size) =>
              iconoir.Link(color: color, width: size, height: size),
        ),
        if (_avatarUrls.isNotEmpty || _avatarUrl != null)
          _MorphMenuItemData(
            id: 'delete_photo',
            label: _tr(l10n, 'profile_delete_photo', 'Удалить фото'),
            isDestructive: true,
            iconBuilder: (color, size) =>
                iconoir.Trash(color: color, width: size, height: size),
          ),
      ];
    }

    if (_isUser) {
      return [
        _MorphMenuItemData(
          id: 'search_chat',
          label: _tr(l10n, 'chat_menu_search_messages', 'Поиск сообщений'),
          iconBuilder: (color, size) =>
              iconoir.Search(color: color, width: size, height: size),
        ),
        _MorphMenuItemData(
          id: 'copy_link',
          label: _tr(l10n, 'profile_menu_copy_link', 'Скопировать ссылку'),
          iconBuilder: (color, size) =>
              iconoir.ShareIos(color: color, width: size, height: size),
        ),
        if (_resolvedChatId != null && _resolvedChatId!.isNotEmpty)
          _MorphMenuItemData(
            id: 'clear_history',
            label: _tr(l10n, 'chat_menu_clear_history', 'Очистить историю'),
            iconBuilder: (color, size) =>
                iconoir.Erase(color: color, width: size, height: size),
          ),
        _MorphMenuItemData(
          id: 'toggle_block',
          label: _isBlocked
              ? _tr(l10n, 'profile_menu_unblock_user', 'Разблокировать')
              : _tr(l10n, 'profile_menu_block_user', 'Заблокировать'),
          isDestructive: !_isBlocked,
          iconBuilder: (color, size) =>
              iconoir.Prohibition(color: color, width: size, height: size),
        ),
        if (_resolvedChatId != null && _resolvedChatId!.isNotEmpty)
          _MorphMenuItemData(
            id: 'delete_chat',
            label: _tr(l10n, 'chat_menu_delete_chat', 'Удалить чат'),
            isDestructive: true,
            iconBuilder: (color, size) =>
                iconoir.Trash(color: color, width: size, height: size),
          ),
      ];
    }

    // Group or Channel
    return [
      if (_canEditGroupOrChannel)
        _MorphMenuItemData(
          id: 'edit_group_channel',
          label: _isChannel
              ? _tr(l10n, 'profile_menu_edit_channel', 'Изменить канал')
              : _tr(l10n, 'profile_menu_edit_group', 'Изменить группу'),
          iconBuilder: (color, size) =>
              iconoir.EditPencil(color: color, width: size, height: size),
        ),
      _MorphMenuItemData(
        id: 'search_chat',
        label: _tr(l10n, 'chat_menu_search_messages', 'Поиск сообщений'),
        iconBuilder: (color, size) =>
            iconoir.Search(color: color, width: size, height: size),
      ),
      _MorphMenuItemData(
        id: 'copy_link',
        label: _tr(l10n, 'profile_menu_copy_link', 'Скопировать ссылку'),
        iconBuilder: (color, size) =>
            iconoir.Link(color: color, width: size, height: size),
      ),
      _MorphMenuItemData(
        id: 'clear_history',
        label: _tr(l10n, 'chat_menu_clear_history', 'Очистить историю'),
        iconBuilder: (color, size) =>
            iconoir.Erase(color: color, width: size, height: size),
      ),
      _MorphMenuItemData(
        id: 'leave_chat',
        label: _isChannel
            ? _tr(l10n, 'profile_menu_leave_channel', 'Покинуть канал')
            : _tr(l10n, 'chat_menu_leave', 'Покинуть группу'),
        isDestructive: true,
        iconBuilder: (color, size) =>
            iconoir.LogOut(color: color, width: size, height: size),
      ),
    ];
  }

  void _handleHeaderMenuAction(String id) {
    switch (id) {
      case 'edit_info':
        _openEditProfile();
        break;
      case 'choose_photo':
        _pickImage();
        break;
      case 'choose_music':
        _showMusicDialog();
        break;
      case 'change_color':
        _openColorSettings();
        break;
      case 'copy_link':
        _copyProfileLink();
        break;
      case 'delete_photo':
        _deleteAvatar();
        break;
      case 'search_chat':
        _handleSearchInChat();
        break;
      case 'clear_history':
        _handleClearHistory();
        break;
      case 'toggle_block':
        _handleBlockToggle();
        break;
      case 'delete_chat':
      case 'leave_chat':
        _handleDeleteOrLeaveChat();
        break;
      case 'edit_group_channel':
        _openEditGroupOrChannel();
        break;
    }
  }

  String _getDisplayName() {
    final name = _nameController.text.trim();
    final surname = _surnameController.text.trim();
    if (name.isEmpty && surname.isEmpty) {
      if (_usernameController.text.isNotEmpty) {
        return '@${_usernameController.text}';
      }
      return widget.initialName ?? '';
    }
    return '$name $surname'.trim();
  }

  int? _calculateAge(DateTime? birthday) {
    if (birthday == null) return null;
    final now = DateTime.now();
    int age = now.year - birthday.year;
    if (now.month < birthday.month ||
        (now.month == birthday.month && now.day < birthday.day)) {
      age--;
    }
    return age >= 0 ? age : null;
  }

  String? _formatBirthday(DateTime? date, AppLocalizations l10n) {
    if (date == null) return null;
    const fallbackMonths = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    final monthIdx = date.month.clamp(1, 12);
    final monthName = _tr(
      l10n,
      'profile_month_$monthIdx',
      fallbackMonths[monthIdx - 1],
    );
    return '${date.day} $monthName ${date.year}';
  }
}

/// Круглая кнопка в шапке профиля с иконкой `iconoir_flutter`.
class _RoundHeaderButton extends StatelessWidget {
  final Widget Function(Color color, double size) iconBuilder;
  final Color iconColor;
  final bool isDark;
  final bool glassEnabled;
  final bool isLite;
  final VoidCallback? onTap;

  const _RoundHeaderButton({
    Key? key,
    required this.iconBuilder,
    required this.iconColor,
    required this.isDark,
    this.glassEnabled = false,
    this.isLite = false,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const size = 44.0;

    if (glassEnabled) {
      final glassProvider = context.watch<LiquidGlassProvider>();
      final glassStyle = glassProvider.createStyle(
        context: context,
        isDarkOverride: isDark,
        isLiteOverride: isLite,
        color: isDark ? const Color(0x33202025) : const Color(0x66FFFFFF),
        refractionIndex: 1.15,
        refractionWidth: 22.0,
        shape: const LiquidGlassShape.roundedRectangle(
          cornerRadius: size / 2,
        ),
      );

      final buttonChild = SizedBox(
        width: size,
        height: size,
        child: Center(
          child: iconBuilder(iconColor, 22.0),
        ),
      );

      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: LiquidGlassLens(
          style: glassStyle,
          child: buttonChild,
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipOval(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0x992C2C2E)
                    : const Color(0xB3FFFFFF),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
              child: iconBuilder(iconColor, 22.0),
            ),
          ),
        ),
      ),
    );
  }
}

class _MorphMenuItemData {
  final String id;
  final String label;
  final bool isDestructive;
  final Widget Function(Color color, double size) iconBuilder;

  const _MorphMenuItemData({
    required this.id,
    required this.label,
    required this.iconBuilder,
    this.isDestructive = false,
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
  final bool isDark;
  final List<_MorphMenuItemData> items;
  final ValueChanged<String> onItemTap;

  const _TopMorphMenu({
    super.key,
    required this.width,
    required this.isDark,
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
                      isDark: isDark,
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
  final bool isDark;
  final VoidCallback onTap;

  const _MorphMenuRow({
    super.key,
    required this.item,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final defaultColor = isDark
        ? Colors.white.withValues(alpha: 0.92)
        : const Color(0xFF1C1C1E);
    final itemColor = item.isDestructive ? Colors.red.shade400 : defaultColor;

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
  final List<_MorphMenuItemData> items;
  final ValueChanged<String> onItemSelected;
  final ValueChanged<bool>? onOpenChanged;

  const _MorphingHeaderMenuButton({
    Key? key,
    required this.iconColor,
    required this.isDark,
    this.glassEnabled = false,
    this.isLite = false,
    required this.items,
    required this.onItemSelected,
    this.onOpenChanged,
  }) : super(key: key);

  @override
  State<_MorphingHeaderMenuButton> createState() =>
      _MorphingHeaderMenuButtonState();
}

class _MorphingHeaderMenuButtonState extends State<_MorphingHeaderMenuButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;
  bool _isOpen = false;
  static const double _ctrlSize = 44.0;
  static const double _menuWidth = 224.0;

  bool get isOpen => _isOpen;

  void closeMenu() => _closeMenu();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
    _controller.forward();
    widget.onOpenChanged?.call(true);
  }

  void _closeMenu() {
    if (!_isOpen) return;
    setState(() {
      _isOpen = false;
    });
    _controller.reverse();
    widget.onOpenChanged?.call(false);
  }

  void _handleAction(String id) {
    setState(() {
      _isOpen = false;
    });
    _controller.reverse();
    widget.onOpenChanged?.call(false);
    widget.onItemSelected(id);
  }

  @override
  Widget build(BuildContext context) {
    final openHeight = math.max(_ctrlSize, widget.items.length * 44.0 + 12.0);
    final glassProvider = context.watch<LiquidGlassProvider>();
    final glassStyle = glassProvider.createStyle(
      context: context,
      isDarkOverride: widget.isDark,
      isLiteOverride: widget.isLite,
      color: widget.isDark
          ? const Color(0x33202025)
          : const Color(0x66FFFFFF),
      refractionIndex: 1.15,
      refractionWidth: 22.0,
      shape: const LiquidGlassShape.roundedRectangle(
        cornerRadius: _ctrlSize / 2,
      ),
    );

    if (widget.glassEnabled) {
      final Widget morphChild = SizedBox(
        width: _menuWidth,
        height: openHeight,
        child: LiquidGlassMorph(
          key: const ValueKey<String>('profile_header_menu_morph'),
          alignment: Alignment.topRight,
          motion: LiquidGlassMorphMotion.fluid,
          smoothness: 28,
          style: glassStyle,
          child: _isOpen
              ? _TopMorphMenu(
                  key: const ValueKey<String>('profile_menu'),
                  width: _menuWidth,
                  isDark: widget.isDark,
                  items: widget.items,
                  onItemTap: _handleAction,
                )
              : _ThreeDotsGlyph(
                  key: const ValueKey<String>('profile_glyph'),
                  size: _ctrlSize,
                  color: widget.iconColor,
                  onTap: _toggleMenu,
                ),
        ),
      );

      if (widget.onOpenChanged != null) {
        return morphChild;
      }

      return TapRegion(
        onTapOutside: (_) {
          if (_isOpen) {
            _closeMenu();
          }
        },
        child: morphChild,
      );
    }

    final Widget animatedChild = AnimatedBuilder(
      animation: _curve,
      builder: (context, _) {
        final t = _curve.value;
        final currentWidth =
            _ctrlSize + (_menuWidth - _ctrlSize) * t;
        final currentHeight =
            _ctrlSize + (openHeight - _ctrlSize) * t;

        final glyphOpacity = (1.0 - t * 2.4).clamp(0.0, 1.0);
        final glyphScale = 1.0 - 0.15 * t;
        final menuOpacity = ((t - 0.25) / 0.75).clamp(0.0, 1.0);
        final menuSlideY = (1.0 - menuOpacity) * -12.0;

        final innerContent = SizedBox(
          width: currentWidth,
          height: currentHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_ctrlSize / 2),
            child: Stack(
              alignment: Alignment.topRight,
              children: [
                if (glyphOpacity > 0.001)
                  IgnorePointer(
                    ignoring: _isOpen,
                    child: Opacity(
                      opacity: glyphOpacity,
                      child: Transform.scale(
                        scale: glyphScale,
                        child: _ThreeDotsGlyph(
                          key: const ValueKey<String>('profile_glyph'),
                          size: _ctrlSize,
                          color: widget.iconColor,
                          onTap: _toggleMenu,
                        ),
                      ),
                    ),
                  ),
                if (menuOpacity > 0.001)
                  IgnorePointer(
                    ignoring: !_isOpen,
                    child: Opacity(
                      opacity: menuOpacity,
                      child: Transform.translate(
                        offset: Offset(0, menuSlideY),
                        child: _TopMorphMenu(
                          key: const ValueKey<String>('profile_menu'),
                          width: _menuWidth,
                          isDark: widget.isDark,
                          items: widget.items,
                          onItemTap: _handleAction,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );

        return Container(
          width: currentWidth,
          height: currentHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_ctrlSize / 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: (widget.isDark ? 0.22 : 0.08) + 0.12 * t,
                ),
                blurRadius: 8 + 14 * t,
                offset: Offset(0, 2 + 6 * t),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_ctrlSize / 2),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                width: currentWidth,
                height: currentHeight,
                decoration: BoxDecoration(
                  color: widget.isDark
                      ? const Color(0x992C2C2E)
                      : const Color(0xB3FFFFFF),
                  borderRadius: BorderRadius.circular(_ctrlSize / 2),
                  border: Border.all(
                    color: widget.isDark
                        ? Colors.white.withValues(alpha: 0.14)
                        : Colors.black.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                ),
                child: innerContent,
              ),
            ),
          ),
        );
      },
    );

    if (widget.onOpenChanged != null) {
      return animatedChild;
    }

    return TapRegion(
      onTapOutside: (_) {
        if (_isOpen) {
          _closeMenu();
        }
      },
      child: animatedChild,
    );
  }
}
