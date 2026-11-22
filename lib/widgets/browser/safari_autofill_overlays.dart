import 'package:flutter/material.dart';

import '../../services/browser_vault_service.dart';
import '../../utils/browser_autofill_script.dart';
import '../../utils/haptic_utils.dart';
import '../design_system/theav_design_system.dart';

export 'browser_vault_pin_sheet.dart';

/// Floating Safari iOS 26 autofill capsule bar displayed above the keyboard
/// when a login or contact input is focused in the top-level browser frame.
///
/// Uses [TheavFloatingSurface] without any `Opacity` or `FadeTransition`
/// wrappers so Liquid Glass refraction stays intact.
class SafariAutofillAccessoryBar extends StatelessWidget {
  final BrowserFocusedFieldState focusedField;
  final List<BrowserCredentialHint> hints;
  final BrowserContactProfile contactProfile;
  final int totalSavedCount;
  final ValueChanged<BrowserCredentialHint> onSelectCredential;
  final VoidCallback onOpenPasswordPicker;
  final VoidCallback onFillContact;
  final VoidCallback onDismiss;

  const SafariAutofillAccessoryBar({
    super.key,
    required this.focusedField,
    required this.hints,
    required this.contactProfile,
    required this.totalSavedCount,
    required this.onSelectCredential,
    required this.onOpenPasswordPicker,
    required this.onFillContact,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;

    final bool showContactChip = focusedField.isContact &&
        contactProfile.enabled &&
        contactProfile.hasAnyField;
    final bool showLoginRow = focusedField.isLogin &&
        (hints.isNotEmpty || totalSavedCount > 0);

    if (!showContactChip && !showLoginRow) {
      return const SizedBox.shrink();
    }

    final List<Widget> chips = <Widget>[];
    if (showLoginRow) {
      for (final hint in hints.take(3)) {
        final String label = hint.username.isNotEmpty
            ? hint.username
            : (hint.displayHost.isNotEmpty ? hint.displayHost : 'Аккаунт');
        chips.add(
          _AutofillCapsuleChip(
            key: ValueKey('safari_autofill_credential_chip_${hint.id}'),
            icon: Icons.key_rounded,
            label: label,
            isPrimary: true,
            onTap: () => onSelectCredential(hint),
          ),
        );
      }
      if (totalSavedCount > 0) {
        chips.add(
          _AutofillCapsuleChip(
            key: const ValueKey('safari_autofill_all_passwords_btn'),
            icon: Icons.vpn_key_outlined,
            label: hints.isEmpty ? 'Пароли' : 'Все',
            onTap: onOpenPasswordPicker,
          ),
        );
      }
    } else if (showContactChip) {
      final summaryParts = <String>[
        if (contactProfile.fullName.trim().isNotEmpty)
          contactProfile.fullName.trim(),
        if (contactProfile.email.trim().isNotEmpty) contactProfile.email.trim(),
        if (contactProfile.phone.trim().isNotEmpty) contactProfile.phone.trim(),
      ];
      chips.add(
        _AutofillCapsuleChip(
          key: const ValueKey('safari_autofill_contact_chip'),
          icon: Icons.person_outline_rounded,
          label: summaryParts.first,
          subtitle: summaryParts.length > 1 ? summaryParts[1] : null,
          isPrimary: true,
          onTap: onFillContact,
        ),
      );
    }

    return Padding(
      key: const ValueKey('safari_autofill_accessory_bar'),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Align(
        alignment: Alignment.center,
        child: TheavFloatingSurface(
          borderRadius: 24.0,
          refractionIndex: 1.09,
          refractionWidth: 16.0,
          enableFlex: false,
          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
          child: Material(
            type: MaterialType.transparency,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < chips.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          chips[i],
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  key: const ValueKey('safari_autofill_dismiss_btn'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    HapticUtils.tap();
                    onDismiss();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: palette.subtext,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AutofillCapsuleChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool isPrimary;
  final VoidCallback onTap;

  const _AutofillCapsuleChip({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.isPrimary = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final Color bg = isPrimary
        ? palette.primary.withValues(alpha: style.isDark ? 0.24 : 0.14)
        : palette.onSurface.withValues(alpha: style.isDark ? 0.12 : 0.07);
    final Color fg = isPrimary ? palette.primary : palette.onSurface;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 210),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            HapticUtils.tap();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    subtitle != null && subtitle!.isNotEmpty
                        ? '$label • $subtitle'
                        : label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isPrimary ? palette.onSurface : fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact Safari iOS 26 floating bottom prompt asking the user to save or
/// update submitted login credentials inside the encrypted browser vault.
///
/// Animated purely via transform translation without `Opacity` wrappers so
/// `LiquidGlassLens` refraction stays completely solid.
class SafariSavePasswordSheet extends StatefulWidget {
  final BrowserPendingCredentialSubmission candidate;
  final ValueChanged<String> onSave;
  final VoidCallback onNeverSave;
  final VoidCallback onDismiss;

  const SafariSavePasswordSheet({
    super.key,
    required this.candidate,
    required this.onSave,
    required this.onNeverSave,
    required this.onDismiss,
  });

  @override
  State<SafariSavePasswordSheet> createState() =>
      _SafariSavePasswordSheetState();
}

class _SafariSavePasswordSheetState extends State<SafariSavePasswordSheet> {
  late final TextEditingController _usernameCtrl;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _usernameCtrl = TextEditingController(text: widget.candidate.username);
  }

  @override
  void didUpdateWidget(covariant SafariSavePasswordSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.candidate.username != widget.candidate.username &&
        _usernameCtrl.text != widget.candidate.username) {
      _usernameCtrl.text = widget.candidate.username;
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final bool disableAnims =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final BoxDecoration fieldBoxDecoration = BoxDecoration(
      color: palette.onSurface.withValues(alpha: style.isDark ? 0.09 : 0.05),
      borderRadius: BorderRadius.circular(14),
    );
    const double fieldBoxHeight = 46.0;

    final String maskedOrPlain = _obscurePassword
        ? '•' * widget.candidate.password.length.clamp(6, 16)
        : widget.candidate.password;

    final Widget card = Padding(
      key: const ValueKey('safari_save_password_sheet'),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: TheavFloatingSurface(
          borderRadius: 26.0,
          refractionIndex: 1.10,
          refractionWidth: 18.0,
          enableFlex: false,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: palette.primary
                            .withValues(alpha: style.isDark ? 0.22 : 0.14),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.key_rounded,
                        size: 18,
                        color: palette.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.candidate.isUpdate
                                ? 'Обновить пароль?'
                                : 'Сохранить пароль?',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: palette.onSurface,
                            ),
                          ),
                          Text(
                            widget.candidate.displayHost.isNotEmpty
                                ? widget.candidate.displayHost
                                : widget.candidate.origin,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.subtext,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: palette.subtext,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: () {
                        HapticUtils.tap();
                        widget.onDismiss();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  key: const ValueKey('safari_save_password_username_box'),
                  width: double.infinity,
                  height: fieldBoxHeight,
                  child: DecoratedBox(
                    decoration: fieldBoxDecoration,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.person_outline_rounded,
                            size: 17,
                            color: palette.subtext,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              key: const ValueKey(
                                'safari_save_password_username',
                              ),
                              controller: _usernameCtrl,
                              cursorColor: palette.primary,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                                color: palette.onSurface,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                isCollapsed: true,
                                filled: false,
                                fillColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                hintText: 'Логин или Email',
                                hintStyle: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w400,
                                  color: palette.subtext.withValues(alpha: 0.78),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  key: const ValueKey('safari_save_password_password_box'),
                  width: double.infinity,
                  height: fieldBoxHeight,
                  child: DecoratedBox(
                    decoration: fieldBoxDecoration,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 17,
                            color: palette.subtext,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              maskedOrPlain,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: _obscurePassword ? 2.0 : 0.0,
                                color: palette.onSurface,
                              ),
                            ),
                          ),
                          InkWell(
                            key: const ValueKey(
                              'safari_save_password_toggle_visibility',
                            ),
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              HapticUtils.tap();
                              setState(
                                () => _obscurePassword = !_obscurePassword,
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(
                                _obscurePassword
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded,
                                size: 18,
                                color: palette.subtext,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 42,
                  child: Material(
                    color: palette.primary,
                    borderRadius: BorderRadius.circular(21),
                    child: InkWell(
                      key: const ValueKey('safari_save_password_confirm_btn'),
                      borderRadius: BorderRadius.circular(21),
                      onTap: () {
                        HapticUtils.selection();
                        widget.onSave(_usernameCtrl.text.trim());
                      },
                      child: Center(
                        child: Text(
                          widget.candidate.isUpdate
                              ? 'Обновить пароль'
                              : 'Сохранить пароль',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: palette.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (!widget.candidate.isUpdate) ...[
                      Expanded(
                        child: SizedBox(
                          height: 36,
                          child: Material(
                            color: palette.onSurface
                                .withValues(alpha: style.isDark ? 0.09 : 0.05),
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                              key: const ValueKey(
                                'safari_save_password_never_btn',
                              ),
                              borderRadius: BorderRadius.circular(18),
                              onTap: () {
                                HapticUtils.tap();
                                widget.onNeverSave();
                              },
                              child: Center(
                                child: Text(
                                  'Никогда',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: palette.subtext,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: Material(
                          color: palette.onSurface
                              .withValues(alpha: style.isDark ? 0.09 : 0.05),
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            key: const ValueKey(
                              'safari_save_password_not_now_btn',
                            ),
                            borderRadius: BorderRadius.circular(18),
                            onTap: () {
                              HapticUtils.tap();
                              widget.onDismiss();
                            },
                            child: Center(
                              child: Text(
                                'Не сейчас',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: palette.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (disableAnims) return card;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 1.0, end: 0.0),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, 48.0 * t),
        child: child,
      ),
      child: card,
    );
  }
}
