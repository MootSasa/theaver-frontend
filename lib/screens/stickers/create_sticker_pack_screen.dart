import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../services/sticker_service.dart';
import '../../theme/theav_theme.dart';
import '../../utils/emoji_utils.dart';
import '../../widgets/chat/sticker_item_widget.dart';
import 'sticker_pack_detail_sheet.dart';

class _DraftStickerItem {
  final String fileName;
  final Uint8List bytes;
  final TextEditingController emojisController;
  final TextEditingController keywordsController;
  String? effectFileName;
  Uint8List? effectBytes;

  _DraftStickerItem({
    required this.fileName,
    required this.bytes,
    String initialEmojis = '😀',
    String initialKeywords = '',
  })  : emojisController = TextEditingController(text: initialEmojis),
        keywordsController = TextEditingController(text: initialKeywords);

  void dispose() {
    emojisController.dispose();
    keywordsController.dispose();
  }
}

class CreateStickerPackScreen extends StatefulWidget {
  final int initialModeIndex; // 0 = Import from Telegram, 1 = Create from scratch
  final String? initialTelegramLink;

  const CreateStickerPackScreen({
    super.key,
    this.initialModeIndex = 0,
    this.initialTelegramLink,
  });

  static Future<StickerPack?> showModal(
    BuildContext context, {
    int initialModeIndex = 0,
    String? initialTelegramLink,
  }) {
    return showModalBottomSheet<StickerPack>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.55,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) => CreateStickerPackScreen(
            initialModeIndex: initialModeIndex,
            initialTelegramLink: initialTelegramLink,
          ),
        ),
      ),
    );
  }

  @override
  State<CreateStickerPackScreen> createState() =>
      _CreateStickerPackScreenState();
}

class _CreateStickerPackScreenState extends State<CreateStickerPackScreen> {
  late int _modeIndex; // 0 = Telegram import, 1 = Create pack
  late final TextEditingController _tgLinkController;
  bool _importingTg = false;
  String? _tgError;

  // Create pack state
  String _packType = 'sticker'; // 'sticker' | 'custom_emoji'
  bool _isAdaptiveColor = false;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _slugController = TextEditingController();
  Timer? _slugDebounce;
  bool? _slugAvailable;
  bool _checkingSlug = false;
  final List<_DraftStickerItem> _draftItems = [];
  bool _publishing = false;
  String? _publishError;

  @override
  void initState() {
    super.initState();
    _modeIndex = widget.initialModeIndex;
    _tgLinkController = TextEditingController(
      text: widget.initialTelegramLink ?? '',
    );
    _slugController.addListener(_onSlugChanged);
  }

  @override
  void dispose() {
    _slugDebounce?.cancel();
    _tgLinkController.dispose();
    _titleController.dispose();
    _slugController.dispose();
    for (final item in _draftItems) {
      item.dispose();
    }
    super.dispose();
  }

  void _onSlugChanged() {
    _slugDebounce?.cancel();
    final raw = _slugController.text.trim();
    if (raw.length < 3) {
      setState(() {
        _slugAvailable = null;
        _checkingSlug = false;
      });
      return;
    }
    setState(() => _checkingSlug = true);
    _slugDebounce = Timer(const Duration(milliseconds: 350), () async {
      final ok = await StickerService.instance.checkSlugAvailable(raw);
      if (mounted && _slugController.text.trim() == raw) {
        setState(() {
          _slugAvailable = ok;
          _checkingSlug = false;
        });
      }
    });
  }

