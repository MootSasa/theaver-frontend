import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ios_color_picker/show_ios_color_picker.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/name_color_preset.dart';
import '../../services/account_manager.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/name_color_sync_service.dart';
import '../../services/profile_theme_provider.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';
import '../../widgets/profile/color_palette_picker.dart';
import '../../widgets/profile/name_color_picker.dart';
import '../../widgets/profile/profile_segmented_control.dart';
import '../../widgets/profile/reply_message_preview_card.dart';

/// Экран изменения цвета профиля в стиле Telegram.
class ProfileColorScreen extends StatefulWidget {
  const ProfileColorScreen({Key? key}) : super(key: key);

  @override
  State<ProfileColorScreen> createState() => _ProfileColorScreenState();
}

class _ProfileColorScreenState extends State<ProfileColorScreen> {
  late ProfileColorPreset _tempPreset;
  late NameColorPreset _tempNameColorPreset;
  late ReplyStripStyle _tempStripStyle;
  int _selectedTab = 0; // 0 = Профиль, 1 = Имя
  final AccountManager _accountManager = AccountManager();

  @override
  void initState() {
    super.initState();
    final themeProvider = context.read<ProfileThemeProvider>();
    _tempPreset = themeProvider.currentPreset ?? ProfileColorPresets.blue;
    _tempNameColorPreset = themeProvider.currentNameColorPreset;
    _tempStripStyle = themeProvider.currentStripStyle;
  }

  String _getUserDisplayName() {
    final account = _accountManager.currentAccount;
    if (account == null) return 'Саша';
    final name = account.name ?? '';
    final surname = account.surname ?? '';
    if (name.isEmpty && surname.isEmpty) {
      return account.username != null ? '@${account.username}' : 'Саша';
    }
    return '$name $surname'.trim();
  }

  String? _getUserAvatarUrl() {
    final account = _accountManager.currentAccount;
    return account?.avatarUrl;
  }

