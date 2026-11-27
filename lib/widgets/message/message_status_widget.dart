import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

/// Виджет отображения статуса доставки/прочтения сообщения.
/// ✓ — доставлено на сервер (iconoir.Check)
/// ✓✓ — прочитано получателем (iconoir.DoubleCheck)
/// Серые — не прочитано, цветные (акцентные) — прочитано
class MessageStatusWidget extends StatelessWidget {
  final bool isRead;
  final bool isOutgoing;
  final int sendStatus;
  final Color? accentColor;
  final Color? colorOverride;

  const MessageStatusWidget({
    Key? key,
    required this.isRead,
    required this.isOutgoing,
    this.sendStatus = 1,
    this.accentColor,
    this.colorOverride,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isOutgoing) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final color = colorOverride ?? (isRead
        ? (accentColor ?? theme.colorScheme.primary)
        : Colors.grey);

    if (sendStatus == 0) {
      return iconoir.Clock(
        width: 13,
        height: 13,
        color: colorOverride ?? Colors.grey,
      );
    }
    if (sendStatus == 2) {
      return const iconoir.WarningCircle(
        width: 14,
        height: 14,
        color: Colors.redAccent,
      );
    }

    if (isRead) {
      // ✓✓ — прочитано (две галочки из пака iconoir)
      return iconoir.DoubleCheck(
        width: 15,
        height: 15,
        color: color,
      );
    } else {
      // ✓ — доставлено (одна галочка из пака iconoir)
      return iconoir.Check(
        width: 15,
        height: 15,
        color: color,
      );
    }
  }
}

