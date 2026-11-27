import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../l10n/app_localizations.dart';
import '../../utils/haptic_utils.dart';
import '../design_system/theav_design_system.dart';

/// Descriptor for a dial-code country entry (rendered with clean ISO codes, zero flag emojis).
class CountryDialEntry {
  final String iso;
  final String dialCode;
  final String nameEn;
  final String nameRu;
  final String nationalHint;

  const CountryDialEntry({
    required this.iso,
    required this.dialCode,
    required this.nameEn,
    required this.nameRu,
    this.nationalHint = '999 000-00-00',
  });

  String localizedName(String localeCode) =>
      localeCode.toLowerCase().startsWith('ru') ? nameRu : nameEn;
}

const List<CountryDialEntry> kTheavCountryDialCatalog = [
  CountryDialEntry(iso: 'RU', dialCode: '7', nameEn: 'Russia', nameRu: 'Россия', nationalHint: '999 123-45-67'),
  CountryDialEntry(iso: 'KZ', dialCode: '7', nameEn: 'Kazakhstan', nameRu: 'Казахстан', nationalHint: '701 123-45-67'),
  CountryDialEntry(iso: 'BY', dialCode: '375', nameEn: 'Belarus', nameRu: 'Беларусь', nationalHint: '29 123-45-67'),
  CountryDialEntry(iso: 'AM', dialCode: '374', nameEn: 'Armenia', nameRu: 'Армения', nationalHint: '91 123-456'),
  CountryDialEntry(iso: 'KG', dialCode: '996', nameEn: 'Kyrgyzstan', nameRu: 'Киргизия', nationalHint: '555 123-456'),
  CountryDialEntry(iso: 'UZ', dialCode: '998', nameEn: 'Uzbekistan', nameRu: 'Узбекистан', nationalHint: '90 123-45-67'),
  CountryDialEntry(iso: 'TJ', dialCode: '992', nameEn: 'Tajikistan', nameRu: 'Таджикистан', nationalHint: '90 123-45-67'),
  CountryDialEntry(iso: 'AZ', dialCode: '994', nameEn: 'Azerbaijan', nameRu: 'Азербайджан', nationalHint: '50 123-45-67'),
  CountryDialEntry(iso: 'MD', dialCode: '373', nameEn: 'Moldova', nameRu: 'Молдова', nationalHint: '60 123-456'),
  CountryDialEntry(iso: 'GE', dialCode: '995', nameEn: 'Georgia', nameRu: 'Грузия', nationalHint: '555 12-34-56'),
  CountryDialEntry(iso: 'US', dialCode: '1', nameEn: 'United States', nameRu: 'США', nationalHint: '415 555-0132'),
  CountryDialEntry(iso: 'CA', dialCode: '1', nameEn: 'Canada', nameRu: 'Канада', nationalHint: '416 555-0199'),
  CountryDialEntry(iso: 'GB', dialCode: '44', nameEn: 'United Kingdom', nameRu: 'Великобритания', nationalHint: '7700 900123'),
  CountryDialEntry(iso: 'DE', dialCode: '49', nameEn: 'Germany', nameRu: 'Германия', nationalHint: '151 23456789'),
  CountryDialEntry(iso: 'FR', dialCode: '33', nameEn: 'France', nameRu: 'Франция', nationalHint: '6 12 34 56 78'),
  CountryDialEntry(iso: 'ES', dialCode: '34', nameEn: 'Spain', nameRu: 'Испания', nationalHint: '612 34 56 78'),
  CountryDialEntry(iso: 'IT', dialCode: '39', nameEn: 'Italy', nameRu: 'Италия', nationalHint: '312 345 6789'),
  CountryDialEntry(iso: 'PT', dialCode: '351', nameEn: 'Portugal', nameRu: 'Португалия', nationalHint: '912 345 678'),
  CountryDialEntry(iso: 'NL', dialCode: '31', nameEn: 'Netherlands', nameRu: 'Нидерланды', nationalHint: '6 12345678'),
  CountryDialEntry(iso: 'PL', dialCode: '48', nameEn: 'Poland', nameRu: 'Польша', nationalHint: '501 234 567'),
  CountryDialEntry(iso: 'TR', dialCode: '90', nameEn: 'Turkey', nameRu: 'Турция', nationalHint: '532 123 45 67'),
  CountryDialEntry(iso: 'AE', dialCode: '971', nameEn: 'UAE', nameRu: 'ОАЭ', nationalHint: '50 123 4567'),
  CountryDialEntry(iso: 'IL', dialCode: '972', nameEn: 'Israel', nameRu: 'Израиль', nationalHint: '52 123 4567'),
  CountryDialEntry(iso: 'UA', dialCode: '380', nameEn: 'Ukraine', nameRu: 'Украина', nationalHint: '67 123 4567'),
  CountryDialEntry(iso: 'BR', dialCode: '55', nameEn: 'Brazil', nameRu: 'Бразилия', nationalHint: '11 91234-5678'),
  CountryDialEntry(iso: 'CN', dialCode: '86', nameEn: 'China', nameRu: 'Китай', nationalHint: '138 0013 8000'),
  CountryDialEntry(iso: 'JP', dialCode: '81', nameEn: 'Japan', nameRu: 'Япония', nationalHint: '90 1234 5678'),
  CountryDialEntry(iso: 'KR', dialCode: '82', nameEn: 'South Korea', nameRu: 'Южная Корея', nationalHint: '10 1234 5678'),
  CountryDialEntry(iso: 'IN', dialCode: '91', nameEn: 'India', nameRu: 'Индия', nationalHint: '98765 43210'),
  CountryDialEntry(iso: 'AU', dialCode: '61', nameEn: 'Australia', nameRu: 'Австралия', nationalHint: '412 345 678'),
];

