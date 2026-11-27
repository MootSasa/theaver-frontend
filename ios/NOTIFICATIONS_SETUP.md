# iOS: системные уведомления чатов (Communication Notifications)

Что уже сделано в репозитории (Xcode-проект `Runner.xcodeproj` **не** изменялся — это делается вручную на Mac по шагам ниже):

| Файл | Назначение |
|---|---|
| `ios/NotificationService/NotificationService.swift` | Notification Service Extension: аватар отправителя/чата, `INSendMessageIntent` → Communication Notification, группировка по `thread-id = chat_<id>`, категория `message` |
| `ios/NotificationService/Info.plist` | `NSExtension` (`com.apple.usernotifications.service`, `IntentsSupported = [INSendMessageIntent]`) |
| `ios/NotificationService/NotificationService.entitlements` | App Group + Communication Notifications для расширения |
| `ios/Flutter/NotificationService.xcconfig` | Базовая конфигурация расширения: подтягивает `FLUTTER_BUILD_NAME/NUMBER` из `Generated.xcconfig` (версия расширения = версия приложения) |
| `ios/Runner/AppDelegate.swift` | MethodChannel `app.theaver.messenger/native_notifications`, категории `message`/`incoming_call`, нативная обработка «Ответить»/«Прочитано» для remote-пушей (работает и при убитом приложении) |
| `ios/Runner/Info.plist` | `NSUserActivityTypes = [INSendMessageIntent]` |
| `ios/Runner/Runner.entitlements` | + `com.apple.developer.usernotifications.communication`, + App Group `group.app.theaver.messenger` |

Как это работает:

1. Flutter после логина вызывает `configure` (`base_url`, `storage_url`, `token`, `user_id`) → значения пишутся в общий `UserDefaults(suiteName: "group.app.theaver.messenger")` (ключи `notif_base_url`, `notif_storage_url`, `notif_auth_token`, `notif_user_id`; пустой `token` = удаление, т.е. logout).
2. Пуш с `mutable-content: 1` будит расширение → оно скачивает аватар (до 5 с; если нет — рисует кружок с инициалами), донатит `INInteraction` и вызывает `content.updating(from: intent)`.
3. Действия «Ответить»/«Прочитано» на remote-пуше обрабатывает `AppDelegate` нативно: `POST {base}/api/chats/{id}/messages` и/или `POST {base}/api/chats/{id}/messages/read` с `Authorization: Bearer <token>`.

---

## 0. Требования

- Mac с Xcode 15+ (проверено по API: iOS 15 SDK и выше), CocoaPods.
- Доступ к Apple Developer аккаунту (Team) с правами на Identifiers/Capabilities.
- Communication Notifications работают на **iOS 15+**. На iOS 14 расширение просто проставляет `thread-id`/категорию (весь iOS 15 код под `#available`).

## 1. Apple Developer Portal

1. **Identifiers → App Groups → +**: `group.app.theaver.messenger`.
2. **Identifiers → `app.theaver.messenger`**: включить *App Groups* (выбрать группу выше), *Push Notifications*, *Communication Notifications*, *Time Sensitive Notifications*.
3. **Identifiers → + App ID** `app.theaver.messenger.NotificationService`: включить *App Groups* (та же группа) и *Communication Notifications*.
4. При ручном подписании — перевыпустить provisioning profiles для обоих bundle id. При *Automatically manage signing* Xcode сделает это сам.

## 2. Добавить target расширения в Xcode

> [!IMPORTANT]
> Папка `ios/NotificationService/` уже лежит в репозитории. Чтобы Xcode не конфликтовал с существующими файлами при создании target'а, временно переименуйте её.

```bash
cd frontend/ios
mv NotificationService NotificationService.ours
open Runner.xcworkspace
```

1. **File → New → Target… → iOS → Notification Service Extension → Next**.
2. Product Name: `NotificationService`, Language: **Swift**, Team: ваш, Project: `Runner`, Embed in Application: `Runner` → **Finish**.
3. На вопрос *Activate "NotificationService" scheme?* → **Cancel** (схему активировать не нужно, запускаем схему Runner).
4. Закройте Xcode и замените сгенерированные файлы нашими:

