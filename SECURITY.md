[English](#english) | [Русский](#русский)

# Security Policy / Политика безопасности

## English

### Reporting a Vulnerability

Please do not publish security bugs in GitHub Issues, Discussions, or community chats before a fix is out.

Send vulnerability reports privately through either option:

- GitHub Security tab: [github.com/MootSasa/theaver-frontend/security](https://github.com/MootSasa/theaver-frontend/security) (click **Report a vulnerability**)
- Email: [security@theaver.app](mailto:security@theaver.app)

Include reproduction steps, the affected platform or endpoint, the client version from Settings -> About Theaver, and potential impact. We aim to acknowledge reports within 72 hours and coordinate public disclosure after shipping a fix.

### Supported Targets

Security patches focus on the latest Stable release (`main`), the latest Beta build (`beta`), and the live Web client at [app.theaver.app](https://app.theaver.app).

### Good-Faith Testing

Testing strictly against your own test accounts is welcome, provided you do not access another user's data, degrade availability, or run automated brute-force or denial-of-service traffic.

### Verification Keys and Policy File

- Machine-readable policy (RFC 9116): [theaver.app/.well-known/security.txt](https://theaver.app/.well-known/security.txt)
- Web security overview: [theaver.app/security](https://theaver.app/security)
- Linux GPG public key: [signing/linux/theaver-release-public.asc](./signing/linux/theaver-release-public.asc)
- Windows Root CA certificate: [signing/windows/theaver-windows-root.cer](./signing/windows/theaver-windows-root.cer)

---

## Русский

### Как сообщить об уязвимости

Не публикуйте детали найденных уязвимостей в открытых GitHub Issues, Discussions или пользовательских чатах до выхода исправления.

Передайте отчёт приватно одним из двух способов:

- Вкладка безопасности на GitHub: [github.com/MootSasa/theaver-frontend/security](https://github.com/MootSasa/theaver-frontend/security) (кнопка **Report a vulnerability**)
- Электронная почта: [security@theaver.app](mailto:security@theaver.app)

Опишите шаги воспроизведения, затронутую платформу или эндпоинт, версию клиента из Настройки -> О приложении и возможный эффект. Мы стараемся отвечать в течение 72 часов и согласовывать публикацию деталей после выпуска исправления.

### Поддерживаемые версии

Исправления безопасности выходят для актуального релиза Stable (`main`), последней сборки Beta (`beta`) и текущей веб-версии на [app.theaver.app](https://app.theaver.app).

### Добросовестные проверки

Мы приветствуем исследования безопасности, если они проводятся только на собственных тестовых аккаунтах без чтения чужих данных, вмешательства в работу сервиса и массовой генерации трафика.

### Ключи проверки и стандарты

- Файл стандарта RFC 9116: [theaver.app/.well-known/security.txt](https://theaver.app/.well-known/security.txt)
- Страница безопасности на русском: [theaver.app/ru/security](https://theaver.app/ru/security)
- Публичный GPG-ключ для Linux: [signing/linux/theaver-release-public.asc](./signing/linux/theaver-release-public.asc)
- Корневой сертификат Windows: [signing/windows/theaver-windows-root.cer](./signing/windows/theaver-windows-root.cer)
