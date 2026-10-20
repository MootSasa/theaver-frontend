import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../utils/emoji_utils.dart';
import '../../utils/haptic_utils.dart';

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
  }) : super(key: key);

  @override
  State<PollMessageWidget> createState() => _PollMessageWidgetState();
}

class _PollMessageWidgetState extends State<PollMessageWidget> {
  Map<String, dynamic>? _pollData;
  final Set<int> _selectedOptionIds = {};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _pollData = widget.pollData != null
        ? Map<String, dynamic>.from(widget.pollData!)
        : null;
  }

  @override
  void didUpdateWidget(covariant PollMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pollData != oldWidget.pollData && widget.pollData != null) {
      setState(() {
        _pollData = Map<String, dynamic>.from(widget.pollData!);
      });
    }
  }

  int? _parseInt(dynamic val) {
    if (val == null) return null;
    if (val is int) return val;
    if (val is num) return val.toInt();
    return int.tryParse(val.toString());
  }

  int? get _pollId => _parseInt(_pollData?['poll_id'] ?? _pollData?['id']);

  String get _question {
    final q = _pollData?['question']?.toString().trim();
    if (q != null && q.isNotEmpty) return q;
    return widget.questionFallback;
  }

  bool get _isAnonymous => _pollData?['is_anonymous'] == true;
  bool get _isMultiple => _pollData?['is_multiple_choice'] == true;
  bool get _isQuiz => _pollData?['is_quiz'] == true;
  bool get _isClosed => _pollData?['is_closed'] == true;
  int? get _correctOptionId => _parseInt(_pollData?['correct_option_id']);

  List<Map<String, dynamic>> get _options {
    final raw = _pollData?['options'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  Set<int> get _myVotedOptionIds {
    final result = <int>{};
    final opts = _options;
    bool hasVoterIdsField = false;
    for (final opt in opts) {
      final optId = _parseInt(opt['id']);
      final voterIds = opt['voter_ids'];
      if (voterIds is List) {
        hasVoterIdsField = true;
        if (optId != null &&
            voterIds.any((v) => v.toString() == widget.currentUserId)) {
          result.add(optId);
        }
      }
    }
    if (result.isNotEmpty || hasVoterIdsField) {
      return result;
    }
    final rawVoted = _pollData?['voted_option_ids'];
    if (rawVoted is List) {
      for (final item in rawVoted) {
        final id = _parseInt(item);
        if (id != null) result.add(id);
      }
    }
    return result;
  }

  int get _totalVotes {
    final explicitTotal = _parseInt(_pollData?['total_votes']);
    if (explicitTotal != null && explicitTotal > 0) return explicitTotal;
    int sum = 0;
    for (final opt in _options) {
      sum += _parseInt(opt['vote_count']) ?? 0;
    }
    return sum;
  }

  Future<void> _submitVote(List<int> optionIds, {bool retract = false}) async {
    final pollId = _pollId;
    if (pollId == null || _isSubmitting) return;

    HapticUtils.tap();
    setState(() => _isSubmitting = true);

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
        setState(() {
          _pollData = Map<String, dynamic>.from(respData['poll'] as Map);
          if (retract) {
            _selectedOptionIds.clear();
          }
        });
      }
    } catch (_) {
      // Ignore transient errors
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String _buildPollSubtitle(BuildContext context) {
    if (_isClosed) {
      return context.l10n.translate('poll_closed');
    }
    final List<String> parts = [];
    if (_isQuiz) {
      parts.add(_isAnonymous ? 'Анонимная викторина' : 'Викторина');
    } else {
      parts.add(_isAnonymous ? 'Анонимный опрос' : 'Опрос');
    }
    if (_isMultiple) {
      parts.add(context.l10n.translate('poll_create_multiple').toLowerCase());
    }
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    final myVotedIds = _myVotedOptionIds;
    final bool hasVoted = myVotedIds.isNotEmpty;
    final bool showResults = hasVoted || _isClosed;
    final int totalVotes = _totalVotes;
    final int? correctOptId = _correctOptionId;

    final Color barAccent = widget.isMe
        ? widget.textColor.withValues(alpha: 0.9)
        : widget.accentColor;

    return MetaData(
      metaData: 'block_element',
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 240.0,
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
              const SizedBox(height: 3.0),

              // Subtitle (Poll type)
              Text(
                _buildPollSubtitle(context),
                style: TextStyle(
                  fontSize: 12.0,
                  color: widget.subtextColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10.0),

              // Options
              if (options.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: Text(
                    context.l10n.translate('poll_total_votes').replaceAll('{count}', '0'),
                    style: TextStyle(fontSize: 13.0, color: widget.subtextColor),
                  ),
                )
              else
                ...options.map((opt) {
                  final int optId = _parseInt(opt['id']) ?? 0;
                  final String optText = opt['text']?.toString() ?? '';
                  final int voteCount = _parseInt(opt['vote_count']) ?? 0;
                  final bool isVotedByMe = myVotedIds.contains(optId);
                  final bool isSelectedDraft = _selectedOptionIds.contains(optId);

                  final double fraction = totalVotes > 0
                      ? (voteCount / totalVotes).clamp(0.0, 1.0)
                      : 0.0;
                  final int percent = (fraction * 100).round();

                  final bool isCorrectQuizOption =
                      _isQuiz && showResults && correctOptId != null && optId == correctOptId;
                  final bool isWrongQuizVote =
                      _isQuiz && showResults && isVotedByMe && correctOptId != null && optId != correctOptId;

                  Color optionBarColor = barAccent;
                  if (isCorrectQuizOption) {
                    optionBarColor = widget.isDark
                        ? const Color(0xFF4ADE80)
                        : const Color(0xFF16A34A);
                  } else if (isWrongQuizVote) {
                    optionBarColor = const Color(0xFFEF4444);
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8.0),
                      onTap: (_isClosed || _isSubmitting)
                          ? null
                          : () {
                              if (showResults) {
                                // Allow retracting vote in non-quiz open polls by tapping a voted option
                                if (!_isQuiz && isVotedByMe) {
                                  _submitVote(const [], retract: true);
                                }
                                return;
                              }
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
                            },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Left indicator: radio/checkbox before voting, percentage after voting
                                if (!showResults)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 1.0, right: 10.0),
                                    child: Container(
                                      width: 20.0,
                                      height: 20.0,
                                      decoration: BoxDecoration(
                                        shape: _isMultiple ? BoxShape.rectangle : BoxShape.circle,
                                        borderRadius: _isMultiple ? BorderRadius.circular(5.0) : null,
                                        color: isSelectedDraft
                                            ? barAccent
                                            : Colors.transparent,
                                        border: Border.all(
                                          color: isSelectedDraft
                                              ? barAccent
                                              : widget.subtextColor.withValues(alpha: 0.65),
                                          width: 1.8,
                                        ),
                                      ),
                                      child: isSelectedDraft
                                          ? Icon(
                                              Icons.check,
                                              size: 14.0,
                                              color: widget.isMe && widget.isDark
                                                  ? Colors.black87
                                                  : Colors.white,
                                            )
                                          : null,
                                    ),
                                  )
                                else
                                  SizedBox(
                                    width: 44.0,
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 1.0, right: 6.0),
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
                                        fontWeight: (isVotedByMe || isCorrectQuizOption)
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: widget.textColor,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ),

                                // Right status icon (voted check / quiz correct / quiz wrong)
                                if (showResults && (isVotedByMe || isCorrectQuizOption))
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6.0, top: 1.0),
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
                                      end: math.max(fraction, voteCount > 0 ? 0.04 : 0.0),
                                    ),
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeOutCubic,
                                    builder: (context, animValue, _) {
                                      return LinearProgressIndicator(
                                        value: animValue,
                                        minHeight: 5.0,
                                        backgroundColor: widget.textColor.withValues(alpha: 0.12),
                                        valueColor: AlwaysStoppedAnimation<Color>(optionBarColor),
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
                    height: 34.0,
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

              // Footer: Total votes count
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: Text(
                  context.l10n
                      .translate('poll_total_votes')
                      .replaceAll('{count}', '$totalVotes'),
                  style: TextStyle(
                    fontSize: 12.0,
                    color: widget.subtextColor,
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