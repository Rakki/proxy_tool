# Proxy Tool

Android-only Flutter proxy client with per-app routing through `VpnService`.

Проект сейчас уже умеет:

- хранить несколько proxy-профилей;
- редактировать и запускать сохраненные профили;
- выбирать режим `All traffic` или `Selected apps`;
- выбирать установленные приложения из списка;
- поднимать и останавливать VPN на Android;
- отправлять трафик через `tun2proxy`;
- показывать runtime-логи в UI;
- не падать вместе с VPN-движком на `Stop`, потому что `ProxyVpnService` вынесен в отдельный процесс.

## Текущий статус

Рабочее сейчас:

- платформа: Android only;
- UI: Flutter;
- VPN слой: `VpnService` на Kotlin;
- сетевой движок: `tun2proxy`;
- основной рабочий сценарий: `SOCKS5`;
- запуск и остановка профиля с главного экрана;
- хранение профилей и логов в `shared_preferences`;
- app picker через `installed_apps`;
- runtime events из VPN-процесса обратно в Flutter через broadcast relay.

Что уже подтверждено в проекте:

- `Start` поднимает VPN;
- `Stop` завершает VPN;
- приложение не падает при `Stop`, даже если `tun2proxy` нестабилен на shutdown;
- список профилей, редактирование и логи работают;
- выбранные приложения передаются в Android слой и используются для `allowedApplications`.

## Архитектура

### Flutter

Отвечает за:

- домашний экран со списком профилей;
- экран создания/редактирования профиля;
- выбор установленных приложений;
- экран логов;
- хранение конфигураций;
- отображение active profile и runtime-событий.

Основные файлы:

- `lib/main.dart`
- `lib/screens/home_screen.dart`
- `lib/screens/connection_form_screen.dart`
- `lib/screens/app_picker_screen.dart`
- `lib/screens/logs_screen.dart`
- `lib/models/proxy_connection.dart`
- `lib/data/connection_storage.dart`

### Android

Отвечает за:

- `VpnService.prepare()`;
- запуск и остановку `ProxyVpnService`;
- маршрутизацию `all traffic` / `selected apps`;
- foreground lifecycle;
- интеграцию с native `tun2proxy`;
- пересылку runtime events обратно в Flutter.

Основные файлы:

- `android/app/src/main/kotlin/org/roboratory/proxy_tool/MainActivity.kt`
- `android/app/src/main/kotlin/org/roboratory/proxy_tool/ProxyVpnService.kt`
- `android/app/src/main/kotlin/org/roboratory/proxy_tool/RuntimeEventDispatcher.kt`
- `android/app/src/main/kotlin/org/roboratory/proxy_tool/NativeTun2ProxyBridge.kt`
- `android/app/src/main/AndroidManifest.xml`

### Native bridge

JNI bridge и C++ слой:

- `android/app/src/main/cpp/native_tun2proxy_bridge.cpp`
- `android/app/src/main/cpp/CMakeLists.txt`

Native libs:

- `android/app/src/main/jniLibs/...`

## Что реализовано

### Профили подключений

Есть:

- создание профиля;
- редактирование профиля;
- сохранение профиля;
- сохранение активного профиля;
- `Start` / `Stop` на карточке профиля.

Поля профиля:

- имя;
- тип прокси: `socks5`, `http`, `https`;
- host;
- port;
- username;
- password;
- routing mode;
- selected apps.

### Routing mode

Поддерживаются:

- `All traffic`
- `Selected apps`

Для `Selected apps`:

- пользователь выбирает приложения из списка установленных;
- Android layer использует `addAllowedApplication(...)`.

### VPN runtime

Есть:

- запрос VPN permission;
- запуск `ProxyVpnService`;
- foreground notification;
- `Start` / `Stop`;
- runtime logs;
- isolated VPN process через `android:process=":vpn"`.

### Логи

В UI уже видно:

- старт VPN;
- stop request;
- `tun2proxy` exit;
- runtime errors;
- traffic counters;
- endpoint / proxy type / routing mode / apps count;
- native log messages, если их присылает движок.

## Известные ограничения

### 1. Основной реальный target сейчас: SOCKS5

Хотя в UI есть `HTTP` и `HTTPS`, надежно подтвержденный рабочий сценарий сейчас только `SOCKS5`.