CountryDialEntry countryByIso(String iso) {
  final upper = iso.trim().toUpperCase();
  return kTheavCountryDialCatalog.firstWhere(
    (c) => c.iso == upper,
    orElse: () => kTheavCountryDialCatalog.first,
  );
}

CountryDialEntry? detectCountryFromE164(String e164, {String preferredIso = 'RU'}) {
  if (!e164.startsWith('+')) return null;
  final digits = e164.substring(1);
  final sorted = List<CountryDialEntry>.from(kTheavCountryDialCatalog)
    ..sort((a, b) => b.dialCode.length.compareTo(a.dialCode.length));
  for (final entry in sorted) {
    if (digits.startsWith(entry.dialCode)) {
      if (entry.dialCode == '7' && preferredIso.toUpperCase() == 'KZ') {
        return countryByIso('KZ');
      }
      if (entry.dialCode == '1' && preferredIso.toUpperCase() == 'CA') {
        return countryByIso('CA');
      }
      return entry;
    }
  }
  return null;
}

/// Validates and converts international or CIS/regional phone strings into strict
/// ITU-T E.164 format (`+[1-9][0-9]{7,14}`), matching backend `NormalizeE164Phone`.
String? normalizeToE164(String rawInput, {String defaultIso = 'RU'}) {
  var clean = rawInput
      .trim()
      .replaceAll(RegExp(r'[\s\u00a0\-().\/]'), '');
  if (clean.isEmpty) return null;
  if (clean.startsWith('00')) {
    clean = '+${clean.substring(2)}';
  }

  final cc = defaultIso.trim().toUpperCase();
  final country = countryByIso(cc);

  if (clean.startsWith('+')) {
    final digits = clean.substring(1);
    if (!RegExp(r'^[1-9][0-9]{7,14}$').hasMatch(digits)) {
      return null;
    }
    return '+$digits';
  }

  if (!RegExp(r'^[0-9]+$').hasMatch(clean)) {
    return null;
  }

  String digits = clean;
  if (digits.length == 11 &&
      digits.startsWith('8') &&
      (cc.isEmpty || cc == 'RU' || cc == 'KZ')) {
    digits = '7${digits.substring(1)}';
  } else if (digits.length == 10 && (cc == 'RU' || cc == 'KZ')) {
    digits = '7$digits';
  } else if (!digits.startsWith(country.dialCode)) {
    digits = '${country.dialCode}$digits';
  }

  if (!RegExp(r'^[1-9][0-9]{7,14}$').hasMatch(digits)) {
    return null;
  }
  return '+$digits';
}

