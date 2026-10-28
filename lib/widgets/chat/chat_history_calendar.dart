import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../services/chat_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/media_cache_manager.dart';
import '../../utils/blur_utils.dart';
import '../../utils/date_time_utils.dart';

/// Telegram-style Chat History Calendar with circular media previews for days with photos/videos,
/// highlighted badges for days with text messages, and platform-adaptive navigation
/// (compact 6x7 card with ^/v & wheel on Desktop; smooth vertical scrolling months list on Mobile).
class ChatHistoryCalendar extends StatefulWidget {
  final String chatId;
  final DateTime initialDate;
  final Map<String, ChatCalendarDayInfo> initialDayMap;

  const ChatHistoryCalendar({
    Key? key,
    required this.chatId,
    required this.initialDate,
    required this.initialDayMap,
  }) : super(key: key);

  /// Formats a local [DateTime] into a `YYYY-MM-DD` map key.
  static String formatDayKey(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  /// Builds an initial local day map from the currently loaded [messages] in the chat screen.
  static Map<String, ChatCalendarDayInfo> buildLocalDayMap(
    List<Message> messages,
  ) {
    final map = <String, ChatCalendarDayInfo>{};
    // Iterate from oldest to newest so firstMessageId is the earliest message of that day
    final sorted = List<Message>.from(messages)
      ..sort((a, b) {
        final da = DateTimeUtils.parseUtcDateTime(a.createdAt) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final db = DateTimeUtils.parseUtcDateTime(b.createdAt) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return da.compareTo(db);
      });

    for (final msg in sorted) {
      if (msg.id.isEmpty) continue;
      final dt = DateTimeUtils.parseUtcDateTime(msg.createdAt);
      if (dt == null) continue;
      final key = formatDayKey(dt);
      String? previewUrl;
      final thumbUrl = msg.mediaPayload?['thumb_url']?.toString() ??
          msg.mediaPayload?['thumbnail_url']?.toString();
      final blurhash = msg.mediaPayload?['blurhash']?.toString();
      if (msg.messageType == 'image' ||
          msg.messageType == 'video' ||
          msg.messageType == 'video_note') {
        previewUrl = (thumbUrl != null && thumbUrl.isNotEmpty)
            ? thumbUrl
            : (msg.messageType == 'image' ? msg.fileUrl : null);
      }

      final existing = map[key];
      if (existing == null) {
        map[key] = ChatCalendarDayInfo(
          date: key,
          messageCount: 1,
          firstMessageId: msg.id,
          lastMessageId: msg.id,
          firstCreatedAt: msg.createdAt,
          previewUrl: previewUrl,
          previewBlurhash: blurhash,
        );
      } else {
        map[key] = ChatCalendarDayInfo(
          date: key,
          messageCount: existing.messageCount + 1,
          firstMessageId: existing.firstMessageId,
          lastMessageId: msg.id,
          firstCreatedAt: existing.firstCreatedAt,
          previewUrl: previewUrl ?? existing.previewUrl,
          previewBlurhash: existing.previewBlurhash ?? blurhash,
        );
      }
    }
    return map;
  }

  /// Opens the calendar modal and returns the selected [ChatCalendarDayInfo] if the user picks a day.
  static Future<ChatCalendarDayInfo?> show({
    required BuildContext context,
    required String chatId,
    required DateTime initialDate,
    required List<Message> currentMessages,
  }) {
    final localMap = buildLocalDayMap(currentMessages);
    final isDesktop = _isDesktopPlatform(context);

    if (isDesktop) {
      return showGeneralDialog<ChatCalendarDayInfo>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Dismiss calendar',
        barrierColor: Colors.black.withValues(alpha: 0.45),
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (ctx, anim1, anim2) {
          return Center(
            child: Material(
              color: Colors.transparent,
              child: ChatHistoryCalendar(
                chatId: chatId,
                initialDate: initialDate,
                initialDayMap: localMap,
              ),
            ),
          );
        },
        transitionBuilder: (ctx, anim, _, child) {
          final curved = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      );
    } else {
      return showModalBottomSheet<ChatCalendarDayInfo>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        builder: (ctx) {
          return FractionallySizedBox(
            heightFactor: 0.78,
            child: ChatHistoryCalendar(
              chatId: chatId,
              initialDate: initialDate,
              initialDayMap: localMap,
            ),
          );
        },
      );
    }
  }

