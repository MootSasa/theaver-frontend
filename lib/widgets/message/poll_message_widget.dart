import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/chat/user_profile_screen.dart';
import '../../services/auth_service.dart';
import '../../services/database/app_database.dart';
import '../../utils/emoji_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../chat/telegram_avatar_stack.dart';

/// Interactive Telegram-style Poll / Quiz widget rendered inside a message bubble.
class PollMessageWidget extends StatefulWidget {
  final String chatId;
  final String messageId;
  final String currentUserId;
  final String questionFallback;
  final Map<String, dynamic>? pollData;
  final bool isMe;
  final bool isDark;
  final Color textColor;
  final Color subtextColor;
  final Color accentColor;
  final ValueChanged<Map<String, dynamic>>? onPollUpdated;

  const PollMessageWidget({
    Key? key,
    required this.chatId,
    required this.messageId,
    required this.currentUserId,
    required this.questionFallback,
    this.pollData,
    required this.isMe,
    required this.isDark,
    required this.textColor,
    required this.subtextColor,
    required this.accentColor,
    this.onPollUpdated,
  }) : super(key: key);

  static int? parseInt(dynamic val) {
    if (val == null) return null;
    if (val is int) return val;
    if (val is num) return val.toInt();
    return int.tryParse(val.toString());
  }

  static int? getPollId(Map<String, dynamic>? pollData) {
    return parseInt(pollData?['poll_id'] ?? pollData?['id']);
  }

  static Set<int> getUserVotedOptionIds(
    Map<String, dynamic>? pollData,
    String? currentUserId,
  ) {
    final result = <int>{};
    if (pollData == null || currentUserId == null || currentUserId.isEmpty) {
      return result;
    }
    final rawOpts = pollData['options'];
    bool hasVoterIdsField = false;
    if (rawOpts is List) {
      for (final item in rawOpts) {
        if (item is! Map) continue;
        final optId = parseInt(item['id']);
        final voterIds = item['voter_ids'];
        if (voterIds is List) {
          hasVoterIdsField = true;
          if (optId != null &&
              voterIds.any((v) => v.toString() == currentUserId)) {
            result.add(optId);
          }
        }
        final voters = item['voters'];
        if (voters is List) {
          hasVoterIdsField = true;
          if (optId != null &&
              voters.any((v) =>
                  v is Map &&
                  (v['user_id']?.toString() == currentUserId ||
                      v['id']?.toString() == currentUserId))) {
            result.add(optId);
          }
        }
      }
    }
    if (result.isNotEmpty || hasVoterIdsField) {
      return result;
    }
    final rawVoted = pollData['voted_option_ids'];
    if (rawVoted is List) {
      for (final item in rawVoted) {
        final id = parseInt(item);
        if (id != null) result.add(id);
      }
    }
    return result;
  }

  static bool hasUserVoted(
    Map<String, dynamic>? pollData,
    String? currentUserId,
  ) {
    return getUserVotedOptionIds(pollData, currentUserId).isNotEmpty;
  }

  static int getTotalVotes(Map<String, dynamic>? pollData) {
    if (pollData == null) return 0;
    final explicitTotal = parseInt(pollData['total_votes']);
    if (explicitTotal != null && explicitTotal > 0) return explicitTotal;
    final rawOpts = pollData['options'];
    int sum = 0;
    if (rawOpts is List) {
      for (final opt in rawOpts) {
        if (opt is Map) {
          sum += parseInt(opt['vote_count']) ?? 0;
        }
      }
    }
    return sum;
  }

  static bool canRetractVote(
    Map<String, dynamic>? pollData,
    String? currentUserId,
  ) {
    if (pollData == null) return false;
    if (pollData['is_closed'] == true) return false;
    if (pollData['is_quiz'] == true) return false;
    return hasUserVoted(pollData, currentUserId);
  }

  static bool canViewResults(
    Map<String, dynamic>? pollData,
    String? currentUserId,
  ) {
    if (pollData == null) return false;
    if (pollData['is_anonymous'] == true) return false;
    final isClosed = pollData['is_closed'] == true;
    final voted = hasUserVoted(pollData, currentUserId);
    return (voted || isClosed) && getTotalVotes(pollData) > 0;
  }

