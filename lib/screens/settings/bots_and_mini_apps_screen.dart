import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../services/bot_service.dart';
import '../../services/chat_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/tiling_layout_controller.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../../widgets/bot/mini_app_webview_sheet.dart';
import '../../widgets/bot/thv_invoice_sheet.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/settings/settings_floating_header.dart';
import '../chat/private_chat_screen.dart';

/// Hub screen for discovering and managing Bots, Inline Mode (`@bot`), and Mini Apps.
///
/// Accessible directly from Settings (`Боты и Mini Apps`) and settings search.
class BotsAndMiniAppsScreen extends StatefulWidget {
  const BotsAndMiniAppsScreen({super.key});

  @override
  State<BotsAndMiniAppsScreen> createState() => _BotsAndMiniAppsScreenState();
}

class _BotsAndMiniAppsScreenState extends State<BotsAndMiniAppsScreen> {
  bool _isLoading = true;
  bool _isOpeningChat = false;
  List<BotInfo> _directory = const [];
  List<BotInfo> _myBots = const [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool forceRefresh = true}) async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        BotService.getBotsDirectory(forceRefresh: forceRefresh),
        BotService.getMyBots(),
      ]);
      if (!mounted) return;
      setState(() {
        _directory = results[0];
        _myBots = results[1];
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  BotInfo? get _botMother {
    for (final b in _directory) {
      if ((b.username ?? '').toLowerCase() == 'botmother') {
        return b;
      }
    }
    return null;
  }

  BotInfo? get _waltBot {
    for (final b in _directory) {
      if ((b.username ?? '').toLowerCase() == 'walt') {
        return b;
      }
    }
    return null;
  }

  List<BotInfo> get _featuredAppsAndInlineBots {
    return _directory.where((b) {
      final uname = (b.username ?? '').toLowerCase();
      final isSystem = uname == 'botmother' || uname == 'walt';
      return !isSystem && (b.hasAnyWebApp || b.supportsInlineQueries);
    }).toList();
  }

  Future<void> _openBotChat(BotInfo bot) async {
    if (_isOpeningChat || bot.userId.isEmpty) return;
    HapticUtils.tap();
    setState(() => _isOpeningChat = true);
    try {
      final res = await ChatService.createChat(
        chatType: 'private',
        participantIds: [bot.userId],
      );
      if (!mounted) return;
      if (res['success'] == true && res['chat'] is Chat) {
        final chat = res['chat'] as Chat;
        final title = bot.displayName.isNotEmpty
            ? bot.displayName
            : '@${bot.username ?? 'bot'}';
        if (TilingLayoutController.instance.isWorkspaceMounted) {
          TilingLayoutController.instance.openChatInActiveTile(
            chatId: chat.id,
            chatType: 'private',
            chatName: title,
            avatarUrl: bot.avatarUrl,
            otherUserId: bot.userId,
          );
          return;
        }
        await Navigator.of(context).push(
          SwipeBackPageRoute(
            builder: (_) => PrivateChatScreen(
              chatId: chat.id,
              otherUserId: bot.userId,
              otherUserName: title,
              otherUserAvatar: bot.avatarUrl,
              otherUserOnline: false,
            ),
          ),
        );
      } else {
        GlassToastService().showError(
          context,
          res['message']?.toString() ?? 'Не удалось открыть чат с ботом',
        );
      }
    } finally {
      if (mounted) setState(() => _isOpeningChat = false);
    }
  }

  Future<void> _launchBotMiniApp(
    BotInfo bot, {
    String? url,
    String? shortName,
    String mode = 'menu',
  }) async {
    if (bot.userId.isEmpty) return;
    HapticUtils.tap();
    await openMiniAppSheet(
      context,
      botId: bot.userId,
      botName: bot.displayName,
      botUsername: bot.username,
      isVerified: bot.isVerified,
      url: url ?? bot.effectiveWebAppUrl,
      appShortName: shortName,
      mode: mode,
      buttonText: bot.menuButton.text,
    );
  }

  Future<void> _showCreateBotSheet() async {
    final nameCtrl = TextEditingController();
    final unameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    bool submitting = false;

    await showTheavModalSheet<void>(
      context: context,
      title: 'Новый бот',
      showCloseButton: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final palette = sheetCtx.theav;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Отображаемое имя',
                  hintText: 'Например: Погодный Помощник',
                  filled: true,
                  fillColor: palette.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: unameCtrl,
                decoration: InputDecoration(
                  labelText: 'Username (оканчивается на bot)',
                  hintText: 'weather_helper_bot',
                  prefixText: '@',
                  filled: true,
                  fillColor: palette.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Описание (необязательно)',
                  filled: true,
                  fillColor: palette.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TheavFloatingPillButton(
                label: submitting ? 'Создание...' : 'Создать бота',
                isPrimary: true,
                enabled: !submitting,
                onTap: () async {
                  final name = nameCtrl.text.trim();
                  final uname = unameCtrl.text.trim();
                  if (name.isEmpty || uname.isEmpty) {
                    GlassToastService().show(
                      sheetCtx,
                      'Укажите имя и @username бота',
                    );
                    return;
                  }
                  setSheetState(() => submitting = true);
                  final res = await BotService.createBot(
                    displayName: name,
                    username: uname,
                    description: descCtrl.text,
                    aboutText: descCtrl.text,
                  );
                  if (!sheetCtx.mounted) return;
                  if (res['success'] == true) {
                    Navigator.pop(sheetCtx);
                    if (mounted) {
                      GlassToastService().show(
                        context,
                        'Бот @${uname.replaceFirst(RegExp(r'^@+'), '')} создан',
                        icon: Icons.check,
                      );
                    }
                    await _loadData(forceRefresh: true);
                  } else {
                    setSheetState(() => submitting = false);
                    GlassToastService().showError(
                      sheetCtx,
                      res['message']?.toString() ?? 'Ошибка создания бота',
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );

    nameCtrl.dispose();
    unameCtrl.dispose();
    descCtrl.dispose();
  }

  Future<void> _showManageBotSheet(BotInfo bot) async {
    bool supportsInline = bot.supportsInlineQueries;
    final placeholderCtrl =
        TextEditingController(text: bot.inlinePlaceholder ?? '');
    final mainAppUrlCtrl = TextEditingController(text: bot.mainAppUrl);
    final menuBtnTextCtrl = TextEditingController(
      text: bot.menuButton.text.isNotEmpty ? bot.menuButton.text : 'Открыть',
    );
    final menuBtnUrlCtrl = TextEditingController(
      text: bot.menuButton.webAppUrl ?? bot.mainAppUrl,
    );
    final newAppShortCtrl = TextEditingController();
    final newAppTitleCtrl = TextEditingController();
    final newAppUrlCtrl = TextEditingController();
    List<BotWebAppInfo> apps = List<BotWebAppInfo>.from(bot.webApps);
    bool saving = false;

    await showTheavModalSheet<void>(
      context: context,
      title: '@${bot.username ?? bot.displayName}',
      showCloseButton: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final palette = sheetCtx.theav;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (bot.token != null && bot.token!.isNotEmpty)
                  TheavInsetGroup(
                    margin: const EdgeInsets.only(bottom: 12),
                    header: 'API-токен и чат',
                    children: [
                      TheavListRow(
                        leading: iconoir.Key(
                          width: 20,
                          height: 20,
                          color: palette.primary,
                        ),
                        title: 'Скопировать Bot Token',
                        subtitle: bot.token,
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: bot.token!));
                          GlassToastService().show(
                            sheetCtx,
                            'Токен скопирован',
                            icon: Icons.check,
                          );
                        },
                      ),
                      TheavListRow(
                        leading: iconoir.ChatBubble(
                          width: 20,
                          height: 20,
                          color: palette.primary,
                        ),
                        title: 'Открыть чат с ботом',
                        showChevron: true,
                        onTap: () {
                          Navigator.pop(sheetCtx);
                          _openBotChat(bot);
                        },
                      ),
                    ],
                  ),
                TheavInsetGroup(
                  margin: const EdgeInsets.only(bottom: 12),
                  header: 'Inline и Mini App',
                  children: [
                    TheavListRow(
                      leading: iconoir.Spark(
                        width: 20,
                        height: 20,
                        color: palette.primary,
                      ),
                      title: 'Inline-режим (@${bot.username ?? 'bot'} ...)',
                      trailing: TheavSwitch(
                        value: supportsInline,
                        onChanged: (v) =>
                            setSheetState(() => supportsInline = v),
                      ),
                    ),
                  ],
                ),
                TextField(
                  controller: placeholderCtrl,
                  decoration: InputDecoration(
                    labelText: 'Inline-подсказка (placeholder)',
                    filled: true,
                    fillColor: palette.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: mainAppUrlCtrl,
                  decoration: InputDecoration(
                    labelText: 'URL главного Mini App (https://...)',
                    hintText: 'https://api.theaver.app/api/miniapps/studio',
                    filled: true,
                    fillColor: palette.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: menuBtnTextCtrl,
                        decoration: InputDecoration(
                          labelText: 'Кнопка меню',
                          filled: true,
                          fillColor: palette.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: menuBtnUrlCtrl,
                        decoration: InputDecoration(
                          labelText: 'URL кнопки меню',
                          hintText: 'https://...',
                          filled: true,
                          fillColor: palette.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TheavFloatingPillButton(
                        label: saving ? 'Сохранение...' : 'Сохранить',
                        isPrimary: true,
                        enabled: !saving,
                        onTap: () async {
                          setSheetState(() => saving = true);
                          final mbUrl = menuBtnUrlCtrl.text.trim();
                          final mbPayload = mbUrl.isNotEmpty
                              ? {
                                  'type': 'web_app',
                                  'text': menuBtnTextCtrl.text.trim().isNotEmpty
                                      ? menuBtnTextCtrl.text.trim()
                                      : 'Открыть',
                                  'web_app': {'url': mbUrl},
                                }
                              : {'type': 'default'};
                          final res = await BotService.updateBot(bot.userId, {
                            'supports_inline_queries': supportsInline,
                            'inline_placeholder': placeholderCtrl.text.trim(),
                            'main_app_url': mainAppUrlCtrl.text.trim(),
                            'has_main_web_app':
                                mainAppUrlCtrl.text.trim().isNotEmpty,
                            'menu_button': mbPayload,
                          });
                          if (!sheetCtx.mounted) return;
                          setSheetState(() => saving = false);
                          if (res['success'] == true) {
                            GlassToastService().show(
                              sheetCtx,
                              'Настройки сохранены',
                              icon: Icons.check,
                            );
                            await _loadData(forceRefresh: true);
                          } else {
                            GlassToastService().showError(
                              sheetCtx,
                              res['message']?.toString() ??
                                  'Ошибка сохранения',
                            );
                          }
                        },
                      ),
                    ),
                    if (mainAppUrlCtrl.text.trim().isNotEmpty ||
                        menuBtnUrlCtrl.text.trim().isNotEmpty) ...[
                      const SizedBox(width: 8),
                      TheavFloatingPillButton(
                        label: 'Запустить',
                        icon: const iconoir.AppWindow(width: 17, height: 17),
                        onTap: () {
                          final url = menuBtnUrlCtrl.text.trim().isNotEmpty
                              ? menuBtnUrlCtrl.text.trim()
                              : mainAppUrlCtrl.text.trim();
                          Navigator.pop(sheetCtx);
                          _launchBotMiniApp(bot, url: url, mode: 'main');
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                if (apps.isNotEmpty)
                  TheavInsetGroup(
                    margin: const EdgeInsets.only(bottom: 12),
                    header: 'Именованные Mini Apps',
                    children: [
                      for (final app in apps)
                        TheavListRow(
                          leading: iconoir.AppWindow(
                            width: 20,
                            height: 20,
                            color: palette.primary,
                          ),
                          title: app.title.isNotEmpty
                              ? app.title
                              : app.shortName,
                          subtitle: app.url,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Открыть',
                                icon: iconoir.OpenNewWindow(
                                  width: 18,
                                  height: 18,
                                  color: palette.primary,
                                ),
                                onPressed: () {
                                  Navigator.pop(sheetCtx);
                                  _launchBotMiniApp(
                                    bot,
                                    url: app.url,
                                    shortName: app.shortName,
                                    mode: 'app',
                                  );
                                },
                              ),
                              IconButton(
                                tooltip: 'Удалить',
                                icon: iconoir.Trash(
                                  width: 18,
                                  height: 18,
                                  color: palette.error,
                                ),
                                onPressed: () async {
                                  final r = await BotService.deleteBotWebApp(
                                    botId: bot.userId,
                                    shortName: app.shortName,
                                  );
                                  if (sheetCtx.mounted && r['success'] == true) {
                                    setSheetState(() {
                                      apps.removeWhere(
                                        (a) => a.shortName == app.shortName,
                                      );
                                    });
                                    await _loadData(forceRefresh: true);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                Text(
                  'Добавить Mini App (short_name)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: newAppShortCtrl,
                        decoration: InputDecoration(
                          labelText: 'short_name',
                          hintText: 'shop',
                          filled: true,
                          fillColor: palette.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: newAppTitleCtrl,
                        decoration: InputDecoration(
                          labelText: 'Название',
                          hintText: 'Магазин',
                          filled: true,
                          fillColor: palette.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: newAppUrlCtrl,
                  decoration: InputDecoration(
                    labelText: 'URL Mini App',
                    hintText: 'https://api.theaver.app/api/miniapps/studio',
                    filled: true,
                    fillColor: palette.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TheavFloatingPillButton(
                  label: 'Добавить Mini App',
                  icon: const iconoir.Plus(width: 18, height: 18),
                  onTap: () async {
                    final sn = newAppShortCtrl.text.trim();
                    final url = newAppUrlCtrl.text.trim();
                    final title = newAppTitleCtrl.text.trim().isNotEmpty
                        ? newAppTitleCtrl.text.trim()
                        : sn;
                    if (sn.length < 3 || url.isEmpty) {
                      GlassToastService().show(
                        sheetCtx,
                        'Укажите short_name (от 3 символов) и URL',
                      );
                      return;
                    }
                    final res = await BotService.upsertBotWebApp(
                      botId: bot.userId,
                      shortName: sn,
                      title: title,
                      url: url,
                    );
                    if (!sheetCtx.mounted) return;
                    if (res['success'] == true) {
                      newAppShortCtrl.clear();
                      newAppTitleCtrl.clear();
                      newAppUrlCtrl.clear();
                      setSheetState(() {
                        apps.add(BotWebAppInfo(
                          shortName: sn,
                          title: title,
                          url: url,
                        ));
                      });
                      GlassToastService().show(
                        sheetCtx,
                        'Mini App добавлено',
                        icon: Icons.check,
                      );
                      await _loadData(forceRefresh: true);
                    } else {
                      GlassToastService().showError(
                        sheetCtx,
                        res['message']?.toString() ?? 'Не удалось добавить',
                      );
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );

    placeholderCtrl.dispose();
    mainAppUrlCtrl.dispose();
    menuBtnTextCtrl.dispose();
    menuBtnUrlCtrl.dispose();
    newAppShortCtrl.dispose();
    newAppTitleCtrl.dispose();
    newAppUrlCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final mother = _botMother;
    final walt = _waltBot;
    final directoryBots = _featuredAppsAndInlineBots;

    return SettingsFloatingScaffold(
      title: 'Боты и Mini Apps',
      padBodyTop: true,
      actions: [
        SettingsHeaderAction(
          tooltip: 'Создать бота',
          icon: iconoir.Plus(
            width: 22,
            height: 22,
            color: SettingsFloatingHeader.foregroundColorOf(context),
          ),
          onTap: _showCreateBotSheet,
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadData(forceRefresh: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                padding: EdgeInsets.only(
                  top: SettingsFloatingHeader.topClearanceOf(context) + 6,
                  bottom: 36,
                ),
                children: [
                  TheavInsetGroup(
                    header: 'Системная студия',
                    footer:
                        'Введите @BotMother в начале сообщения в любом чате, чтобы протестировать Inline-режим и запуск Mini Apps.',
                    children: [
                      TheavListRow(
                        leading: iconoir.ChatBubble(
                          width: 22,
                          height: 22,
                          color: palette.primary,
                        ),
                        title: '@BotMother',
                        subtitle:
                            'Создание ботов, настройка команд, Webhook и Mini Apps',
                        showChevron: true,
                        onTap: mother != null
                            ? () => _openBotChat(mother)
                            : null,
                      ),
                      if (mother != null && mother.hasAnyWebApp)
                        TheavListRow(
                          leading: iconoir.AppWindow(
                            width: 22,
                            height: 22,
                            color: palette.primary,
                          ),
                          title: 'Bot Studio (Mini App)',
                          subtitle:
                              'Открыть интерактивное Mini App (@BotMother/studio)',
                          trailing: TheavFloatingPillButton(
                            label: 'Открыть',
                            height: 32,
                            isPrimary: true,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            onTap: () => _launchBotMiniApp(
                              mother,
                              shortName: 'studio',
                              mode: 'menu',
                            ),
                          ),
                          onTap: () => _launchBotMiniApp(
                            mother,
                            shortName: 'studio',
                            mode: 'menu',
                          ),
                        ),
                    ],
                  ),
                  if (walt != null)
                    TheavInsetGroup(
                      header: 'Кошелёк и Theav (THV)',
                      footer:
                          'Официальный мультивалютный кошелёк @walt: внутренняя валюта Theav (THV), криптоактивы USDT/TON/BTC/ETH, переводы и чеки.',
                      children: [
                        TheavListRow(
                          leading: Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 22,
                            color: palette.primary,
                          ),
                          title: '@walt',
                          subtitle: 'Чат с ботом кошелька, чеки и уведомления',
                          showChevron: true,
                          onTap: () => _openBotChat(walt),
                        ),
                        TheavListRow(
                          leading: ThvCrystalIcon(
                            size: 22,
                            color: palette.primary,
                          ),
                          title: 'Walt Кошелёк (Mini App)',
                          subtitle: 'Балансы THV и криптоактивов, переводы и обмен',
                          trailing: TheavFloatingPillButton(
                            label: 'Открыть',
                            height: 32,
                            isPrimary: true,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            onTap: () => _launchBotMiniApp(
                              walt,
                              shortName: 'wallet',
                              mode: 'menu',
                            ),
                          ),
                          onTap: () => _launchBotMiniApp(
                            walt,
                            shortName: 'wallet',
                            mode: 'menu',
                          ),
                        ),
                      ],
                    ),
                  if (directoryBots.isNotEmpty)
                    TheavInsetGroup(
                      header: 'Mini Apps и Inline-боты',
                      children: [
                        for (final bot in directoryBots)
                          TheavListRow(
                            leading: _botAvatar(bot, palette),
                            title: bot.displayName.isNotEmpty
                                ? bot.displayName
                                : '@${bot.username ?? 'bot'}',
                            subtitle: _buildBotSubtitle(bot),
                            trailing: bot.hasAnyWebApp
                                ? TheavFloatingPillButton(
                                    label: 'Открыть',
                                    height: 32,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    onTap: () => _launchBotMiniApp(bot),
                                  )
                                : null,
                            showChevron: !bot.hasAnyWebApp,
                            onTap: () => _openBotChat(bot),
                          ),
                      ],
                    ),
                  TheavInsetGroup(
                    header: 'Мои боты',
                    children: [
                      if (_myBots.isEmpty)
                        TheavListRow(
                          leading: iconoir.PlusCircle(
                            width: 22,
                            height: 22,
                            color: palette.primary,
                          ),
                          title: 'Создать первого бота',
                          subtitle:
                              'Настроить Mini App, меню команд и Inline-режим без кода',
                          showChevron: true,
                          onTap: _showCreateBotSheet,
                        )
                      else ...[
                        for (final bot in _myBots)
                          TheavListRow(
                            leading: _botAvatar(bot, palette),
                            title: bot.displayName.isNotEmpty
                                ? bot.displayName
                                : '@${bot.username ?? 'bot'}',
                            subtitle: _buildBotSubtitle(bot),
                            showChevron: true,
                            onTap: () => _showManageBotSheet(bot),
                          ),
                        TheavListRow(
                          leading: iconoir.Plus(
                            width: 22,
                            height: 22,
                            color: palette.primary,
                          ),
                          title: 'Создать нового бота',
                          showChevron: true,
                          onTap: _showCreateBotSheet,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _botAvatar(BotInfo bot, TheavPalette palette) {
    final provider = avatarImageProvider(bot.avatarUrl);
    final label = bot.displayName.isNotEmpty
        ? bot.displayName
        : (bot.username ?? 'B');
    final initial = label.trim().isNotEmpty
        ? String.fromCharCode(label.trim().runes.first).toUpperCase()
        : 'B';
    return CircleAvatar(
      radius: 18,
      backgroundColor: palette.primary.withValues(alpha: 0.14),
      backgroundImage: provider,
      child: provider == null
          ? Text(
              initial,
              style: TextStyle(
                color: palette.primary,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }

  String _buildBotSubtitle(BotInfo bot) {
    final tags = <String>[
      if (bot.username != null && bot.username!.isNotEmpty) '@${bot.username}',
      if (bot.hasAnyWebApp) 'Mini App',
      if (bot.supportsInlineQueries) 'Inline',
    ];
    return tags.join(' · ');
  }
}
