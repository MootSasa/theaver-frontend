import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../services/chat_service.dart';
import '../../services/contacts_service.dart';
import '../../utils/haptic_utils.dart';
import '../design_system/theav_design_system.dart';

/// Current options attached to pending forwarded messages staged above chat input.
class StagedForwardPayload {
  final String fromChatId;
  final List<Message> messages;
  final bool hideSender;
  final bool hideCaption;

  const StagedForwardPayload({
    required this.fromChatId,
    required this.messages,
    this.hideSender = false,
    this.hideCaption = false,
  });

  bool get hasAnyCaption =>
      messages.any((m) => m.content.trim().isNotEmpty && m.fileUrl != null);

  StagedForwardPayload copyWith({
    String? fromChatId,
    List<Message>? messages,
    bool? hideSender,
    bool? hideCaption,
  }) {
    return StagedForwardPayload(
      fromChatId: fromChatId ?? this.fromChatId,
      messages: messages ?? this.messages,
      hideSender: hideSender ?? this.hideSender,
      hideCaption: hideCaption ?? this.hideCaption,
    );
  }
}

/// Telegram-style preview bar mounted above the input bar when messages are
/// staged for forwarding (tapping opens [showForwardOptionsSheet]).
class ForwardPreviewBar extends StatelessWidget {
  final StagedForwardPayload payload;
  final VoidCallback onTapOptions;
  final VoidCallback onCancel;

  const ForwardPreviewBar({
    super.key,
    required this.payload,
    required this.onTapOptions,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final int count = payload.messages.length;
    final String titleText = count == 1
        ? 'Переслать 1 сообщение'
        : 'Переслать сообщений: $count';

    Widget buildBar(String senderSummary) {
      final String subtitleText = payload.hideCaption && payload.hasAnyCaption
          ? '$senderSummary • Подпись скрыта'
          : senderSummary;

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticUtils.tap();
          onTapOptions();
        },
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.divider, width: 0.5),
          ),
          child: Row(
            children: [
              iconoir.ForwardMessage(
                width: 20,
                height: 20,
                color: palette.primary,
              ),
              const SizedBox(width: 10),
              Container(
                width: 2.5,
                height: 30,
                decoration: BoxDecoration(
                  color: palette.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.subtext,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Отменить пересылку',
                icon: iconoir.Xmark(
                  width: 18,
                  height: 18,
                  color: palette.subtext,
                ),
                onPressed: () {
                  HapticUtils.tap();
                  onCancel();
                },
              ),
            ],
          ),
        ),
      );
    }

    if (payload.hideSender) {
      return buildBar('Имя отправителя скрыто');
    }

    return ValueListenableBuilder<int>(
      valueListenable: ContactsService.revisionNotifier,
      builder: (_, __, ___) {
        final senders = payload.messages
            .map((m) {
              final raw = m.resolveEffectiveAuthorTitle().trim();
              if (raw.isEmpty) return '';
              if (m.isChannelOrPersonaAuthored || m.isMirroredChannelPost) {
                return raw;
              }
              return ContactsService.resolvePeerName(
                m.senderId,
                raw,
                senderChatId: m.senderChatId,
                isAnonymousAdmin: m.isFromAnonymousAdmin,
                isMirroredChannelPost: m.isMirroredChannelPost,
              ).trim();
            })
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList();
        final String senderSummary = senders.isEmpty
            ? 'Пересылка сообщений'
            : (senders.length == 1
                ? senders.first
                : '${senders.first} и ещё ${senders.length - 1}');
        return buildBar(senderSummary);
      },
    );
  }
}

/// Action result returned from [showForwardOptionsSheet].
class ForwardOptionsResult {
  final bool hideSender;
  final bool hideCaption;
  final bool changeRecipient;
  final bool cancelForward;

  const ForwardOptionsResult({
    this.hideSender = false,
    this.hideCaption = false,
    this.changeRecipient = false,
    this.cancelForward = false,
  });
}

/// Opens Telegram-style forward customization sheet (`Скрыть имя отправителя`,
/// `Скрыть подпись`, change recipient, cancel).
Future<ForwardOptionsResult?> showForwardOptionsSheet({
  required BuildContext context,
  required StagedForwardPayload payload,
}) {
  return showTheavModalSheet<ForwardOptionsResult>(
    context: context,
    title: 'Настройки пересылки',
    showCloseButton: true,
    builder: (ctx) => _ForwardOptionsSheetBody(payload: payload),
  );
}

class _ForwardOptionsSheetBody extends StatefulWidget {
  final StagedForwardPayload payload;

  const _ForwardOptionsSheetBody({required this.payload});

  @override
  State<_ForwardOptionsSheetBody> createState() =>
      _ForwardOptionsSheetBodyState();
}

class _ForwardOptionsSheetBodyState extends State<_ForwardOptionsSheetBody> {
  late bool _hideSender;
  late bool _hideCaption;

  @override
  void initState() {
    super.initState();
    _hideSender = widget.payload.hideSender;
    _hideCaption = widget.payload.hideCaption;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TheavInsetGroup(
            margin: const EdgeInsets.only(bottom: 12),
            children: [
              TheavListRow(
                leading: iconoir.EyeClosed(
                  width: 20,
                  height: 20,
                  color: palette.primary,
                ),
                title: 'Скрыть имя отправителя',
                trailing: TheavSwitch(
                  value: _hideSender,
                  onChanged: (v) => setState(() => _hideSender = v),
                ),
                onTap: () => setState(() => _hideSender = !_hideSender),
              ),
              if (widget.payload.hasAnyCaption)
                TheavListRow(
                  leading: iconoir.TextBox(
                    width: 20,
                    height: 20,
                    color: palette.primary,
                  ),
                  title: 'Скрыть подпись',
                  trailing: TheavSwitch(
                    value: _hideCaption,
                    onChanged: (v) => setState(() => _hideCaption = v),
                  ),
                  onTap: () => setState(() => _hideCaption = !_hideCaption),
                ),
            ],
          ),
          TheavInsetGroup(
            margin: const EdgeInsets.only(bottom: 14),
            children: [
              TheavListRow(
                leading: iconoir.Community(
                  width: 20,
                  height: 20,
                  color: palette.primary,
                ),
                title: 'Изменить получателя',
                showChevron: true,
                onTap: () => Navigator.of(context).pop(
                  ForwardOptionsResult(
                    hideSender: _hideSender,
                    hideCaption: _hideCaption,
                    changeRecipient: true,
                  ),
                ),
              ),
              TheavListRow(
                leading: iconoir.Trash(
                  width: 20,
                  height: 20,
                  color: palette.error,
                ),
                title: 'Отменить пересылку',
                isDestructive: true,
                onTap: () => Navigator.of(context).pop(
                  const ForwardOptionsResult(cancelForward: true),
                ),
              ),
            ],
          ),
          TheavFloatingPillButton(
            label: 'Готово',
            isPrimary: true,
            onTap: () => Navigator.of(context).pop(
              ForwardOptionsResult(
                hideSender: _hideSender,
                hideCaption: _hideCaption,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
