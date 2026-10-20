import 'package:flutter/material.dart';

// TODO(stickers): При реализации системы стикеров подключить StickerMessageWidget
// в MessageBubble (для messageType == 'sticker') без фона бабла, использовать
// MediaCacheManager для кэширования и отображения превью, а также добавить
// поддержку анимированных стикеров (Lottie/TGS и WebM).
class StickerMessageWidget extends StatelessWidget {
  final String imageUrl;
  final bool isSentByMe;

  const StickerMessageWidget({
    super.key,
    required this.imageUrl,
    this.isSentByMe = false,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: 200,
        maxHeight: 200,
      ),
      child: Image.network(
        imageUrl,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(
            child: CircularProgressIndicator(),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return const Center(
            child: Icon(Icons.broken_image, size: 48),
          );
        },
        fit: BoxFit.cover,
      ),
    );
  }
}