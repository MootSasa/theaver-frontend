import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/browser_vault_service.dart';
import '../../utils/browser_autofill_script.dart';
import '../../utils/haptic_utils.dart';
import '../design_system/theav_design_system.dart';

export 'browser_vault_pin_sheet.dart';

String _cleanAutofillStr(Object? value) =>
    value == null ? '' : value.toString().trim();

String _formatCardExpiry(int month, int year) {
  if (month < 1 || month > 12 || year <= 0) {
    return '';
  }
  final String mm = month.toString().padLeft(2, '0');
  final String yy = (year % 100).toString().padLeft(2, '0');
  return '$mm/$yy';
}

/// Floating Safari iOS 26 autofill capsule bar displayed above the keyboard
/// when a login, OTP, payment card, address, or contact input is focused in the
/// top-level browser frame.
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

  final List<BrowserCardHint> cards;
  final int totalSavedCardsCount;
  final ValueChanged<BrowserCardHint>? onSelectCard;
  final VoidCallback? onOpenCardPicker;

  final List<BrowserSavedAddress> addresses;
  final ValueChanged<BrowserSavedAddress>? onSelectAddress;
  final VoidCallback? onOpenAddressPicker;

  final String? otpCandidateCode;
  final bool showExplicitPasteOtpChip;
  final ValueChanged<String>? onFillOtp;
  final VoidCallback? onPasteOtpFromClipboard;

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
    this.cards = const [],
    this.totalSavedCardsCount = 0,
    this.onSelectCard,
    this.onOpenCardPicker,
    this.addresses = const [],
    this.onSelectAddress,
    this.onOpenAddressPicker,
    this.otpCandidateCode,
    this.showExplicitPasteOtpChip = false,
    this.onFillOtp,
    this.onPasteOtpFromClipboard,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;

    final List<Widget> chips = <Widget>[];

    if (focusedField.isLogin) {
      if (hints.isNotEmpty || totalSavedCount > 0) {
        for (final hint in hints.take(3)) {
          final String label = hint.username.isNotEmpty
              ? hint.username
              : (hint.displayHost.isNotEmpty
                  ? hint.displayHost
                  : context.trOr(
                      'browser_autofill_account_fallback',
                      'Аккаунт',
                    ));
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
              label: hints.isEmpty
                  ? context.trOr('browser_autofill_passwords', 'Пароли')
                  : context.trOr('browser_autofill_all', 'Все'),
              onTap: onOpenPasswordPicker,
            ),
          );
        }
      }
    } else if (focusedField.isOtp) {
      final String cleanOtp = _cleanAutofillStr(otpCandidateCode);
      final bool hasOtp = cleanOtp.isNotEmpty;
      if (hasOtp) {
        chips.add(
          _AutofillCapsuleChip(
            key: const ValueKey('safari_autofill_otp_chip'),
            icon: Icons.sms_outlined,
            label: cleanOtp,
            isPrimary: true,
            onTap: () => onFillOtp?.call(cleanOtp),
          ),
        );
      }
      if (showExplicitPasteOtpChip) {
        chips.add(
          _AutofillCapsuleChip(
            key: const ValueKey('safari_autofill_paste_otp_btn'),
            icon: Icons.content_paste_rounded,
            label: context.trOr('browser_autofill_paste_otp', 'Вставить код'),
            isPrimary: !hasOtp,
            onTap: () => onPasteOtpFromClipboard?.call(),
          ),
        );
      }
    } else if (focusedField.isCard) {
      for (final card in cards.take(3)) {
        chips.add(
          _AutofillCapsuleChip(
            key: ValueKey('safari_autofill_card_chip_${card.id}'),
            icon: Icons.credit_card_rounded,
            label: '${card.brand.displayName} •••• ${card.last4}',
            isPrimary: true,
            onTap: () => onSelectCard?.call(card),
          ),
        );
      }
      if (totalSavedCardsCount > 0) {
        chips.add(
          _AutofillCapsuleChip(
            key: const ValueKey('safari_autofill_all_cards_btn'),
            icon: Icons.credit_card_outlined,
            label: cards.isEmpty
                ? context.trOr('browser_autofill_cards', 'Карты')
                : context.trOr('browser_autofill_all_cards', 'Все карты'),
            onTap: () => onOpenCardPicker?.call(),
          ),
        );
      }
    } else if (focusedField.isAddress || focusedField.isContact) {
      final List<BrowserSavedAddress> usableAddresses = addresses
          .where((a) => a.hasAnyField)
          .toList(growable: false);
      final bool hasContact =
          contactProfile.enabled && contactProfile.hasAnyField;

      if (usableAddresses.isNotEmpty &&
          (focusedField.isAddress || !hasContact)) {
        _appendAddressChips(context, chips, usableAddresses);
      } else if (hasContact) {
        final summaryParts = <String>[
          if (contactProfile.fullName.trim().isNotEmpty)
            contactProfile.fullName.trim(),
          if (contactProfile.email.trim().isNotEmpty)
            contactProfile.email.trim(),
          if (contactProfile.phone.trim().isNotEmpty)
            contactProfile.phone.trim(),
        ];
        if (summaryParts.isNotEmpty) {
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
      }
    }

    if (chips.isEmpty) {
      return const SizedBox.shrink();
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
  void _appendAddressChips(
    BuildContext context,
    List<Widget> chips,
    List<BrowserSavedAddress> usableAddresses,
  ) {
    for (final addr in usableAddresses.take(3)) {
      final String title = _cleanAutofillStr(addr.displayTitle);
      final String subtitle = _cleanAutofillStr(addr.summarySubtitle);
      final String label = title.isNotEmpty
          ? title
          : (subtitle.isNotEmpty
              ? subtitle
              : context.trOr(
                  'browser_autofill_address_fallback',
                  'Адрес',
                ));
      chips.add(
        _AutofillCapsuleChip(
          key: ValueKey('safari_autofill_address_chip_${addr.id}'),
          icon: Icons.location_on_outlined,
          label: label,
          subtitle:
              (title.isNotEmpty && subtitle.isNotEmpty && subtitle != title)
                  ? subtitle
                  : null,
          isPrimary: true,
          onTap: () => onSelectAddress?.call(addr),
        ),
      );
    }
    if (onOpenAddressPicker != null) {
      chips.add(
        _AutofillCapsuleChip(
          key: const ValueKey('safari_autofill_all_addresses_btn'),
          icon: Icons.bookmarks_outlined,
          label: context.trOr('browser_autofill_addresses', 'Адреса'),
          onTap: onOpenAddressPicker!,
        ),
      );
    }
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
                                ? context.trOr(
                                    'browser_save_password_update_title',
                                    'Обновить пароль?',
                                  )
                                : context.trOr(
                                    'browser_save_password_title',
                                    'Сохранить пароль?',
                                  ),
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
                                hintText: context.trOr(
                                  'browser_save_password_username_hint',
                                  'Логин или Email',
                                ),
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
                              ? context.trOr(
                                  'browser_save_password_update_btn',
                                  'Обновить пароль',
                                )
                              : context.trOr(
                                  'browser_save_password_save_btn',
                                  'Сохранить пароль',
                                ),
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
                                  context.trOr(
                                    'browser_save_password_never',
                                    'Никогда',
                                  ),
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
                                context.trOr(
                                  'browser_save_password_not_now',
                                  'Не сейчас',
                                ),
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

/// Compact Safari iOS 26 floating bottom prompt asking the user to save or
/// update a submitted payment card inside the encrypted browser vault (never
/// storing CVV/CVC).
///
/// Animated purely via transform translation without `Opacity` wrappers so
/// `LiquidGlassLens` refraction stays completely solid.
class SafariSaveCardSheet extends StatelessWidget {
  final BrowserPendingCardSubmission candidate;
  final VoidCallback onSave;
  final VoidCallback onDismiss;

  const SafariSaveCardSheet({
    super.key,
    required this.candidate,
    required this.onSave,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final bool disableAnims =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final String digits = BrowserVaultService.stripCardDigits(
      candidate.cardNumber,
    );
    final String last4 =
        digits.length >= 4 ? digits.substring(digits.length - 4) : digits;
    final BrowserCardBrand brand = BrowserVaultService.detectCardBrand(digits);
    final String maskedLabel = last4.isNotEmpty
        ? '${brand.displayName} •••• $last4'
        : brand.displayName;
    final String holderName = _cleanAutofillStr(candidate.holderName);
    final String expiry = _formatCardExpiry(
      candidate.expMonth,
      candidate.expYear,
    );
    final String displayHost = _cleanAutofillStr(candidate.displayHost);
    final String origin = _cleanAutofillStr(candidate.origin);
    final String hostLabel = displayHost.isNotEmpty ? displayHost : origin;

    final Widget card = Padding(
      key: const ValueKey('safari_save_card_sheet'),
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
                        Icons.credit_card_rounded,
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
                            candidate.isUpdate
                                ? context.trOr(
                                    'browser_save_card_update_title',
                                    'Обновить карту?',
                                  )
                                : context.trOr(
                                    'browser_save_card_title',
                                    'Сохранить карту?',
                                  ),
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: palette.onSurface,
                            ),
                          ),
                          if (hostLabel.isNotEmpty)
                            Text(
                              hostLabel,
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
                        onDismiss();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: palette.onSurface
                        .withValues(alpha: style.isDark ? 0.09 : 0.05),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.credit_card_outlined,
                            size: 17,
                            color: palette.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              maskedLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: palette.onSurface,
                              ),
                            ),
                          ),
                          if (expiry.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              expiry,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: palette.subtext,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (holderName.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.person_outline_rounded,
                              size: 15,
                              color: palette.subtext,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                holderName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: palette.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 14,
                      color: palette.subtext,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        context.trOr(
                          'browser_save_card_cvv_note',
                          'CVV не сохраняется',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.subtext,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 42,
                  child: Material(
                    color: palette.primary,
                    borderRadius: BorderRadius.circular(21),
                    child: InkWell(
                      key: const ValueKey('safari_save_card_confirm_btn'),
                      borderRadius: BorderRadius.circular(21),
                      onTap: () {
                        HapticUtils.selection();
                        onSave();
                      },
                      child: Center(
                        child: Text(
                          candidate.isUpdate
                              ? context.trOr(
                                  'browser_save_card_update_btn',
                                  'Обновить карту',
                                )
                              : context.trOr(
                                  'browser_save_card_save_btn',
                                  'Сохранить карту',
                                ),
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
                SizedBox(
                  height: 36,
                  child: Material(
                    color: palette.onSurface
                        .withValues(alpha: style.isDark ? 0.09 : 0.05),
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      key: const ValueKey('safari_save_card_not_now_btn'),
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        HapticUtils.tap();
                        onDismiss();
                      },
                      child: Center(
                        child: Text(
                          context.trOr(
                            'browser_save_password_not_now',
                            'Не сейчас',
                          ),
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