/// Native phone input row intended to sit inside [TheavInsetGroup], featuring an
/// ISO/dial-code picker sheet, clipboard international paste detection, and
/// optional verified provider badge (e.g. `Yandex ID`, `VK ID`, or `SMS`).
class CountryPhoneInput extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String countryIso;
  final ValueChanged<CountryDialEntry> onCountryChanged;
  final ValueChanged<String>? onE164Changed;
  final VoidCallback? onSubmitted;
  final bool enabled;
  final bool verified;
  final String? verifiedProviderLabel;
  final String? label;

  const CountryPhoneInput({
    super.key,
    required this.controller,
    this.focusNode,
    this.countryIso = 'RU',
    required this.onCountryChanged,
    this.onE164Changed,
    this.onSubmitted,
    this.enabled = true,
    this.verified = false,
    this.verifiedProviderLabel,
    this.label,
  });

  @override
  State<CountryPhoneInput> createState() => _CountryPhoneInputState();
}

class _CountryPhoneInputState extends State<CountryPhoneInput> {
  final GlobalKey _countryPillKey = GlobalKey();
  bool _internalUpdate = false;

  CountryDialEntry get _selectedCountry => countryByIso(widget.countryIso);

  @override
  void initState() {
    super.initState();
    _syncIfFullE164InController();
  }