  static bool _isDesktopPlatform(BuildContext context) {
    if (kIsWeb) {
      return MediaQuery.of(context).size.width >= 640;
    }
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  @override
  State<ChatHistoryCalendar> createState() => _ChatHistoryCalendarState();
}

class _ChatHistoryCalendarState extends State<ChatHistoryCalendar> {
  late Map<String, ChatCalendarDayInfo> _dayMap;
  late DateTime _displayedMonth; // First day of displayed month (Desktop)
  late DateTime _selectedDate;
  bool _isLoadingRemote = true;
  bool _isYearMonthPickerOpen = false;
  late int _pickerYear;
  DateTime _lastWheelScrollTime = DateTime.fromMillisecondsSinceEpoch(0);

  // Mobile vertical month list state
  final ScrollController _mobileScrollController = ScrollController();
  List<DateTime> _mobileMonths = []; // Index 0 = current month, growing older
  late DateTime _focusedMobileMonth;
  static const double _kMobileMonthItemExtent = 316.0;

  @override
  void initState() {
    super.initState();
    _dayMap = Map<String, ChatCalendarDayInfo>.from(widget.initialDayMap);
    final initLocal = widget.initialDate.toLocal();
    _selectedDate = DateTime(initLocal.year, initLocal.month, initLocal.day);
    _displayedMonth = DateTime(initLocal.year, initLocal.month, 1);
    _focusedMobileMonth = _displayedMonth;
    _pickerYear = _displayedMonth.year;
    _rebuildMobileMonthsList();
    _mobileScrollController.addListener(_onMobileScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollMobileToInitialMonth();
    });

    _fetchRemoteCalendar();
  }

  @override
  void dispose() {
    _mobileScrollController.removeListener(_onMobileScroll);
    _mobileScrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchRemoteCalendar() async {
    final remote = await ChatService.getChatCalendar(chatId: widget.chatId);
    if (!mounted) return;
    if (remote.isNotEmpty) {
      final merged = <String, ChatCalendarDayInfo>{..._dayMap};
      remote.forEach((key, remoteInfo) {
        final localInfo = merged[key];
        if (localInfo != null &&
            (remoteInfo.previewUrl == null || remoteInfo.previewUrl!.isEmpty) &&
            localInfo.previewUrl != null) {
          merged[key] = ChatCalendarDayInfo(
            date: remoteInfo.date,
            messageCount: remoteInfo.messageCount,
            firstMessageId: remoteInfo.firstMessageId,
            lastMessageId: remoteInfo.lastMessageId,
            firstCreatedAt: remoteInfo.firstCreatedAt,
            previewUrl: localInfo.previewUrl,
            previewBlurhash:
                remoteInfo.previewBlurhash ?? localInfo.previewBlurhash,
          );
        } else {
          merged[key] = remoteInfo;
        }
      });
      setState(() {
        _dayMap = merged;
        _isLoadingRemote = false;
        _rebuildMobileMonthsList();
      });
    } else {
      setState(() {
        _isLoadingRemote = false;
      });
    }
  }

  DateTime _getEarliestMonth() {
    final now = DateTimeUtils.nowProvider().toLocal();
    DateTime earliest = DateTime(now.year, now.month, 1);
    for (final key in _dayMap.keys) {
      final parts = key.split('-');
      if (parts.length == 3) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (y != null && m != null) {
          final dt = DateTime(y, m, 1);
          if (dt.isBefore(earliest)) {
            earliest = dt;
          }
        }
      }
    }
    if (_displayedMonth.isBefore(earliest)) {
      earliest = _displayedMonth;
    }
    // Always show at least 6 months of context on mobile
    final sixMonthsAgo = DateTime(now.year, now.month - 5, 1);
    if (sixMonthsAgo.isBefore(earliest)) {
      earliest = sixMonthsAgo;
    }
    return earliest;
  }

  void _rebuildMobileMonthsList() {
    final now = DateTimeUtils.nowProvider().toLocal();
    final currentMonth = DateTime(now.year, now.month, 1);
    final earliest = _getEarliestMonth();

    final months = <DateTime>[];
    DateTime cursor = currentMonth;
    while (!cursor.isBefore(earliest)) {
      months.add(cursor);
      cursor = DateTime(cursor.year, cursor.month - 1, 1);
    }
    if (months.isEmpty) {
      months.add(currentMonth);
    }
    _mobileMonths = months;
  }