`HTTP` / `HTTPS CONNECT` оставлены в модели и форме, но их нужно отдельно проверить и довести.

### 2. `tun2proxy` нестабилен на shutdown

Что происходит:

- сам VPN lifecycle у нас уже стабилен;
- UI больше не падает;
- но `tun2proxy` может абортиться на shutdown внутри своего native-кода.

Текущее решение:

- `ProxyVpnService` вынесен в отдельный процесс;
- crash VPN-движка не убивает основной Flutter UI.

Это обходной путь, а не окончательное решение.

### 3. Логи сейчас диагностические, не полноценные access logs

Есть:

- runtime events;
- counters;
- endpoint;
- route mode;
- errors.

Пока нет:

- полного per-connection списка всех TCP/UDP соединений;
- надежного сопоставления `app -> dst ip:port` для каждой сессии;
- URL-level logging;
- HTTPS inspection.

### 4. IPv6 и DNS надо еще доводить

По логам уже видно, что часть IPv6-трафика помечается как `unhandled transport`.

Это значит:

- базовый сценарий работает;
- но стек еще не доведен до production-level качества для всех сетевых edge cases.

### 5. Play Store публикация отдельно потребует проработки

В проекте используется `QUERY_ALL_PACKAGES` для app picker.

Для internal/dev это приемлемо. Для публикации в Google Play нужно:

- обосновать core functionality;
- подготовить privacy policy;
- подготовить Permissions Declaration Form;
- возможно сделать отдельный `play` flavor.

## Что нужно доделать

### Высокий приоритет

1. Нормальный live status на главном экране

Сделать состояния:

- `Idle`
- `Starting`
- `Active`
- `Stopping`
- `Error`

Сейчас UI знает только active profile id и часть runtime events.

2. Синхронизация UI со смертью VPN-процесса

Нужно аккуратно закрыть кейсы:

- VPN process crashed;
- VPN process stopped without явного Flutter action;
- профиль остался помечен как активный после нештатного завершения.

Часть этого уже есть, но нужно сделать полноценную status model.

3. Проверка и доведение `HTTP` / `HTTPS CONNECT`

Сейчас эти типы есть на уровне формы и маппинга, но не считаются production-ready.

4. Улучшение runtime logs

Нужно добавить:

- фильтрацию по типам;
- очистку логов;
- возможно live counters на home screen;
- более структурированные события вместо плоского текста.

### Средний приоритет

5. Access logs уровня соединений

Желаемый результат:

- какое приложение открыло соединение;
- куда именно: `ip:port`;
- протокол;
- tx/rx per session.

Это уже потребует дополнительной логики поверх текущего runtime слоя.

6. Доведение DNS/IPv6

Нужно отдельно проверить:

- IPv6 behavior;
- DNS edge cases;
- поведение на разных Android-устройствах и сетях.

7. Очистка Android lifecycle

Хотя текущее поведение рабочее, lifecycle вокруг `tun2proxy` и отдельного процесса стоит упростить и документировать лучше.

### Низкий приоритет / позже

8. Поддержка других proxy engines

Если `tun2proxy` продолжит создавать проблемы, следующий реалистичный шаг:

- заменить сетевой движок, не переписывая Flutter UI.

Кандидаты:

- `sing-box`
- `hev-socks5-tunnel`

9. Material polishing

UI уже обновлен под более современный стиль, но можно еще добавить:

- live status indicators;
- transition animations;
- richer diagnostics cards;
- better error surfaces.

## Что не входит в текущий scope

Сейчас не делается:

- iOS;
- desktop;
- MITM;
- HTTPS content inspection;
- production-grade traffic analytics;
- публикация в Google Play;
- enterprise policy tooling.

## Проверка проекта

Локально уже прогонялось:

- `flutter analyze`
- `./gradlew :app:assembleDebug`

Проверка реального трафика и device-specific поведения делается на Android-устройстве.

## Короткий roadmap

Ближайшая последовательность выглядит так:

1. доделать live status model;
2. улучшить экран логов и counters;
3. довести `HTTP` / `HTTPS CONNECT`;
4. проверить DNS/IPv6 edge cases;
5. решить, оставаться ли на `tun2proxy` или менять движок.
