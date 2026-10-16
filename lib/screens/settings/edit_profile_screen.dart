import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';

/// Экран редактирования профиля пользователя ("Аккаунт"),
/// повторяющий цветовое решение главного экрана настроек (SettingsScreen).
class EditProfileScreen extends StatefulWidget {
  final String? initialName;
  final String? initialSurname;
  final String? initialUsername;
  final String? initialPhone;
  final String? initialBio;
  final DateTime? initialBirthday;
  final String? initialEmail;

  const EditProfileScreen({
    Key? key,
    this.initialName,
    this.initialSurname,
    this.initialUsername,
    this.initialPhone,
    this.initialBio,
    this.initialBirthday,
    this.initialEmail,
  }) : super(key: key);

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _surnameController;
  late TextEditingController _usernameController;
  late TextEditingController _phoneController;
  late TextEditingController _bioController;

  DateTime? _selectedBirthday;
  bool _isSaving = false;

  static const Color brandColor = Color(0xFF0088CC);
  static const int bioMaxLength = 140;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _surnameController = TextEditingController(text: widget.initialSurname ?? '');

    // Удаляем начальную @, если она передана
    final rawUsername = (widget.initialUsername ?? '').trim();
    final cleanUsername = rawUsername.startsWith('@')
        ? rawUsername.substring(1)
        : rawUsername;

    _usernameController = TextEditingController(text: cleanUsername);
    _phoneController = TextEditingController(text: widget.initialPhone ?? '');
    _phoneController.addListener(_onPhoneChanged);

    _bioController = TextEditingController(text: widget.initialBio ?? '');
    _bioController.addListener(_onBioChanged);