```bash
cd frontend/ios
cp NotificationService.ours/NotificationService.swift NotificationService/NotificationService.swift
cp NotificationService.ours/Info.plist NotificationService/Info.plist
cp NotificationService.ours/NotificationService.entitlements NotificationService/NotificationService.entitlements
rm -rf NotificationService.ours
git status   # в папке должны остаться только наши 3 файла (+ изменения project.pbxproj)
```

5. Откройте `Runner.xcworkspace` снова. Если `NotificationService.entitlements` не виден в навигаторе — перетащите его в группу `NotificationService` (**Target Membership: ни одной галочки** — entitlements не должен попадать в Copy Bundle Resources).

> [!NOTE]
> Xcode 16 может создать папку как *synchronized folder* (синяя иконка). Тогда все файлы папки автоматически попадают в target. Проверьте **NotificationService → Build Phases → Copy Bundle Resources**: там **не должно** быть `Info.plist` и `NotificationService.entitlements` (иначе ошибка *Multiple commands produce …Info.plist*). Если они есть — выделите файл в навигаторе и снимите Target Membership (Xcode добавит исключение).

## 3. Build Settings расширения (target `NotificationService`)

| Настройка | Значение |
|---|---|
| **iOS Deployment Target** (`IPHONEOS_DEPLOYMENT_TARGET`) | `14.0` (как у Runner; можно `15.0` — тогда на iOS 14 расширение не будет запускаться) |
| **Product Bundle Identifier** | `app.theaver.messenger.NotificationService` |
| **Info.plist File** (`INFOPLIST_FILE`) | `NotificationService/Info.plist` |
| **Generate Info.plist File** (`GENERATE_INFOPLIST_FILE`) | `NO` |
| **Code Signing Entitlements** (`CODE_SIGN_ENTITLEMENTS`) | `NotificationService/NotificationService.entitlements` |
| **Swift Language Version** | `Swift 5` |
| **Development Team** / Signing | тот же Team, *Automatically manage signing* |
| `TARGETED_DEVICE_FAMILY` | `1,2` (как у Runner) |

**Базовая конфигурация (версия расширения = версия приложения):**
**Project Runner → Info → Configurations** → раскройте `Debug`, `Release`, `Profile` → для строки target'а `NotificationService` выберите `NotificationService` (файл `Flutter/NotificationService.xcconfig`) во **всех трёх** конфигурациях.

> [!WARNING]
> Не назначайте расширению `Flutter/Debug.xcconfig` / `Release.xcconfig` и `Pods-Runner.*.xcconfig` — они линкуют Flutter и поды. Если `CFBundleShortVersionString`/`CFBundleVersion` расширения окажутся пустыми (xcconfig не назначен или `flutter pub get` ещё не создал `Generated.xcconfig`), установка на устройство упадёт. Альтернатива: вписать в `NotificationService/Info.plist` `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` и вести версии вручную.

## 4. Target `Runner`

1. **Build Settings → Code Signing Entitlements** (`CODE_SIGN_ENTITLEMENTS`) = `Runner/Runner.entitlements` для **Debug, Release и Profile**.
   > Сейчас в `project.pbxproj` этот параметр **не задан**, т.е. `Runner.entitlements` (aps-environment, time-sensitive) фактически не используется — без этого шага не будут работать ни пуши, ни новые capabilities.
2. **Signing & Capabilities** (если капабилити уже есть в entitlements, Xcode просто покажет их; следите, чтобы Xcode не создал второй `.entitlements`-файл):
   - Push Notifications
   - Time Sensitive Notifications
   - Communication Notifications
   - App Groups → `group.app.theaver.messenger`
   - Background Modes → *Remote notifications* (и *Audio*, уже есть в Info.plist)
3. **Target NotificationService → Signing & Capabilities**:
   - App Groups → `group.app.theaver.messenger`
   - Communication Notifications
4. **Build Phases target Runner**: перетащите фазу **Embed Foundation Extensions** (или *Embed App Extensions*) **выше** фазы **Thin Binary** (и выше `[CP] Embed Pods Frameworks`, если мешает). Иначе Flutter-проекты падают с ошибкой *Cycle inside Runner; building could produce unreliable results*.

## 5. CocoaPods