  @override
  void didUpdateWidget(covariant CountryPhoneInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.countryIso != widget.countryIso) {
      _emitE164(widget.controller.text, _selectedCountry);
    }
  }

  void _syncIfFullE164InController() {
    final text = widget.controller.text.trim();
    if (text.startsWith('+')) {
      final detected =
          detectCountryFromE164(text, preferredIso: widget.countryIso);
      if (detected != null) {
        final national = text.substring(1 + detected.dialCode.length);
        _internalUpdate = true;
        widget.controller.value = TextEditingValue(
          text: national,
          selection: TextSelection.collapsed(offset: national.length),
        );
        _internalUpdate = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            if (detected.iso != widget.countryIso) {
              widget.onCountryChanged(detected);
            }
            widget.onE164Changed?.call(text);
          }
        });
      }
    }
  }

  void _emitE164(String nationalOrRaw, CountryDialEntry entry) {
    final norm = normalizeToE164(nationalOrRaw, defaultIso: entry.iso);
    widget.onE164Changed?.call(norm ?? '');
  }

  void _handleTextChanged(String raw) {
    if (_internalUpdate) return;
    final compact = raw.trim().replaceAll(RegExp(r'[\s\u00a0\-()]'), '');
    if (compact.startsWith('+') && compact.length >= 4) {
      final detected =
          detectCountryFromE164(compact, preferredIso: widget.countryIso);
      if (detected != null) {
        final national = compact.substring(1 + detected.dialCode.length);
        _internalUpdate = true;
        widget.controller.value = TextEditingValue(
          text: national,
          selection: TextSelection.collapsed(offset: national.length),
        );
        _internalUpdate = false;
        widget.onCountryChanged(detected);
        _emitE164(national, detected);
        return;
      }
    }
    if (RegExp(r'^8[0-9]{10}$').hasMatch(compact) &&
        (widget.countryIso.toUpperCase() == 'RU' ||
            widget.countryIso.toUpperCase() == 'KZ')) {
      final national = compact.substring(1);
      _internalUpdate = true;
      widget.controller.value = TextEditingValue(
        text: national,
        selection: TextSelection.collapsed(offset: national.length),
      );
      _internalUpdate = false;
      _emitE164(national, _selectedCountry);
      return;
    }
    _emitE164(raw, _selectedCountry);
  }

  Future<void> _openCountryPicker() async {
    if (!widget.enabled) return;
    HapticUtils.tap();
    final l10n = context.l10n;
    final lang = l10n.locale.languageCode;
    final searchCtrl = TextEditingController();
    final anchorCtx = _countryPillKey.currentContext ?? context;

    final selected = await openTheavMorphPopover<CountryDialEntry>(
      anchorContext: anchorCtx,
      menuWidth: 276.0,
      menuHeight: 304.0,
      cornerRadius: 22.0,
      collapsedBuilder: (_) {
        final palette = context.theav;
        return Center(
          child: Text(
            '${_selectedCountry.iso} +${_selectedCountry.dialCode}',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: palette.primary,
            ),
          ),
        );
      },
      menuBuilder: (menuCtx, close) {
        return StatefulBuilder(
          builder: (ctx, setMenuState) {
            final palette = ctx.theav;
            final style = TheavSurfaceStyle.of(ctx);
            final query = searchCtrl.text.trim().toLowerCase();
            final filtered = query.isEmpty
                ? kTheavCountryDialCatalog
                : kTheavCountryDialCatalog.where((c) {
                    return c.iso.toLowerCase().contains(query) ||
                        '+${c.dialCode}'.contains(query) ||
                        c.dialCode.contains(query) ||
                        c.nameEn.toLowerCase().contains(query) ||
                        c.nameRu.toLowerCase().contains(query);
                  }).toList();

            return Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: style.trackFill,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(
                      children: [
                        iconoir.Search(
                          width: 16,
                          height: 16,
                          color: palette.subtext,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: searchCtrl,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: palette.onSurface,
                            ),
                            decoration: InputDecoration.collapsed(
                              hintText: ctx.l10n.trOr('search', 'Search'),
                              hintStyle: TextStyle(
                                fontSize: 13.5,
                                color: palette.subtext,
                              ),
                            ),
                            onChanged: (_) => setMenuState(() {}),
                          ),
                        ),
                        if (searchCtrl.text.isNotEmpty)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              searchCtrl.clear();
                              setMenuState(() {});
                            },
                            child: iconoir.XmarkCircle(
                              width: 16,
                              height: 16,
                              color: palette.subtext,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Divider(height: 0.5, thickness: 0.5, color: palette.divider),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 0.5,
                      thickness: 0.5,
                      indent: 52,
                      endIndent: 12,
                      color: palette.divider,
                    ),
                    itemBuilder: (_, idx) {
                      final item = filtered[idx];
                      final bool isSelected = item.iso == widget.countryIso;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticUtils.selection();
                          close(item);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              _IsoPillBadge(iso: item.iso),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  item.localizedName(lang),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: palette.onSurface,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '+${item.dialCode}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: palette.subtext,
                                ),
                              ),
                              const SizedBox(width: 6),
                              TheavCheckCircle(selected: isSelected, size: 18),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    searchCtrl.dispose();
    if (selected != null && mounted) {
      widget.onCountryChanged(selected);
      _emitE164(widget.controller.text, selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final style = TheavSurfaceStyle.of(context);
    final entry = _selectedCountry;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.label != null && widget.label!.isNotEmpty) ...[
            Text(
              widget.label!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: palette.subtext,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              GestureDetector(
                key: _countryPillKey,
                onTap: _openCountryPicker,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: palette.primary.withValues(
                      alpha: style.isDark ? 0.16 : 0.10,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${entry.iso} +${entry.dialCode}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: palette.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      iconoir.NavArrowDown(
                        width: 14,
                        height: 14,
                        color: palette.primary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  enabled: widget.enabled,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[0-9+\-\s().]'),
                    ),
                  ],
                  style: TextStyle(
                    fontSize: 15.5,
                    color: palette.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration.collapsed(
                    hintText: entry.nationalHint,
                    hintStyle: TextStyle(
                      fontSize: 15.5,
                      color: palette.subtext.withValues(alpha: 0.72),
                    ),
                  ),
                  onChanged: _handleTextChanged,
                  onSubmitted: (_) => widget.onSubmitted?.call(),
                ),
              ),
              if (widget.verified)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF34C759).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const iconoir.CheckCircle(
                        width: 13,
                        height: 13,
                        color: Color(0xFF28A745),
                      ),
                      if (widget.verifiedProviderLabel != null &&
                          widget.verifiedProviderLabel!.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Text(
                          widget.verifiedProviderLabel!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF28A745),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IsoPillBadge extends StatelessWidget {
  final String iso;

  const _IsoPillBadge({required this.iso});

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    return Container(
      width: 34,
      height: 28,
      decoration: BoxDecoration(
        color: palette.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        iso,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: palette.onSurface,
        ),
      ),
    );
  }
}