    _selectedBirthday = widget.initialBirthday;
  }

  void _onBioChanged() {
    setState(() {});
  }

  void _onPhoneChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _usernameController.dispose();
    _phoneController.removeListener(_onPhoneChanged);
    _phoneController.dispose();
    _bioController.removeListener(_onBioChanged);
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    final name = _nameController.text.trim();
    final surname = _surnameController.text.trim();

    var username = _usernameController.text.trim();
    if (username.startsWith('@')) {
      username = username.substring(1).trim();
    }

    final phone = _phoneController.text.trim();
    final email = widget.initialEmail ?? '';

    final result = await AuthService.updateProfile(
      name: name,
      surname: surname,
      username: username,
      email: email,
      phone: phone,
      bio: _bioController.text.trim(),
      birthday: _selectedBirthday,
    );

    if (!mounted) return;

    setState(() {
      _isSaving = false;
    });

    if (result['success'] == true) {
      Navigator.pop(context, {
        'name': name,
        'surname': surname,
        'username': username,
        'phone': phone,
        'bio': _bioController.text.trim(),
        'birthday': _selectedBirthday,
        'synced': result['synced'] ?? true,
      });
    } else {
      final l10n = AppLocalizations.of(context)!;
      final errorMessage = result['requiresServer'] == true
          ? l10n.translate('edit_profile_server_required_for_unique_fields')
          : (result['message'] ?? l10n.translate('common_error'));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _selectBirthday() async {
    final now = DateTime.now();
    final initialDate = _selectedBirthday ?? DateTime(2000, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1920),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: brandColor,
                ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedBirthday = picked;
      });
    }
  }

  void _clearBirthday() {
    setState(() {
      _selectedBirthday = null;
    });
  }

  void _clearPhone() {
    _phoneController.clear();
  }

  String _formatBirthday(DateTime? date, AppLocalizations l10n) {
    if (date == null) {
      return l10n.translate('edit_profile_birthday_not_set');
    }
    final months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  void _showPersonalChannelTodo(AppLocalizations l10n) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.translate('edit_profile_personal_channel_todo')),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Цвета в точности как на главном экране настроек (SettingsScreen)
    final backgroundColor = theme.scaffoldBackgroundColor;
    final cardColor = theme.cardColor;
    final accentColor = theme.primaryColor; // Color(0xFF0088CC)
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = theme.hintColor;

    final bioRemaining = bioMaxLength - _bioController.text.length;

    // Мягкий неяркий цвет для подсказок в тёмной теме (намного менее яркий)
    final mutedHintStyle = TextStyle(
      color: isDark
          ? const Color(0xFF555B63)
          : secondaryTextColor.withValues(alpha: 0.4),
      fontSize: 16,
    );

    const transparentInputDecoration = InputDecoration(
      filled: false,
      fillColor: Colors.transparent,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      isDense: true,
      contentPadding: EdgeInsets.zero,
    );

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: primaryTextColor, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.translate('edit_profile_title'),
          style: TextStyle(
            color: primaryTextColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          _isSaving
              ? const Padding(
                  padding: EdgeInsets.all(14.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: brandColor,
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.check_rounded, color: brandColor, size: 26),
                  onPressed: _saveProfile,
                  tooltip: l10n.translate('edit_profile_save'),
                ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // СЕКЦИЯ 1: Ваше имя
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 8, bottom: 8),
              child: Text(
                l10n.translate('edit_profile_your_name'),
                style: theme.textTheme.labelLarge?.copyWith(
                      color: accentColor,
                      fontWeight: FontWeight.bold,
                    ) ??
                    const TextStyle(
                      color: brandColor,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameController,
                    style: TextStyle(color: primaryTextColor, fontSize: 16),
                    decoration: transparentInputDecoration.copyWith(
                      hintText: l10n.translate('edit_profile_first_name'),
                      hintStyle: mutedHintStyle,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _surnameController,
                    style: TextStyle(color: primaryTextColor, fontSize: 16),
                    decoration: transparentInputDecoration.copyWith(
                      hintText: l10n.translate('edit_profile_last_name'),
                      hintStyle: mutedHintStyle,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // СЕКЦИЯ 2: О себе
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _bioController,
                          maxLength: bioMaxLength,
                          maxLines: 3,
                          minLines: 1,
                          style: TextStyle(color: primaryTextColor, fontSize: 16),
                          decoration: transparentInputDecoration.copyWith(
                            hintText: l10n.translate('edit_profile_bio_hint'),
                            hintStyle: mutedHintStyle,
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$bioRemaining',
                        style: TextStyle(
                          color: bioRemaining < 20 ? Colors.redAccent : brandColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 6, bottom: 16),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(color: secondaryTextColor, fontSize: 13),
                  children: [
                    TextSpan(text: '${l10n.translate('edit_profile_bio_visible_info')} '),
                    WidgetSpan(
                      child: GestureDetector(
                        onTap: () {},
                        child: Text(
                          l10n.translate('edit_profile_edit_link'),
                          style: const TextStyle(
                            color: brandColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // СЕКЦИЯ 3: Информация о Вас
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 8, bottom: 8),
              child: Text(
                l10n.translate('edit_profile_info_about_you'),
                style: theme.textTheme.labelLarge?.copyWith(
                      color: accentColor,
                      fontWeight: FontWeight.bold,
                    ) ??
                    const TextStyle(
                      color: brandColor,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Редактируемый Номер телефона + Кнопка сброса
                  Row(
                    children: [
                      const Icon(Icons.phone_rounded, color: brandColor, size: 22),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              style: TextStyle(
                                color: primaryTextColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: transparentInputDecoration.copyWith(
                                hintText: l10n.translate('edit_profile_birthday_not_set'),
                                hintStyle: mutedHintStyle,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.translate('edit_profile_phone'),
                              style: TextStyle(
                                color: secondaryTextColor,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_phoneController.text.isNotEmpty)
                        IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            color: secondaryTextColor,
                            size: 18,
                          ),
                          onPressed: _clearPhone,
                          tooltip: l10n.translate('edit_profile_birthday_clear'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Редактируемое Имя пользователя (@username)
                  Row(
                    children: [
                      const Icon(Icons.alternate_email_rounded, color: brandColor, size: 22),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _usernameController,
                              style: TextStyle(
                                color: primaryTextColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: transparentInputDecoration.copyWith(
                                prefixText: '@',
                                prefixStyle: TextStyle(
                                  color: primaryTextColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                                hintText: 'username',
                                hintStyle: mutedHintStyle,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.translate('edit_profile_username'),
                              style: TextStyle(
                                color: secondaryTextColor,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // День рождения + Кнопка сброса
                  Row(
                    children: [
                      const Icon(Icons.cake_rounded, color: brandColor, size: 22),
                      const SizedBox(width: 14),
                      Expanded(
                        child: InkWell(
                          onTap: _selectBirthday,
                          borderRadius: BorderRadius.circular(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatBirthday(_selectedBirthday, l10n),
                                style: TextStyle(
                                  color: _selectedBirthday != null
                                      ? primaryTextColor
                                      : mutedHintStyle.color,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                l10n.translate('edit_profile_birthday'),
                                style: TextStyle(
                                  color: secondaryTextColor,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_selectedBirthday != null)
                        IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            color: secondaryTextColor,
                            size: 18,
                          ),
                          onPressed: _clearBirthday,
                          tooltip: l10n.translate('edit_profile_birthday_clear'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 6, bottom: 16),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(color: secondaryTextColor, fontSize: 13),
                  children: [
                    TextSpan(text: l10n.translate('edit_profile_birthday_visibility_info_1')),
                    WidgetSpan(
                      child: GestureDetector(
                        onTap: () {},
                        child: Text(
                          l10n.translate('edit_profile_settings_link'),
                          style: const TextStyle(
                            color: brandColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    TextSpan(text: l10n.translate('edit_profile_birthday_visibility_info_2')),
                  ],
                ),
              ),
            ),

            // СЕКЦИЯ 4: Личный канал (TODO)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.campaign_rounded, color: brandColor, size: 20),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      l10n.translate('edit_profile_personal_channel'),
                      style: TextStyle(
                        color: primaryTextColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _showPersonalChannelTodo(l10n),
                    style: TextButton.styleFrom(
                      foregroundColor: brandColor,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      l10n.translate('edit_profile_add_btn'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