  void _scrollMobileToInitialMonth() {
    if (!_mobileScrollController.hasClients) return;
    final idx = _mobileMonths.indexWhere(
      (m) =>
          m.year == _displayedMonth.year && m.month == _displayedMonth.month,
    );
    if (idx > 0) {
      final targetOffset = (idx * _kMobileMonthItemExtent).clamp(
        0.0,
        _mobileScrollController.position.maxScrollExtent,
      );
      _mobileScrollController.jumpTo(targetOffset);
    }
  }

  void _onMobileScroll() {
    if (!_mobileScrollController.hasClients || _mobileMonths.isEmpty) return;
    final offset = _mobileScrollController.offset;
    final idx =
        ((offset + _kMobileMonthItemExtent * 0.35) / _kMobileMonthItemExtent)
            .floor()
            .clamp(0, _mobileMonths.length - 1);
    final focused = _mobileMonths[idx];
    if (focused.year != _focusedMobileMonth.year ||
        focused.month != _focusedMobileMonth.month) {
      setState(() {
        _focusedMobileMonth = focused;
      });
    }
  }

  bool get _canGoToNextMonth {
    final now = DateTimeUtils.nowProvider().toLocal();
    final currentMonth = DateTime(now.year, now.month, 1);
    return _displayedMonth.isBefore(currentMonth);
  }