  Future<void> _applyAndSave() async {
    HapticUtils.heavy();
    final themeProvider = context.read<ProfileThemeProvider>();
    await themeProvider.setPreset(_tempPreset);
    await themeProvider.setNameColorAndStyle(_tempNameColorPreset, _tempStripStyle);
    await NameColorSyncService().setNameColorAndStyle(
      preset: _tempNameColorPreset,
      style: _tempStripStyle,
    );
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _resetProfileColor() async {
    HapticUtils.impact();
    final themeProvider = context.read<ProfileThemeProvider>();
    await themeProvider.resetToDefault();
    setState(() {
      _tempPreset = ProfileColorPresets.blue;
      _tempNameColorPreset = NameColorPresets.red;
      _tempStripStyle = ReplyStripStyle.solid;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.translate('profile_color_reset_success')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showEmojiTodo() {
    HapticUtils.tap();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${context.l10n.translate('profile_color_bg_emoji')} — ${context.l10n.translate('feature_in_development')}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Диалог выбора собственного цвета фона профиля
  Future<void> _showCustomColorDialog() async {
    final colors = [
      const Color(0xFF1E88E5),
      const Color(0xFF43A047),
      const Color(0xFFFB8C00),
      const Color(0xFFE53935),
      const Color(0xFF8E24AA),
      const Color(0xFF00ACC1),
      const Color(0xFFD81B60),
      const Color(0xFF3949AB),
      const Color(0xFF00897B),
      const Color(0xFFF4511E),
      const Color(0xFF757575),
      const Color(0xFF5E35B1),
    ];

    final chosenColor = await showDialog<Color>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF232E3C),
          title: Text(
            context.l10n.translate('profile_color_choose_custom'),
            style: const TextStyle(color: Colors.white),
          ),
          content: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: colors.map((c) {
              return GestureDetector(
                onTap: () => Navigator.pop(context, c),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );

    if (chosenColor != null && mounted) {
      setState(() {
        _tempPreset = ProfileColorPreset.fromCustomColor(chosenColor);
      });
    }
  }

  final IOSColorPickerController _colorPickerController = IOSColorPickerController();

  @override
  void dispose() {
    _colorPickerController.dispose();
    super.dispose();
  }

  /// Диалог выбора кастомного цвета имени (одноцветный, двухцветный, трёхцветный)
  Future<void> _showCustomNameColorDialog() async {
    HapticUtils.selection();

    Color c1 = _tempNameColorPreset.primaryColor;
    Color c2 = _tempNameColorPreset.effectiveSecondary;
    Color c3 = _tempNameColorPreset.effectiveTertiary;

    if (_tempStripStyle == ReplyStripStyle.solid) {
      _colorPickerController.showIOSCustomColorPicker(
        context: context,
        startingColor: c1,
        onColorChanged: (newColor) {
          final opaque = newColor.withValues(alpha: 1.0);
          setState(() {
            _tempNameColorPreset = NameColorPreset.fromCustomColor(opaque);
          });
        },
      );
      return;
    }

    if (_tempStripStyle == ReplyStripStyle.dualColor || _tempStripStyle == ReplyStripStyle.segmented) {
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1E2C3A),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (bottomSheetContext) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Настройка цветов полоски ответа',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        GestureDetector(
                          onTap: () {
                            HapticUtils.selection();
                            _colorPickerController.showIOSCustomColorPicker(
                              context: context,
                              startingColor: c1,
                              onColorChanged: (newColor) {
                                final opaque = newColor.withValues(alpha: 1.0);
                                setSheetState(() {
                                  c1 = opaque;
                                });
                                setState(() {
                                  _tempNameColorPreset = NameColorPreset.fromCustomGradient(c1, c2);
                                });
                              },
                            );
                          },
                          child: Column(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: c1,
                                  border: Border.all(color: Colors.white38, width: 2),
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text('Цвет 1', style: TextStyle(color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                        ),
                        const Icon(Icons.swap_horiz_rounded, color: Colors.white38, size: 28),
                        GestureDetector(
                          onTap: () {
                            HapticUtils.selection();
                            _colorPickerController.showIOSCustomColorPicker(
                              context: context,
                              startingColor: c2,
                              onColorChanged: (newColor) {
                                final opaque = newColor.withValues(alpha: 1.0);
                                setSheetState(() {
                                  c2 = opaque;
                                });
                                setState(() {
                                  _tempNameColorPreset = NameColorPreset.fromCustomGradient(c1, c2);
                                });
                              },
                            );
                          },
                          child: Column(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: c2,
                                  border: Border.all(color: Colors.white38, width: 2),
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text('Цвет 2', style: TextStyle(color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2B82C9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Готово', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              );
            },
          );
        },
      );
      return;
    }

    if (_tempStripStyle == ReplyStripStyle.candyCane) {
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1E2C3A),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (bottomSheetContext) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Настройка 3-х цветов карамельной полоски',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        GestureDetector(
                          onTap: () {
                            HapticUtils.selection();
                            _colorPickerController.showIOSCustomColorPicker(
                              context: context,
                              startingColor: c1,
                              onColorChanged: (newColor) {
                                final opaque = newColor.withValues(alpha: 1.0);
                                setSheetState(() {
                                  c1 = opaque;
                                });
                                setState(() {
                                  _tempNameColorPreset = NameColorPreset.fromCustomTriple(c1, c2, c3);
                                });
                              },
                            );
                          },
                          child: Column(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: c1,
                                  border: Border.all(color: Colors.white38, width: 2),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text('Цвет 1', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            HapticUtils.selection();
                            _colorPickerController.showIOSCustomColorPicker(
                              context: context,
                              startingColor: c2,
                              onColorChanged: (newColor) {
                                final opaque = newColor.withValues(alpha: 1.0);
                                setSheetState(() {
                                  c2 = opaque;
                                });
                                setState(() {
                                  _tempNameColorPreset = NameColorPreset.fromCustomTriple(c1, c2, c3);
                                });
                              },
                            );
                          },
                          child: Column(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: c2,
                                  border: Border.all(color: Colors.white38, width: 2),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text('Цвет 2', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            HapticUtils.selection();
                            _colorPickerController.showIOSCustomColorPicker(
                              context: context,
                              startingColor: c3,
                              onColorChanged: (newColor) {
                                final opaque = newColor.withValues(alpha: 1.0);
                                setSheetState(() {
                                  c3 = opaque;
                                });
                                setState(() {
                                  _tempNameColorPreset = NameColorPreset.fromCustomTriple(c1, c2, c3);
                                });
                              },
                            );
                          },
                          child: Column(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: c3,
                                  border: Border.all(color: Colors.white38, width: 2),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text('Цвет 3', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2B82C9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Готово', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              );
            },
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final displayName = _getUserDisplayName();
    final avatarUrl = _getUserAvatarUrl();

    // Верхний цвет фона предпросмотра профиля
    BoxDecoration topBackgroundDecoration;
    if (_tempPreset.isGradient) {
      topBackgroundDecoration = BoxDecoration(
        gradient: LinearGradient(
          colors: _tempPreset.gradientColors!,
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      );
    } else {
      topBackgroundDecoration = BoxDecoration(
        color: _tempPreset.backgroundColor,
      );
    }

    final avatarProvider = avatarImageProvider(avatarUrl);

    return Consumer<LiquidGlassProvider>(
      builder: (context, glassProvider, _) {
        final glassEnabled = glassProvider.enabled;
        final isLite = glassProvider.isLite;

        final segmentedControl = ProfileSegmentedControl(
          enabled: glassEnabled,
          isLite: isLite,
          customPreset: _tempPreset,
          selectedIndex: _selectedTab,
          onTabChanged: (index) {
            HapticUtils.selection();
            setState(() {
              _selectedTab = index;
            });
          },
          wallLabel: l10n.translate('profile_color_tab_profile'),
          giftsLabel: l10n.translate('profile_color_tab_name'),
        );

        // Верхняя панель с кнопкой "Назад" и сегментом
        final topBarRow = Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 24),
              onPressed: () {
                _applyAndSave();
              },
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: segmentedControl,
              ),
            ),
            const SizedBox(width: 40),
          ],
        );

        // Верхняя секция предпросмотра
        Widget topPreviewSection;
        if (_selectedTab == 0) {
          topPreviewSection = AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOutCubic,
            width: double.infinity,
            decoration: topBackgroundDecoration,
            padding: EdgeInsets.only(
              top: statusBarHeight + 8,
              bottom: 24,
              left: 16,
              right: 16,
            ),
            child: Column(
              children: [
                topBarRow,
                const SizedBox(height: 20),
                // Круглый аватар
                AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOutCubic,
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _tempPreset.ringColor,
                      width: 3.0,
                    ),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: CircleAvatar(
                    backgroundColor: Colors.white24,
                    backgroundImage: avatarProvider,
                    child: avatarProvider == null
                        ? Text(
                            displayName.isNotEmpty ? displayName[0].toUpperCase() : 'С',
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 350),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _tempPreset.statusColor,
                  ),
                  child: Text(l10n.translate('profile_online')),
                ),
              ],
            ),
          );
        } else {
          topPreviewSection = Container(
            width: double.infinity,
            color: const Color(0xFF17212B),
            padding: EdgeInsets.only(
              top: statusBarHeight + 8,
              bottom: 16,
              left: 16,
              right: 16,
            ),
            child: Column(
              children: [
                topBarRow,
                const SizedBox(height: 16),
                ReplyMessagePreviewCard(
                  preset: _tempNameColorPreset,
                  stripStyle: _tempStripStyle,
                  userName: displayName,
                  avatarUrl: avatarUrl,
                ),
              ],
            ),
          );
        }

        // Нижняя панель управления
        Widget bottomControlSection;
        if (_selectedTab == 0) {
          bottomControlSection = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ColorPalettePicker(
                selectedPreset: _tempPreset,
                onSelect: (preset) {
                  setState(() {
                    _tempPreset = preset;
                  });
                },
                onPickCustomColor: _showCustomColorDialog,
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  l10n.translate('profile_color_bg_emoji'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF6C7F93),
                  ),
                ),
              ),
              InkWell(
                onTap: _showEmojiTodo,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  color: const Color(0xFF232E3C).withValues(alpha: 0.5),
                  child: Row(
                    children: [
                      const Icon(Icons.sentiment_satisfied_alt_rounded, color: Colors.white60, size: 22),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          l10n.translate('profile_color_bg_emoji'),
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'TODO',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              InkWell(
                onTap: _resetProfileColor,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E2C3A),
                    border: Border(
                      top: BorderSide(color: Colors.white10, width: 0.5),
                      bottom: BorderSide(color: Colors.white10, width: 0.5),
                    ),
                  ),
                  child: Text(
                    l10n.translate('profile_color_reset_btn'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64B5F6),
                    ),
                  ),
                ),
              ),
            ],
          );
        } else {
          bottomControlSection = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NameColorPicker(
                selectedPreset: _tempNameColorPreset,
                selectedStyle: _tempStripStyle,
                onPresetSelected: (preset) {
                  setState(() {
                    _tempNameColorPreset = preset;
                  });
                },
                onStyleSelected: (style) {
                  setState(() {
                    _tempStripStyle = style;
                  });
                },
                onPickCustomColor: _showCustomNameColorDialog,
              ),
              const SizedBox(height: 32),
              InkWell(
                onTap: _resetProfileColor,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E2C3A),
                    border: Border(
                      top: BorderSide(color: Colors.white10, width: 0.5),
                      bottom: BorderSide(color: Colors.white10, width: 0.5),
                    ),
                  ),
                  child: Text(
                    l10n.translate('profile_color_reset_btn'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64B5F6),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        Widget content = Column(
          children: [
            topPreviewSection,
            Expanded(
              child: Container(
                color: const Color(0xFF17212B),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: bottomControlSection,
                ),
              ),
            ),
          ],
        );

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Scaffold(
            backgroundColor: const Color(0xFF17212B),
            body: content,
          ),
        );
      },
    );
  }
}