  static String formatVoteCount(
    BuildContext context,
    int count, {
    bool isQuiz = false,
  }) {
    final l10n = context.l10n;
    if (count <= 0) {
      return l10n.translate(isQuiz ? 'poll_no_answers' : 'poll_no_votes');
    }
    final mod10 = count % 10;
    final mod100 = count % 100;
    String key;
    if (mod10 == 1 && mod100 != 11) {
      key = isQuiz ? 'poll_answers_one' : 'poll_votes_one';
    } else if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      key = isQuiz ? 'poll_answers_few' : 'poll_votes_few';
    } else {
      key = isQuiz ? 'poll_answers_many' : 'poll_votes_many';
    }
    final translated = l10n.translate(key);
    if (translated == key) {
      return l10n
          .translate('poll_total_votes')
          .replaceAll('{count}', '$count');
    }
    return translated.replaceAll('{count}', '$count');
  }

  static Future<Map<String, dynamic>?> retractVote({
    required String chatId,
    required String messageId,
    required String question,
    required int pollId,
  }) async {
    try {
      final token = await AuthService.getToken();
      final dio = Dio();
      final response = await dio.post(
        '${AppConfig.baseUrl}/api/chats/$chatId/polls/$pollId/vote',
        data: {'retract': true},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final respData = response.data;
      if (respData is Map && respData['poll'] is Map) {
        final updated = Map<String, dynamic>.from(respData['poll'] as Map);
        try {
          await AppDatabase().updateMessageContent(
            messageId,
            question,
            null,
            jsonEncode(updated),
            false,
          );
        } catch (_) {}
        return updated;
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> closePoll({
    required String chatId,
    required String messageId,
    required String question,
    required int pollId,
  }) async {
    try {
      final token = await AuthService.getToken();
      final dio = Dio();
      final response = await dio.post(
        '${AppConfig.baseUrl}/api/chats/$chatId/polls/$pollId/close',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final respData = response.data;
      if (respData is Map && respData['poll'] is Map) {
        final updated = Map<String, dynamic>.from(respData['poll'] as Map);
        try {
          await AppDatabase().updateMessageContent(
            messageId,
            question,
            null,
            jsonEncode(updated),
            false,
          );
        } catch (_) {}
        return updated;
      }
    } catch (_) {}
    return null;
  }

  static void showResultsSheet(
    BuildContext context, {
    required String chatId,
    required String messageId,
    required String questionFallback,
    required Map<String, dynamic> pollData,
    required String currentUserId,
    int? initialOptionId,
  }) {
    HapticUtils.tap();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PollResultsBottomSheet(
        chatId: chatId,
        messageId: messageId,
        questionFallback: questionFallback,
        initialPollData: pollData,
        currentUserId: currentUserId,
        initialOptionId: initialOptionId,
      ),
    );
  }

  @override
  State<PollMessageWidget> createState() => _PollMessageWidgetState();
}

class _PollMessageWidgetState extends State<PollMessageWidget> {
  Map<String, dynamic>? _pollData;
  final Set<int> _selectedOptionIds = {};
  final Set<int> _submittingOptionIds = {};
  bool _isSubmitting = false;
  bool _isFetchingDetails = false;

  @override
  void initState() {
    super.initState();
    _pollData = widget.pollData != null
        ? Map<String, dynamic>.from(widget.pollData!)
        : null;
    _maybeFetchVoterProfiles();
  }

  @override
  void didUpdateWidget(covariant PollMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pollData != oldWidget.pollData && widget.pollData != null) {
      setState(() {
        _pollData = Map<String, dynamic>.from(widget.pollData!);
        if (_myVotedOptionIds.isEmpty) {
          _selectedOptionIds.clear();
        }
      });
      _maybeFetchVoterProfiles();
    }
  }

  int? get _pollId => PollMessageWidget.getPollId(_pollData);

  String get _question {
    final q = _pollData?['question']?.toString().trim();
    if (q != null && q.isNotEmpty) return q;
    return widget.questionFallback;
  }

  bool get _isAnonymous => _pollData?['is_anonymous'] == true;
  bool get _isMultiple => _pollData?['is_multiple_choice'] == true && !_isQuiz;
  bool get _isQuiz => _pollData?['is_quiz'] == true;
  bool get _isClosed => _pollData?['is_closed'] == true;
  int? get _correctOptionId =>
      PollMessageWidget.parseInt(_pollData?['correct_option_id']);

  List<Map<String, dynamic>> get _options {
    final raw = _pollData?['options'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  Set<int> get _myVotedOptionIds =>
      PollMessageWidget.getUserVotedOptionIds(_pollData, widget.currentUserId);

  int get _totalVotes => PollMessageWidget.getTotalVotes(_pollData);

  bool get _hasVoterProfiles {
    for (final opt in _options) {
      final count = PollMessageWidget.parseInt(opt['vote_count']) ?? 0;
      if (count > 0) {
        final voters = opt['voters'];
        if (voters is List && voters.isNotEmpty) {
          return true;
        }
        return false;
      }
    }
    return true;
  }

  List<Map<String, dynamic>> _getOptionVoters(Map<String, dynamic> opt) {
    final raw = opt['voters'];
    if (raw is List && raw.isNotEmpty) {
      return raw
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return const [];
  }

  List<Map<String, dynamic>> get _recentVoters {
    final raw = _pollData?['recent_voters'];
    if (raw is List && raw.isNotEmpty) {
      return raw
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final opt in _options) {
      for (final v in _getOptionVoters(opt)) {
        final uid = (v['user_id'] ?? v['id'] ?? '').toString();
        if (uid.isNotEmpty && seen.add(uid)) {
          result.add(v);
          if (result.length >= 3) return result;
        }
      }
    }
    return result;
  }

  Future<void> _maybeFetchVoterProfiles() async {
    if (_isAnonymous || _totalVotes <= 0 || _hasVoterProfiles || _isFetchingDetails) {
      return;
    }
    final pollId = _pollId;
    if (pollId == null) return;

    _isFetchingDetails = true;
    try {
      final token = await AuthService.getToken();
      final dio = Dio();
      final response = await dio.get(
        '${AppConfig.baseUrl}/api/chats/${widget.chatId}/polls/$pollId/results',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (!mounted) return;
      final data = response.data;
      if (data is Map && data['options'] is List) {
        final updated = Map<String, dynamic>.from(data);
        setState(() {
          _pollData = updated;
        });
        widget.onPollUpdated?.call(updated);
        try {
          await AppDatabase().updateMessageContent(
            widget.messageId,
            _question,
            null,
            jsonEncode(updated),
            false,
          );
        } catch (_) {}
      }
    } catch (_) {
    } finally {
      _isFetchingDetails = false;
    }
  }

  Future<void> _submitVote(List<int> optionIds, {bool retract = false}) async {
    final pollId = _pollId;
    if (pollId == null || _isSubmitting) return;

    HapticUtils.tap();
    setState(() {
      _isSubmitting = true;
      _submittingOptionIds
        ..clear()
        ..addAll(optionIds);
    });

    try {
      final token = await AuthService.getToken();
      final dio = Dio();
      final response = await dio.post(
        '${AppConfig.baseUrl}/api/chats/${widget.chatId}/polls/$pollId/vote',
        data: retract
            ? {'retract': true}
            : {
                'option_id': optionIds.first,
                'option_ids': optionIds,
              },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (!mounted) return;
      final respData = response.data;
      if (respData is Map && respData['poll'] is Map) {
        final updated = Map<String, dynamic>.from(respData['poll'] as Map);
        setState(() {
          _pollData = updated;
          _selectedOptionIds.clear();
        });
        widget.onPollUpdated?.call(updated);
        try {
          await AppDatabase().updateMessageContent(
            widget.messageId,
            _question,
            null,
            jsonEncode(updated),
            false,
          );
        } catch (_) {}
      }
    } catch (_) {
      // Ignore transient errors
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _submittingOptionIds.clear();
        });
      }
    }
  }

  String _buildPollSubtitle(BuildContext context) {
    final l10n = context.l10n;
    if (_isClosed) {
      return l10n.translate(_isQuiz ? 'poll_closed_quiz' : 'poll_closed');
    }
    final List<String> parts = [];
    if (_isQuiz) {
      parts.add(l10n.translate(
        _isAnonymous ? 'poll_type_anonymous_quiz' : 'poll_type_quiz',
      ));
    } else {
      parts.add(l10n.translate(
        _isAnonymous ? 'poll_type_anonymous_poll' : 'poll_type_poll',
      ));
    }
    if (_isMultiple) {
      parts.add(l10n.translate('poll_create_multiple').toLowerCase());
    }
    return parts.join(' • ');
  }

  void _openResultsSheet({int? initialOptionId}) {
    if (_pollData == null || _isAnonymous) return;
    PollMessageWidget.showResultsSheet(
      context,
      chatId: widget.chatId,
      messageId: widget.messageId,
      questionFallback: _question,
      pollData: _pollData!,
      currentUserId: widget.currentUserId,
      initialOptionId: initialOptionId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    final myVotedIds = _myVotedOptionIds;
    final bool hasVoted = myVotedIds.isNotEmpty;
    final bool showResults = hasVoted || _isClosed;
    final int totalVotes = _totalVotes;
    final int? correctOptId = _correctOptionId;
    final recentVoters = _recentVoters;

    final Color barAccent = widget.isMe
        ? widget.textColor.withValues(alpha: 0.9)
        : widget.accentColor;

    final bool canOpenResults = !_isAnonymous && showResults && totalVotes > 0;

    return MetaData(
      metaData: 'block_element',
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 245.0,
          maxWidth: 320.0,
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 2.0, bottom: 2.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Question
              RichText(
                text: EmojiUtils.buildEmojiTextSpan(
                  _question,
                  style: TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.w700,
                    color: widget.textColor,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: 4.0),

              // Subtitle (Poll type + optional recent voter avatars)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_isAnonymous && recentVoters.isNotEmpty) ...[
                    _VoterAvatarStack(
                      voters: recentVoters,
                      maxCount: 3,
                      size: 16.0,
                      borderColor: widget.isDark
                          ? const Color(0xFF1E2733)
                          : Colors.white,
                    ),
                    const SizedBox(width: 6.0),
                  ],
                  Flexible(
                    child: Text(
                      _buildPollSubtitle(context),
                      style: TextStyle(
                        fontSize: 12.0,
                        color: widget.subtextColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10.0),

              // Options
              if (options.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: Text(
                    PollMessageWidget.formatVoteCount(
                      context,
                      0,
                      isQuiz: _isQuiz,
                    ),
                    style: TextStyle(fontSize: 13.0, color: widget.subtextColor),
                  ),
                )
              else
                ...options.map((opt) {
                  final int optId = PollMessageWidget.parseInt(opt['id']) ?? 0;
                  final String optText = opt['text']?.toString() ?? '';
                  final int voteCount =
                      PollMessageWidget.parseInt(opt['vote_count']) ?? 0;
                  final bool isVotedByMe = myVotedIds.contains(optId);
                  final bool isSelectedDraft =
                      _selectedOptionIds.contains(optId);
                  final bool isOptionSubmitting =
                      _isSubmitting && _submittingOptionIds.contains(optId);
                  final optionVoters = _getOptionVoters(opt);

                  final double fraction = totalVotes > 0
                      ? (voteCount / totalVotes).clamp(0.0, 1.0)
                      : 0.0;
                  final int percent = (fraction * 100).round();

                  final bool isCorrectQuizOption = _isQuiz &&
                      showResults &&
                      correctOptId != null &&
                      optId == correctOptId;
                  final bool isWrongQuizVote = _isQuiz &&
                      showResults &&
                      isVotedByMe &&
                      correctOptId != null &&
                      optId != correctOptId;

                  Color optionBarColor = barAccent;
                  if (isCorrectQuizOption) {
                    optionBarColor = widget.isDark
                        ? const Color(0xFF4ADE80)
                        : const Color(0xFF16A34A);
                  } else if (isWrongQuizVote) {
                    optionBarColor = const Color(0xFFEF4444);
                  }

                  // Only handle option taps BEFORE the user has voted and while poll is open.
                  // Once voted or closed, tapping the option does NOT delete the vote;
                  // instead, it either lets the parent message bubble open its context menu
                  // (where "Retract Vote" / "Stop Poll" live), or tapping voter avatars opens results.
                  final VoidCallback? optionTapHandler =
                      (_isClosed || _isSubmitting || showResults)
                          ? null
                          : () {
                              if (_isMultiple) {
                                HapticUtils.tap();
                                setState(() {
                                  if (_selectedOptionIds.contains(optId)) {
                                    _selectedOptionIds.remove(optId);
                                  } else {
                                    _selectedOptionIds.add(optId);
                                  }
                                });
                              } else {
                                _submitVote([optId]);
                              }
                            };

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8.0),
                      onTap: optionTapHandler,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4.0,
                          horizontal: 2.0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Left indicator: radio/checkbox before voting, percentage after voting
                                if (!showResults)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 10.0),
                                    child: SizedBox(
                                      width: 20.0,
                                      height: 20.0,
                                      child: isOptionSubmitting
                                          ? Padding(
                                              padding: const EdgeInsets.all(2.0),
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.0,
                                                valueColor:
                                                    AlwaysStoppedAnimation<Color>(
                                                  barAccent,
                                                ),
                                              ),
                                            )
                                          : Container(
                                              decoration: BoxDecoration(
                                                shape: _isMultiple
                                                    ? BoxShape.rectangle
                                                    : BoxShape.circle,
                                                borderRadius: _isMultiple
                                                    ? BorderRadius.circular(5.0)
                                                    : null,
                                                color: isSelectedDraft
                                                    ? barAccent
                                                    : Colors.transparent,
                                                border: Border.all(
                                                  color: isSelectedDraft
                                                      ? barAccent
                                                      : widget.subtextColor
                                                          .withValues(alpha: 0.65),
                                                  width: 1.8,
                                                ),
                                              ),
                                              child: isSelectedDraft
                                                  ? Icon(
                                                      Icons.check,
                                                      size: 14.0,
                                                      color: widget.isMe &&
                                                              widget.isDark
                                                          ? Colors.black87
                                                          : Colors.white,
                                                    )
                                                  : null,
                                            ),
                                    ),
                                  )
                                else
                                  SizedBox(
                                    width: 44.0,
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 6.0),
                                      child: Text(
                                        '$percent%',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontSize: 13.0,
                                          fontWeight: FontWeight.w700,
                                          color: widget.textColor,
                                        ),
                                      ),
                                    ),
                                  ),

                                // Option text
                                Expanded(
                                  child: RichText(
                                    text: EmojiUtils.buildEmojiTextSpan(
                                      optText,
                                      style: TextStyle(
                                        fontSize: 15.0,
                                        fontWeight:
                                            (isVotedByMe || isCorrectQuizOption)
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                        color: widget.textColor,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ),

                                // Voter avatars next to the option in non-anonymous polls
                                if (showResults &&
                                    !_isAnonymous &&
                                    optionVoters.isNotEmpty)
                                  GestureDetector(
                                    onTap: () =>
                                        _openResultsSheet(initialOptionId: optId),
                                    behavior: HitTestBehavior.opaque,
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 6.0),
                                      child: _VoterAvatarStack(
                                        voters: optionVoters,
                                        maxCount: 3,
                                        size: 18.0,
                                        borderColor: widget.isDark
                                            ? const Color(0xFF1E2733)
                                            : Colors.white,
                                      ),
                                    ),
                                  ),

                                // Right status icon (voted check / quiz correct / quiz wrong)
                                if (showResults &&
                                    (isVotedByMe || isCorrectQuizOption))
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6.0),
                                    child: Icon(
                                      isWrongQuizVote
                                          ? Icons.cancel_rounded
                                          : Icons.check_circle_rounded,
                                      size: 17.0,
                                      color: optionBarColor,
                                    ),
                                  ),
                              ],
                            ),

                            // Animated progress bar when showing results
                            if (showResults) ...[
                              const SizedBox(height: 5.0),
                              Padding(
                                padding: const EdgeInsets.only(left: 44.0),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3.0),
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween<double>(
                                      begin: 0.0,
                                      end: math.max(
                                        fraction,
                                        voteCount > 0 ? 0.04 : 0.0,
                                      ),
                                    ),
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeOutCubic,
                                    builder: (context, animValue, _) {
                                      return LinearProgressIndicator(
                                        value: animValue,
                                        minHeight: 5.0,
                                        backgroundColor: widget.textColor
                                            .withValues(alpha: 0.12),
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          optionBarColor,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }),

              // Multiple-choice "Vote" button when options are selected
              if (_isMultiple && !showResults && !_isClosed)
                Padding(
                  padding: const EdgeInsets.only(top: 2.0, bottom: 4.0),
                  child: SizedBox(
                    width: double.infinity,
                    height: 36.0,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: _selectedOptionIds.isNotEmpty
                            ? barAccent.withValues(alpha: 0.15)
                            : Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: (_selectedOptionIds.isEmpty || _isSubmitting)
                          ? null
                          : () => _submitVote(_selectedOptionIds.toList()),
                      child: Text(
                        context.l10n.translate('poll_vote'),
                        style: TextStyle(
                          fontSize: 14.0,
                          fontWeight: FontWeight.w600,
                          color: _selectedOptionIds.isNotEmpty
                              ? barAccent
                              : widget.subtextColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                ),

              // Footer: Total votes count OR "View Results" button (Telegram style)
              if (canOpenResults) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 2.0, bottom: 6.0),
                  child: Text(
                    PollMessageWidget.formatVoteCount(
                      context,
                      totalVotes,
                      isQuiz: _isQuiz,
                    ),
                    style: TextStyle(
                      fontSize: 12.0,
                      color: widget.subtextColor,
                    ),
                  ),
                ),
                Divider(
                  height: 1.0,
                  thickness: 0.6,
                  color: widget.textColor.withValues(alpha: 0.12),
                ),
                const SizedBox(height: 2.0),
                SizedBox(
                  width: double.infinity,
                  height: 34.0,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                    ),
                    onPressed: () => _openResultsSheet(),
                    child: Text(
                      context.l10n.translate('poll_view_results'),
                      style: TextStyle(
                        fontSize: 14.0,
                        fontWeight: FontWeight.w600,
                        color: barAccent,
                      ),
                    ),
                  ),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Center(
                    child: Text(
                      PollMessageWidget.formatVoteCount(
                        context,
                        totalVotes,
                        isQuiz: _isQuiz,
                      ),
                      style: TextStyle(
                        fontSize: 12.0,
                        color: widget.subtextColor,
                      ),
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

/// Overlapping stack of mini circular avatars for non-anonymous poll voters.
class _VoterAvatarStack extends StatelessWidget {
  final List<Map<String, dynamic>> voters;
  final int maxCount;
  final double size;
  final Color borderColor;

  const _VoterAvatarStack({
    Key? key,
    required this.voters,
    this.maxCount = 3,
    this.size = 18.0,
    required this.borderColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TelegramAvatarStack(
      users: voters,
      maxCount: maxCount,
      size: size,
      step: size * 0.68,
      gap: 1.5,
    );
  }
}

/// Telegram-style Bottom Sheet showing full Poll Results and the list of all voters per option.
class _PollResultsBottomSheet extends StatefulWidget {
  final String chatId;
  final String messageId;
  final String questionFallback;
  final Map<String, dynamic> initialPollData;
  final String currentUserId;
  final int? initialOptionId;

  const _PollResultsBottomSheet({
    Key? key,
    required this.chatId,
    required this.messageId,
    required this.questionFallback,
    required this.initialPollData,
    required this.currentUserId,
    this.initialOptionId,
  }) : super(key: key);

  @override
  State<_PollResultsBottomSheet> createState() =>
      _PollResultsBottomSheetState();
}

class _PollResultsBottomSheetState extends State<_PollResultsBottomSheet> {
  late Map<String, dynamic> _pollData;
  bool _isLoading = false;
  int? _selectedFilterOptionId;

  @override
  void initState() {
    super.initState();
    _pollData = Map<String, dynamic>.from(widget.initialPollData);
    _selectedFilterOptionId = widget.initialOptionId;
    _refreshResults();
  }

  Future<void> _refreshResults() async {
    final pollId = PollMessageWidget.getPollId(_pollData);
    if (pollId == null) return;

    setState(() => _isLoading = true);
    try {
      final token = await AuthService.getToken();
      final dio = Dio();
      final response = await dio.get(
        '${AppConfig.baseUrl}/api/chats/${widget.chatId}/polls/$pollId/results',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (!mounted) return;
      final data = response.data;
      if (data is Map && data['options'] is List) {
        final updated = Map<String, dynamic>.from(data);
        setState(() {
          _pollData = updated;
        });
        try {
          await AppDatabase().updateMessageContent(
            widget.messageId,
            _question,
            null,
            jsonEncode(updated),
            false,
          );
        } catch (_) {}
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String get _question {
    final q = _pollData['question']?.toString().trim();
    if (q != null && q.isNotEmpty) return q;
    return widget.questionFallback;
  }

  bool get _isQuiz => _pollData['is_quiz'] == true;
  int? get _correctOptionId =>
      PollMessageWidget.parseInt(_pollData['correct_option_id']);
  int get _totalVotes => PollMessageWidget.getTotalVotes(_pollData);

  List<Map<String, dynamic>> get _options {
    final raw = _pollData['options'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  List<Map<String, dynamic>> _getOptionVoters(Map<String, dynamic> opt) {
    final raw = opt['voters'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final options = _options;
    final totalVotes = _totalVotes;
    final correctOptId = _correctOptionId;

    final filteredOptions = _selectedFilterOptionId == null
        ? options
        : options
            .where((o) =>
                PollMessageWidget.parseInt(o['id']) == _selectedFilterOptionId)
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF17212B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 4),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.translate('poll_results_title'),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            PollMessageWidget.formatVoteCount(
                              context,
                              totalVotes,
                              isQuiz: _isQuiz,
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.only(right: 8.0),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Question card
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: RichText(
                  text: EmojiUtils.buildEmojiTextSpan(
                    _question,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),

              // Option filter chips
              if (options.length > 1)
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            '${context.l10n.translate('poll_results')} ($totalVotes)',
                          ),
                          selected: _selectedFilterOptionId == null,
                          onSelected: (_) {
                            setState(() => _selectedFilterOptionId = null);
                          },
                        ),
                      ),
                      ...options.map((opt) {
                        final optId = PollMessageWidget.parseInt(opt['id']);
                        final optText = opt['text']?.toString() ?? '';
                        final count =
                            PollMessageWidget.parseInt(opt['vote_count']) ?? 0;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              '$optText ($count)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            selected: _selectedFilterOptionId == optId,
                            onSelected: (_) {
                              setState(() {
                                _selectedFilterOptionId =
                                    _selectedFilterOptionId == optId
                                        ? null
                                        : optId;
                              });
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),

              const SizedBox(height: 8),
              Divider(
                height: 1,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
              ),

              // Options and voters list
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filteredOptions.length,
                  itemBuilder: (context, index) {
                    final opt = filteredOptions[index];
                    final optId = PollMessageWidget.parseInt(opt['id']) ?? 0;
                    final optText = opt['text']?.toString() ?? '';
                    final voteCount =
                        PollMessageWidget.parseInt(opt['vote_count']) ?? 0;
                    final voters = _getOptionVoters(opt);
                    final int percent = totalVotes > 0
                        ? ((voteCount / totalVotes).clamp(0.0, 1.0) * 100)
                            .round()
                        : 0;
                    final bool isCorrect =
                        _isQuiz && correctOptId != null && optId == correctOptId;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Option section header
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: isDark ? 0.05 : 0.04),
                          child: Row(
                            children: [
                              if (isCorrect)
                                const Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: Icon(
                                    Icons.check_circle_rounded,
                                    size: 18,
                                    color: Color(0xFF16A34A),
                                  ),
                                ),
                              Expanded(
                                child: RichText(
                                  text: EmojiUtils.buildEmojiTextSpan(
                                    optText,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$percent%',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$voteCount',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Voters for this option
                        if (voters.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            child: Text(
                              context.l10n.translate('poll_no_votes_for_option'),
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.45),
                              ),
                            ),
                          )
                        else
                          ...voters.map((voter) {
                            final voterId =
                                (voter['user_id'] ?? voter['id'] ?? '')
                                    .toString();
                            final displayName = (voter['display_name'] ??
                                    voter['username'] ??
                                    'User')
                                .toString()
                                .trim();
                            final username =
                                (voter['username'] ?? '').toString().trim();
                            final avatarUrl = voter['avatar_url']?.toString();
                            final validAvatar = getValidAvatarUrl(avatarUrl);
                            final initial = displayName.isNotEmpty
                                ? displayName.characters.first.toUpperCase()
                                : '?';

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 2,
                              ),
                              leading: CircleAvatar(
                                radius: 19,
                                backgroundColor: theme.colorScheme.primary,
                                backgroundImage: validAvatar != null
                                    ? avatarImageProvider(validAvatar)
                                    : null,
                                child: validAvatar == null
                                    ? Text(
                                        initial,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      )
                                    : null,
                              ),
                              title: Text(
                                displayName,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              subtitle: username.isNotEmpty &&
                                      username != displayName
                                  ? Text(
                                      '@$username',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.55),
                                      ),
                                    )
                                  : null,
                              onTap: voterId.isEmpty
                                  ? null
                                  : () {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        SwipeBackPageRoute(
                                          builder: (_) => UserProfileScreen(
                                            userId:
                                                voterId == widget.currentUserId
                                                    ? ''
                                                    : voterId,
                                            initialName: displayName,
                                            initialAvatarUrl: avatarUrl,
                                          ),
                                        ),
                                      );
                                    },
                            );
                          }),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}