- В `Podfile` **ничего добавлять не нужно**: расширение не использует Flutter и поды (только `UserNotifications`, `Intents`, `UIKit`, `ImageIO`). Не добавляйте `target 'NotificationService'` внутрь `target 'Runner'` (иначе он унаследует `flutter_install_all_ios_pods`).
- После добавления target'а выполните:

```bash
cd frontend && flutter pub get && cd ios && pod install
```

- Если `pod install` ругается на новый target — допустимо добавить в `Podfile` пустой блок **вне** `target 'Runner'`:

```ruby
target 'NotificationService' do
  use_frameworks!
end
```

## 6. Firebase / APNs

1. **Firebase Console → Project settings → Cloud Messaging → Apple app configuration**: загрузить **APNs Authentication Key** (`.p8`, Key ID, Team ID). Ключ создаётся в Apple Developer → Keys → + → *Apple Push Notifications service (APNs)*.
2. `Firebase.initializeApp()` вызывается без `options`, поэтому нужен **`ios/Runner/GoogleService-Info.plist`** (скачать из Firebase для iOS-приложения с bundle id `app.theaver.messenger`) и добавить в target **Runner** (не в расширение). Файла сейчас нет в репозитории.
3. Сервер обязан слать в `aps`: `mutable-content: 1` (иначе расширение не вызовется), `thread-id: "chat_<id>"`, `category: "message"`, `alert {title, body}`; data-ключи: `type=new_message`, `chat_id`, `chat_name`, `chat_type`, `is_group`, `sender_id`, `sender_name`, `message_text`, `avatar_url`, `sender_avatar_url`.
4. `aps-environment` в `Runner.entitlements` = `development`; при Archive Xcode подставит `production` сам.

## 7. Flutter-сторона (контракт канала)

`MethodChannel('app.theaver.messenger/native_notifications')`:

| Метод | Аргументы | iOS |
|---|---|---|
| `configure` | `{base_url, storage_url, token, user_id}` | сохраняет в App Group (пустой/`null` → удаляет ключ). Вызывать после логина, при обновлении токена и при logout (`token: ''`) |
| `cancelChat` | `{chat_id}` | удаляет доставленные уведомления с `threadIdentifier == "chat_<id>"` (или `userInfo.chat_id`) |
| `cancelAll` | — | `removeAllDeliveredNotifications()` |
| `setState`, `showChatNotification`, `getInitialTap` | — | no-op (`nil`) |

`base_url` — адрес API **без** `/api` (если `/api` на конце есть — он отрезается). Относительные аватары: `/avatars/...` → `storage_url`, остальные `/...` → `base_url`. Токен прикладывается к загрузке аватара только для хостов `base_url`/`storage_url`.

## 8. Чек-лист тестирования (реальное устройство, iOS 15+)

- [ ] Сборка схемы **Runner** проходит, в `Runner.app/PlugIns/NotificationService.appex` есть расширение.
- [ ] Приложение запущено, выполнен вход → в логах нет ошибок канала `native_notifications`.
- [ ] Приложение в фоне, личное сообщение → уведомление с **аватаром собеседника** и его именем в заголовке.
- [ ] Собеседник без аватара → кружок с инициалами.
- [ ] Сообщение в группе → имя отправителя + название группы, аватар отправителя (и аватар группы, если есть).
- [ ] Несколько сообщений из одного чата **группируются** в стопку; разные чаты — отдельные стопки.
- [ ] Long-press → «Ответить» → текст → «Отправить»: сообщение появилось в чате на другом устройстве, уведомления чата убраны.
- [ ] Long-press → «Прочитано»: у собеседника сообщения прочитаны, уведомления чата убраны, приложение **не** открылось.
- [ ] То же самое при **убитом** приложении (свайп из App Switcher) — оба действия работают.
- [ ] Ответ без сети → приходит локальное уведомление «Не удалось отправить сообщение…».
- [ ] Logout → `configure(token: '')` → действия больше не отправляют запросы.
- [ ] Входящий звонок: кнопки «Принять»/«Отклонить» на месте.
- [ ] Focus/«Не беспокоить»: при разрешении людей-исключений уведомления от них проходят (признак Communication Notification).
- [ ] Отладка расширения: Xcode → Debug → Attach to Process by PID or Name… → `NotificationService`, затем отправить пуш.