  void _stepMonth(int deltaMonths) {
    final now = DateTimeUtils.nowProvider().toLocal();
    final currentMonth = DateTime(now.year, now.month, 1);
    final target = DateTime(
      _displayedMonth.year,
      _displayedMonth.month + deltaMonths,
      1,
    );
    if (target.isAfter(currentMonth)) return;
    setState(() {
      _displayedMonth = target;
      _pickerYear = target.year;
    });
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && !_isYearMonthPickerOpen) {
      final now = DateTime.now();
      if (now.difference(_lastWheelScrollTime).inMilliseconds < 160) return;
      if (event.scrollDelta.dy < -6) {
        _lastWheelScrollTime = now;
        _stepMonth(-1); // Scroll up -> previous (older) month
      } else if (event.scrollDelta.dy > 6) {
        _lastWheelScrollTime = now;
        _stepMonth(1); // Scroll down -> next (newer) month
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ChatHistoryCalendar._isDesktopPlatform(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final glassEnabled = context.watch<LiquidGlassProvider>().enabled;

    final surfaceColor = glassEnabled
        ? (isDark
            ? const Color(0xFF1C1C22).withValues(alpha: 0.78)
            : Colors.white.withValues(alpha: 0.85))
        : (isDark ? const Color(0xFF1E1E24) : Colors.white);

    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);

    if (isDesktop) {
      Widget card = Container(
        width: 344,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.18),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: _buildDesktopContent(context, isDark),
      );

      if (glassEnabled) {
        card = ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: BlurUtils.createDownsampledBlur(18),
            child: card,
          ),
        );
      }
      return Listener(
        onPointerSignal: _onPointerSignal,
        child: card,
      );
    } else {
      Widget sheet = Container(
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: borderColor, width: 0.8),
        ),
        child: SafeArea(
          top: false,
          child: _buildMobileContent(context, isDark),
        ),
      );

      if (glassEnabled) {
        sheet = ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: BlurUtils.createDownsampledBlur(18),
            child: sheet,
          ),
        );
      }
      return sheet;
    }
  }

  Widget _buildDesktopContent(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    final headerTitle =
        DateTimeUtils.formatCalendarMonthYear(_displayedMonth, context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Top Header: "Октябрь 2026 г." (NO triangle prefix) + ^ / v buttons
        Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  setState(() {
                    _isYearMonthPickerOpen = !_isYearMonthPickerOpen;
                    _pickerYear = _displayedMonth.year;
                  });
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                  child: Text(
                    headerTitle,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _isYearMonthPickerOpen
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
            if (_isLoadingRemote)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.8),
                ),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              splashRadius: 18,
              icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 22),
              onPressed: () {
                if (_isYearMonthPickerOpen) {
                  setState(() => _pickerYear--);
                } else {
                  _stepMonth(-1);
                }
              },
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              splashRadius: 18,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
              onPressed: _isYearMonthPickerOpen
                  ? () {
                      final nowYear = DateTimeUtils.nowProvider().toLocal().year;
                      if (_pickerYear < nowYear) {
                        setState(() => _pickerYear++);
                      }
                    }
                  : (_canGoToNextMonth ? () => _stepMonth(1) : null),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_isYearMonthPickerOpen)
          _buildYearMonthPicker(context, isDark)
        else ...[
          _buildWeekdayHeaderRow(context),
          const SizedBox(height: 6),
          _buildDesktopSixWeekGrid(context, _displayedMonth),
        ],
      ],
    );
  }

  Widget _buildYearMonthPicker(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    final now = DateTimeUtils.nowProvider().toLocal();
    return SizedBox(
      height: 256,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '$_pickerYear',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.1,
              ),
              itemCount: 12,
              itemBuilder: (ctx, idx) {
                final m = idx + 1;
                final isFuture =
                    _pickerYear > now.year || (_pickerYear == now.year && m > now.month);
                final isSelected = _displayedMonth.year == _pickerYear &&
                    _displayedMonth.month == m;
                final label = DateTimeUtils.formatMonthNominative(m, context);

                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: isFuture
                      ? null
                      : () {
                          setState(() {
                            _displayedMonth = DateTime(_pickerYear, m, 1);
                            _isYearMonthPickerOpen = false;
                          });
                        },
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.primary.withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: isSelected
                          ? Border.all(
                              color: theme.colorScheme.primary,
                              width: 1.2,
                            )
                          : null,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isFuture
                            ? theme.colorScheme.onSurface.withValues(alpha: 0.25)
                            : (isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekdayHeaderRow(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: List.generate(7, (index) {
        final weekday = index + 1; // 1 = Monday .. 7 = Sunday
        return Expanded(
          child: Center(
            child: Text(
              DateTimeUtils.formatWeekday(weekday, context),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        );
      }),
    );
  }

  /// Desktop 6x7 grid including leading days of previous month and trailing days of next month.
  Widget _buildDesktopSixWeekGrid(BuildContext context, DateTime monthStart) {
    final firstWeekday = monthStart.weekday; // 1 (Mon) .. 7 (Sun)
    final leadingDays = firstWeekday - 1;
    final gridStart = monthStart.subtract(Duration(days: leadingDays));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(6, (weekIndex) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.5),
          child: Row(
            children: List.generate(7, (dayIndex) {
              final cellOffset = weekIndex * 7 + dayIndex;
              // Use date constructor to avoid DST shift issues
              final cellDate = DateTime(
                gridStart.year,
                gridStart.month,
                gridStart.day + cellOffset,
              );
              final isCurrentMonth = cellDate.year == monthStart.year &&
                  cellDate.month == monthStart.month;
              return Expanded(
                child: Center(
                  child: _buildDayCell(
                    context,
                    cellDate,
                    isCurrentMonth: isCurrentMonth,
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  Widget _buildMobileContent(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    final activeTitle =
        DateTimeUtils.formatCalendarMonthYear(_focusedMobileMonth, context);

    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  activeTitle,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (_isLoadingRemote)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 22),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: _buildWeekdayHeaderRow(context),
        ),
        Divider(
          height: 1,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        ),
        Expanded(
          child: ListView.builder(
            controller: _mobileScrollController,
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            itemCount: _mobileMonths.length,
            itemBuilder: (ctx, index) {
              final monthStart = _mobileMonths[index];
              final isFocused = monthStart.year == _focusedMobileMonth.year &&
                  monthStart.month == _focusedMobileMonth.month;
              return _buildMobileMonthBlock(context, monthStart, isFocused);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMobileMonthBlock(
    BuildContext context,
    DateTime monthStart,
    bool isFocused,
  ) {
    final theme = Theme.of(context);
    final monthLabel =
        DateTimeUtils.formatCalendarMonthYear(monthStart, context);
    final daysInMonth = DateUtils.getDaysInMonth(monthStart.year, monthStart.month);
    final leadingEmpty = monthStart.weekday - 1;
    final totalCells = leadingEmpty + daysInMonth;
    final weekCount = (totalCells / 7).ceil();

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isFocused ? 1.0 : 0.62,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Text(
                monthLabel,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isFocused
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ),
            ...List.generate(weekCount, (weekIdx) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: List.generate(7, (dayIdx) {
                    final cellIdx = weekIdx * 7 + dayIdx;
                    final dayNum = cellIdx - leadingEmpty + 1;
                    if (dayNum < 1 || dayNum > daysInMonth) {
                      return const Expanded(child: SizedBox(height: 40));
                    }
                    final cellDate =
                        DateTime(monthStart.year, monthStart.month, dayNum);
                    return Expanded(
                      child: Center(
                        child: _buildDayCell(
                          context,
                          cellDate,
                          isCurrentMonth: true,
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCell(
    BuildContext context,
    DateTime cellDate, {
    required bool isCurrentMonth,
  }) {
    final theme = Theme.of(context);
    final key = ChatHistoryCalendar.formatDayKey(cellDate);
    final dayInfo = _dayMap[key];
    final hasMessages = dayInfo != null &&
        dayInfo.messageCount > 0 &&
        dayInfo.firstMessageId.isNotEmpty;
    final isSelected = DateTimeUtils.isSameDay(cellDate, _selectedDate);
    final isToday = DateTimeUtils.isToday(cellDate);

    final rawPreview = dayInfo?.previewUrl;
    final resolvedPreview = (rawPreview != null && rawPreview.isNotEmpty)
        ? (AppConfig.resolveMediaUrl(rawPreview) ?? rawPreview)
        : null;

    Widget content;
    if (hasMessages && resolvedPreview != null) {
      // State 1: Day with photo/video — circular media thumbnail + dark overlay + bold white day number
      content = _CalendarMediaCircle(
        previewUrl: resolvedPreview,
        dayNumber: cellDate.day,
        isCurrentMonth: isCurrentMonth,
        isSelected: isSelected,
        accentColor: theme.colorScheme.primary,
      );
    } else if (hasMessages) {
      // State 2: Day with text/voice messages only — circular filled badge
      final badgeColor = isSelected
          ? theme.colorScheme.primary
          : theme.colorScheme.primary
              .withValues(alpha: isCurrentMonth ? 0.18 : 0.09);
      final textColor = isSelected
          ? theme.colorScheme.onPrimary
          : (isCurrentMonth
              ? theme.colorScheme.primary
              : theme.colorScheme.primary.withValues(alpha: 0.55));

      content = Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: badgeColor,
          border: isToday && !isSelected
              ? Border.all(color: theme.colorScheme.primary, width: 1.4)
              : null,
        ),
        child: Text(
          '${cellDate.day}',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
      );
    } else {
      // State 3: Day with no messages — plain muted gray number, non-clickable
      final textColor = theme.colorScheme.onSurface.withValues(
        alpha: isCurrentMonth ? 0.30 : 0.13,
      );
      content = Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: isToday
            ? BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
                  width: 1.0,
                ),
              )
            : null,
        child: Text(
          '${cellDate.day}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: textColor,
          ),
        ),
      );
    }

    if (!hasMessages) {
      return content;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Navigator.of(context).pop(dayInfo);
        },
        child: content,
      ),
    );
  }
}

class _CalendarMediaCircle extends StatelessWidget {
  final String previewUrl;
  final int dayNumber;
  final bool isCurrentMonth;
  final bool isSelected;
  final Color accentColor;

  const _CalendarMediaCircle({
    required this.previewUrl,
    required this.dayNumber,
    required this.isCurrentMonth,
    required this.isSelected,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final cachedFile = !kIsWeb
        ? MediaCacheManager.instance.getCachedFileSync(previewUrl)
        : null;

    Widget imageWidget;
    if (cachedFile != null) {
      imageWidget = Image.file(
        cachedFile,
        fit: BoxFit.cover,
        cacheWidth: 120,
        errorBuilder: (_, __, ___) => Container(color: Colors.black45),
      );
    } else {
      imageWidget = Image.network(
        previewUrl,
        fit: BoxFit.cover,
        cacheWidth: 120,
        errorBuilder: (_, __, ___) => Container(color: Colors.black45),
      );
    }

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: isSelected
            ? Border.all(color: accentColor, width: 2.2)
            : Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 0.8,
              ),
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: isCurrentMonth ? 1.0 : 0.55,
              child: imageWidget,
            ),
            Container(
              color: Colors.black.withValues(
                alpha: isCurrentMonth ? 0.32 : 0.52,
              ),
            ),
            Center(
              child: Text(
                '$dayNumber',
                style: TextStyle(
                  color: Colors.white.withValues(
                    alpha: isCurrentMonth ? 1.0 : 0.78,
                  ),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  shadows: const [
                    Shadow(
                      color: Colors.black87,
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