  Future<void> _handleTelegramImport() async {
    final link = _tgLinkController.text.trim();
    if (link.isEmpty || _importingTg) return;
    setState(() {
      _importingTg = true;
      _tgError = null;
    });
    try {
      final pack = await StickerService.instance.importTelegramPack(link);
      if (!mounted) return;
      if (pack == null) {
        setState(() {
          _tgError =
              'Не удалось импортировать набор. Проверьте ссылку или настройки TELEGRAM_BOT_TOKEN на сервере.';
          _importingTg = false;
        });
        return;
      }
      Navigator.of(context).pop(pack);
      StickerPackDetailSheet.show(
        context,
        packIdOrSlug: pack.id,
        initialPack: pack,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _tgError = 'Ошибка импорта: $e';
          _importingTg = false;
        });
      }
    }
  }

  Future<void> _pickStickerFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['webp', 'png', 'tgs', 'json', 'webm', 'gif'],
    );
    if (result == null || result.files.isEmpty) return;

    setState(() {
      for (final f in result.files) {
        if (f.bytes != null && f.bytes!.isNotEmpty) {
          final baseName = f.name.replaceAll(RegExp(r'\.[^.]+$'), '');
          _draftItems.add(
            _DraftStickerItem(
              fileName: f.name,
              bytes: f.bytes!,
              initialEmojis: '😀',
              initialKeywords: baseName.replaceAll('_', ' '),
            ),
          );
        }
      }
    });
  }

  Future<void> _pickEffectFile(_DraftStickerItem item) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['tgs', 'json'],
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null || f.bytes!.isEmpty) return;
    setState(() {
      item.effectFileName = f.name;
      item.effectBytes = f.bytes;
    });
  }

  Future<void> _publishPack() async {
    final title = _titleController.text.trim();
    final slug = _slugController.text.trim();
    if (title.isEmpty) {
      setState(() => _publishError = 'Введите название набора');
      return;
    }
    if (slug.length < 3 || _slugAvailable == false) {
      setState(() => _publishError = 'Укажите свободный короткий адрес (минимум 3 символа)');
      return;
    }
    if (_draftItems.isEmpty) {
      setState(() => _publishError = 'Добавьте хотя бы один файл стикера или эмодзи');
      return;
    }

    setState(() {
      _publishing = true;
      _publishError = null;
    });

    try {
      final pack = await StickerService.instance.createPack(
        title: title,
        shortName: slug,
        packType: _packType,
      );
      if (pack == null) {
        if (mounted) {
          setState(() {
            _publishError = 'Не удалось создать набор. Возможно, короткий адрес уже занят.';
            _publishing = false;
          });
        }
        return;
      }

      for (final draft in _draftItems) {
        final rawEmojis = draft.emojisController.text.trim();
        final emojis = EmojiUtils.emojiRegex
            .allMatches(rawEmojis)
            .map((m) => m.group(0)!)
            .toList();
        if (emojis.isEmpty && rawEmojis.isNotEmpty) {
          emojis.add(rawEmojis);
        }
        final keywords = draft.keywordsController.text
            .split(RegExp(r'[,;\s]+'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

        await StickerService.instance.uploadStickerToPack(
          packId: pack.id,
          bytes: draft.bytes,
          fileName: draft.fileName,
          emojis: emojis.isEmpty ? const ['😀'] : emojis,
          keywords: keywords,
          isAdaptiveTextColor: _packType == 'custom_emoji' && _isAdaptiveColor,
          effectBytes: draft.effectBytes,
          effectFileName: draft.effectFileName,
        );
      }

      await StickerService.instance.loadInstalledPacks(forceRefresh: true);
      final updatedPack = await StickerService.instance.getPackByIdOrSlug(pack.id);
      if (!mounted) return;
      Navigator.of(context).pop(updatedPack ?? pack);
    } catch (e) {
      if (mounted) {
        setState(() {
          _publishError = 'Ошибка публикации: $e';
          _publishing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TheavTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: theme.secondaryBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: theme.dividerColor,
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: theme.dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Студия стикеров и эмодзи',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: theme.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: iconoir.Xmark(
                    width: 20,
                    height: 20,
                    color: theme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 38,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: theme.inputBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  _buildSegmentTab(
                    theme: theme,
                    index: 0,
                    label: 'Импорт из Telegram',
                  ),
                  _buildSegmentTab(
                    theme: theme,
                    index: 1,
                    label: 'Создать набор',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 0.5, thickness: 0.5, color: theme.dividerColor),
          Expanded(
            child: _modeIndex == 0
                ? _buildTelegramImportView(theme)
                : _buildCreateFromScratchView(theme, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentTab({
    required TheavThemeData theme,
    required int index,
    required String label,
  }) {
    final selected = _modeIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _modeIndex = index),
        behavior: HitTestBehavior.opaque,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? theme.secondaryBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: selected
                ? Border.all(color: theme.dividerColor, width: 0.5)
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? theme.textPrimary : theme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTelegramImportView(TheavThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Ссылка или короткое имя набора Telegram',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: theme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _tgLinkController,
          style: TextStyle(fontSize: 14, color: theme.textPrimary),
          decoration: InputDecoration(
            hintText: 'https://t.me/addstickers/Animals или https://t.me/addemoji/...',
            hintStyle: TextStyle(fontSize: 13, color: theme.textSecondary),
            filled: true,
            fillColor: theme.inputBg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.dividerColor, width: 0.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.dividerColor, width: 0.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.accent, width: 1),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.inputBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Поддерживаемые форматы при импорте',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              _buildFeatureNote(
                theme,
                'Статичные (.webp) и векторные (.tgs) стикеры и эмодзи с прозрачным фоном',
              ),
              const SizedBox(height: 6),
              _buildFeatureNote(
                theme,
                'Видео-стикеры (.webm VP9 с альфа-каналом) автоматически конвертируются в Animated WebP',
              ),
              const SizedBox(height: 6),
              _buildFeatureNote(
                theme,
                'Полноэкранные эффекты Telegram Premium (premium_animation .tgs) сохраняются и проигрываются при нажатии и отправке',
              ),
              const SizedBox(height: 6),
              _buildFeatureNote(
                theme,
                'Локальная двуязычная индексация (RU/EN) по эмодзи, слоям Lottie и семантике',
              ),
            ],
          ),
        ),
        if (_tgError != null) ...[
          const SizedBox(height: 12),
          Text(
            _tgError!,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFFF453A),
            ),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          height: 50,
          child: GestureDetector(
            onTap: _importingTg ? null : _handleTelegramImport,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.accent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: _importingTg
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'ИМПОРТИРОВАТЬ И УСТАНОВИТЬ',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureNote(TheavThemeData theme, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: iconoir.Check(
            width: 14,
            height: 14,
            color: theme.accent,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              color: theme.textSecondary,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateFromScratchView(TheavThemeData theme, bool isDark) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  _buildTypeChoice(
                    theme: theme,
                    value: 'sticker',
                    label: 'Стикеры (512×512)',
                  ),
                  const SizedBox(width: 8),
                  _buildTypeChoice(
                    theme: theme,
                    value: 'custom_emoji',
                    label: 'Эмодзи (128×128)',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _titleController,
                style: TextStyle(fontSize: 14, color: theme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Название набора',
                  labelStyle: TextStyle(fontSize: 13, color: theme.textSecondary),
                  filled: true,
                  fillColor: theme.inputBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: theme.dividerColor, width: 0.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: theme.dividerColor, width: 0.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _slugController,
                style: TextStyle(fontSize: 14, color: theme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Короткий адрес (theaver.app/addstickers/...)',
                  labelStyle: TextStyle(fontSize: 13, color: theme.textSecondary),
                  filled: true,
                  fillColor: theme.inputBg,
                  suffixIcon: _checkingSlug
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _slugAvailable == null
                          ? null
                          : Padding(
                              padding: const EdgeInsets.all(12),
                              child: _slugAvailable!
                                  ? const iconoir.Check(
                                      width: 18,
                                      height: 18,
                                      color: Color(0xFF30D158),
                                    )
                                  : const iconoir.Xmark(
                                      width: 18,
                                      height: 18,
                                      color: Color(0xFFFF453A),
                                    ),
                            ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: theme.dividerColor, width: 0.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: theme.dividerColor, width: 0.5),
                  ),
                ),
              ),
              if (_packType == 'custom_emoji') ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => setState(() => _isAdaptiveColor = !_isAdaptiveColor),
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Checkbox(
                        value: _isAdaptiveColor,
                        activeColor: theme.accent,
                        onChanged: (v) =>
                            setState(() => _isAdaptiveColor = v ?? false),
                      ),
                      Expanded(
                        child: Text(
                          'Адаптивный цвет под тему текста (монохромные иконки)',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ЭЛЕМЕНТЫ НАБОРА (${_draftItems.length})',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      color: theme.textSecondary,
                    ),
                  ),
                  GestureDetector(
                    onTap: _pickStickerFiles,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.inputBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.dividerColor,
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          iconoir.Plus(
                            width: 16,
                            height: 16,
                            color: theme.accent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Добавить файлы',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: theme.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_draftItems.isEmpty)
                GestureDetector(
                  onTap: _pickStickerFiles,
                  child: Container(
                    height: 110,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.inputBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.dividerColor,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        iconoir.MediaImagePlus(
                          width: 24,
                          height: 24,
                          color: theme.textSecondary,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Нажмите, чтобы выбрать .webp, .png, .tgs или .webm с прозрачным фоном',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: theme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ..._draftItems.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  final isRaster = item.fileName.toLowerCase().endsWith('.png') ||
                      item.fileName.toLowerCase().endsWith('.webp') ||
                      item.fileName.toLowerCase().endsWith('.gif');
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.inputBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.dividerColor,
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 56,
                            height: 56,
                            child: CustomPaint(
                              painter: CheckerboardPainter(isDark: isDark),
                              child: Center(
                                child: isRaster
                                    ? Image.memory(
                                        item.bytes,
                                        width: 48,
                                        height: 48,
                                        fit: BoxFit.contain,
                                      )
                                    : Text(
                                        item.fileName.split('.').last.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: theme.textPrimary,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            children: [
                              TextField(
                                controller: item.emojisController,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.textPrimary,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  labelText: 'Привязанные эмодзи',
                                  labelStyle: TextStyle(
                                    fontSize: 11.5,
                                    color: theme.textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: item.keywordsController,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.textPrimary,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  labelText: 'Теги для поиска (RU/EN)',
                                  labelStyle: TextStyle(
                                    fontSize: 11.5,
                                    color: theme.textSecondary,
                                  ),
                                ),
                              ),
                              if (_packType == 'sticker') ...[
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: GestureDetector(
                                    onTap: () => _pickEffectFile(item),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        iconoir.Sparks(
                                          width: 14,
                                          height: 14,
                                          color: item.effectBytes != null
                                              ? theme.accent
                                              : theme.textSecondary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          item.effectFileName != null
                                              ? 'Эффект: ${item.effectFileName}'
                                              : 'Прикрепить эффект .tgs',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: item.effectBytes != null
                                                ? theme.accent
                                                : theme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              final removed = _draftItems.removeAt(idx);
                              removed.dispose();
                            });
                          },
                          icon: iconoir.Trash(
                            width: 18,
                            height: 18,
                            color: theme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              if (_publishError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _publishError!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFFF453A),
                  ),
                ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: GestureDetector(
                onTap: _publishing ? null : _publishPack,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.accent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: _publishing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'ОПУБЛИКОВАТЬ НАБОР',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeChoice({
    required TheavThemeData theme,
    required String value,
    required String label,
  }) {
    final selected = _packType == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _packType = value),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? theme.accent.withValues(alpha: 0.14)
                : theme.inputBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? theme.accent : theme.dividerColor,
              width: selected ? 1 : 0.5,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? theme.accent : theme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
