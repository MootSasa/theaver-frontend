import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// Centralized utility for parsing and formatting dates & times in the user device's local timezone.
class DateTimeUtils {
  /// Clock provider to allow test environments to mock current time.
  static DateTime Function() nowProvider = () => DateTime.now();

  static final RegExp _tzOffsetRegex = RegExp(r'[+-]\d{2}(:?\d{2})?$');
  static const int _kMaxDateCacheSize = 1024;
  static final Map<String, DateTime> _parsedCache = <String, DateTime>{};
  static final Map<String, String> _hhmmCache = <String, String>{};

  /// Safely parses an incoming timestamp (from JSON, DB, or WebSocket) into a local [DateTime].
  /// If the timestamp string has no timezone indicator, it is assumed to be in UTC (Greenwich)
  /// as sent by the server, and then converted to the local device timezone via [toLocal()].
  static DateTime? parseUtcDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) {
      return raw.toLocal();
    }
    if (raw is String) {
      final cached = _parsedCache[raw];
      if (cached != null) return cached;
    }
    final str = raw.toString().trim();
    if (str.isEmpty) return null;
    final cachedTrimmed = _parsedCache[str];
    if (cachedTrimmed != null) return cachedTrimmed;

    String normalized = str;
    // If no timezone offset (+/-HH:MM) and no 'Z' suffix, append 'Z' so it is parsed as UTC (Greenwich)
    if (!normalized.endsWith('Z') &&
        !normalized.endsWith('z') &&
        !_tzOffsetRegex.hasMatch(normalized)) {
      normalized = '${normalized}Z';
    }

    final parsed = DateTime.tryParse(normalized)?.toLocal();
    if (parsed != null) {
      if (_parsedCache.length >= _kMaxDateCacheSize) {
        _parsedCache.remove(_parsedCache.keys.first);
      }
      _parsedCache[str] = parsed;
    }
    return parsed;
  }

  /// Returns midnight (00:00:00) of the given date in local device timezone.
  static DateTime startOfDay(DateTime dt) {
    final local = dt.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// Checks if [dt] falls on the same calendar day as [reference] in local device timezone.
  static bool isSameDay(DateTime dt, DateTime reference) {
    final l1 = dt.toLocal();
    final l2 = reference.toLocal();
    return l1.year == l2.year && l1.month == l2.month && l1.day == l2.day;
  }

  /// Checks if [dt] is today on the current device (or relative to [now]).
  static bool isToday(DateTime dt, {DateTime? now}) {
    return isSameDay(dt, now ?? nowProvider());
  }

  /// Checks if [dt] was yesterday on the current device (or relative to [now]).
  static bool isYesterday(DateTime dt, {DateTime? now}) {
    final current = now ?? nowProvider();
    final today = startOfDay(current);
    final yesterday = today.subtract(const Duration(days: 1));
    return isSameDay(dt, yesterday);
  }

  /// Formats the last seen presence status text in the user device's local timezone.
  /// Handles "был(а) только что", "был(а) N мин. назад", "был(а) сегодня в HH:mm",
  /// "был(а) вчера в HH:mm" and fallback "был(а) недавно".
  static String formatLastSeen(
    DateTime? lastSeen,
    BuildContext context, {
    DateTime? now,
  }) {
    if (lastSeen == null) {
      return context.l10n.translate('chat_status_last_seen_recently');
    }

    final localLastSeen = lastSeen.toLocal();
    final currentNow = (now ?? nowProvider()).toLocal();
    final difference = currentNow.difference(localLastSeen);

    // If future (clock skew) or < 60 seconds ago
    if (difference.isNegative || difference.inSeconds < 60) {
      return context.l10n.translate('chat_status_last_seen_just_now');
    }

    // Within 60 minutes
    if (difference.inMinutes < 60) {
      return context.l10n
          .translate('chat_status_last_seen_minutes')
          .replaceAll('{m}', difference.inMinutes.toString());
    }

    // Calendar comparison on the current user device
    final today = startOfDay(currentNow);
    final yesterday = today.subtract(const Duration(days: 1));
    final lastSeenDay = startOfDay(localLastSeen);

    final timeStr =
        '${localLastSeen.hour.toString().padLeft(2, '0')}:${localLastSeen.minute.toString().padLeft(2, '0')}';

    if (lastSeenDay == today) {
      return context.l10n
          .translate('chat_status_last_seen_today')
          .replaceAll('{time}', timeStr);
    }
    if (lastSeenDay == yesterday) {
      return context.l10n
          .translate('chat_status_last_seen_yesterday')
          .replaceAll('{time}', timeStr);
    }

    return context.l10n.translate('chat_status_last_seen_recently');
  }

  /// Formats a time string (HH:mm) in the local device timezone from any UTC/local timestamp.
  static String formatTimeHHmm(dynamic timestamp) {
    if (timestamp == null) return '';
    if (timestamp is String) {
      final cached = _hhmmCache[timestamp];
      if (cached != null) return cached;
    }
    final dt = parseUtcDateTime(timestamp);
    if (dt == null) return '';
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final formatted = '$hour:$minute';
    if (timestamp is String && timestamp.isNotEmpty) {
      if (_hhmmCache.length >= _kMaxDateCacheSize) {
        _hhmmCache.remove(_hhmmCache.keys.first);
      }
      _hhmmCache[timestamp] = formatted;
    }
    return formatted;
  }

  static const List<String> _ruMonthsGenitive = [
    '',
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

  static const List<String> _ruMonthsNominative = [
    '',
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];

  /// Formats date separator label ("Сегодня", "Вчера", "27 октября", "27 октября 2025")
  /// in local device timezone, localized for the current user language if [context] is provided.
  static String formatDateSeparator(DateTime dt, {BuildContext? context, DateTime? now}) {
    final localDt = dt.toLocal();
    final currentNow = (now ?? nowProvider()).toLocal();
    final today = startOfDay(currentNow);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateDay = startOfDay(localDt);

    if (dateDay == today) {
      return context != null ? context.l10n.translate('date_today') : 'Сегодня';
    }
    if (dateDay == yesterday) {
      return context != null ? context.l10n.translate('date_yesterday') : 'Вчера';
    }

    final monthIdx = localDt.month.clamp(1, 12);
    if (context == null) {
      final monthName = _ruMonthsGenitive[monthIdx];
      if (localDt.year == today.year) {
        return '${localDt.day} $monthName';
      }
      return '${localDt.day} $monthName ${localDt.year}';
    }

    final l10n = context.l10n;
    final monthName = l10n.translate('month_gen_$monthIdx');
    final effectiveMonth =
        monthName == 'month_gen_$monthIdx' ? _ruMonthsGenitive[monthIdx] : monthName;

    if (localDt.year == today.year) {
      final pattern = l10n.translate('date_day_month');
      if (pattern == 'date_day_month') {
        return '${localDt.day} $effectiveMonth';
      }
      return pattern
          .replaceAll('{day}', localDt.day.toString())
          .replaceAll('{month}', effectiveMonth);
    } else {
      final pattern = l10n.translate('date_day_month_year');
      if (pattern == 'date_day_month_year') {
        return '${localDt.day} $effectiveMonth ${localDt.year}';
      }
      return pattern
          .replaceAll('{day}', localDt.day.toString())
          .replaceAll('{month}', effectiveMonth)
          .replaceAll('{year}', localDt.year.toString());
    }
  }

  /// Formats calendar month and year header (e.g., "Октябрь 2026 г." or "October 2026")
  /// without any triangle prefix.
  static String formatCalendarMonthYear(DateTime dt, BuildContext context) {
    final l10n = context.l10n;
    final monthIdx = dt.month.clamp(1, 12);
    final monthName = l10n.translate('month_nom_$monthIdx');
    final effectiveMonth =
        monthName == 'month_nom_$monthIdx' ? _ruMonthsNominative[monthIdx] : monthName;
    final pattern = l10n.translate('calendar_month_year');
    if (pattern == 'calendar_month_year') {
      return '$effectiveMonth ${dt.year} г.';
    }
    return pattern
        .replaceAll('{month}', effectiveMonth)
        .replaceAll('{year}', dt.year.toString());
  }

  /// Formats standalone localized month name in nominative case (1..12).
  static String formatMonthNominative(int month, BuildContext context) {
    final monthIdx = month.clamp(1, 12);
    final monthName = context.l10n.translate('month_nom_$monthIdx');
    return monthName == 'month_nom_$monthIdx' ? _ruMonthsNominative[monthIdx] : monthName;
  }

  /// Formats the abbreviated localized weekday (1 = Monday, ..., 7 = Sunday)
  static String formatWeekday(int weekday, BuildContext context) {
    switch (weekday) {
      case DateTime.monday:
        return context.l10n.translate('weekday_mon');
      case DateTime.tuesday:
        return context.l10n.translate('weekday_tue');
      case DateTime.wednesday:
        return context.l10n.translate('weekday_wed');
      case DateTime.thursday:
        return context.l10n.translate('weekday_thu');
      case DateTime.friday:
        return context.l10n.translate('weekday_fri');
      case DateTime.saturday:
        return context.l10n.translate('weekday_sat');
      case DateTime.sunday:
        return context.l10n.translate('weekday_sun');
      default:
        return '';
    }
  }

  /// Formats a message read/listened timestamp in local device timezone:
  /// "сегодня в HH:mm", "вчера в HH:mm", or "DD.MM.YYYY в HH:mm".
  static String formatReceiptTimestamp(
    dynamic raw,
    BuildContext context, {
    DateTime? now,
  }) {
    final dt = parseUtcDateTime(raw);
    if (dt == null) return '';
    final localDt = dt.toLocal();
    final currentNow = (now ?? nowProvider()).toLocal();
    final today = startOfDay(currentNow);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateDay = startOfDay(localDt);

    final timeStr =
        '${localDt.hour.toString().padLeft(2, '0')}:${localDt.minute.toString().padLeft(2, '0')}';

    if (dateDay == today) {
      return context.l10n
          .translate('msg_receipt_today_at')
          .replaceAll('{time}', timeStr);
    }
    if (dateDay == yesterday) {
      return context.l10n
          .translate('msg_receipt_yesterday_at')
          .replaceAll('{time}', timeStr);
    }
    final dateStr =
        '${localDt.day.toString().padLeft(2, '0')}.${localDt.month.toString().padLeft(2, '0')}.${localDt.year}';
    return context.l10n
        .translate('profile_date_at_time')
        .replaceAll('{date}', dateStr)
        .replaceAll('{time}', timeStr);
  }
}
