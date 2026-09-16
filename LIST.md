# 📋 MilfaCheatHUB — журнал проекта

Общий журнал разработки. Первый игровой проект: **Steal An Egg**.

## Проект

**MilfaCheatHUB** — модульные Roblox Lua-интерфейсы в едином тёмном Minecraft PvP / cyberpunk-стиле.

- фон `#08070D`;
- панели `#151020` и `#20152F`;
- акцент `#A855F7`;
- ESP `#C084FC`;
- движение `#29D9FF`;
- мир `#6366FF`;
- текст `#E7E5EC`;
- общая иконка `/icon.png`.

## Steal An Egg

- PlaceId: `107778070777162`;
- папка: `/Steal-A-Egg/`;
- точка входа: `/Steal-A-Egg/main.lua`;
- текущая версия: `0.4.1`.

## Структура

```text
MilfaCheatHUB/
├── README.md
├── LIST.md
├── icon.png
└── Steal-A-Egg/
    ├── main.lua
    └── modules/
        ├── config.lua
        ├── stealth.lua
        ├── rarity.lua
        ├── ui.lua
        ├── scanner.lua
        ├── eggs.lua
        ├── network.lua
        ├── positions.lua
        ├── esp.lua
        ├── automation.lua
        ├── player.lua
        └── features.lua
```

## Назначение файлов

- `main.lua` — стабильная последовательная загрузка, обработка ошибок и полный cleanup;
- `config.lua` — название, версия, RAW-ссылки, цвета и настройки;
- `stealth.lua` — стелс-ядро: скрытый маунт (gethui/CoreGui/маскировка PlayerGui), случайные имена,
  glide-телепорты, джиттер задержек, поиск античит-скриптов;
- `rarity.lua` — движок редкостей: 16 тиров, ключевые слова, ранги, цвета;
- `ui.lua` — loading screen, интерфейс, вкладки, слайдеры, чипы, дропдауны, список яиц;
- `scanner.lua` — динамический поиск яиц, участка и биомов;
- `eggs.lua` — богатые записи яиц: редкость, дистанция, промпты, фильтры, поиск Sell-ремоутов, ростер питомцев;
- `network.lua` — диагностика известных RemoteFunction/RemoteEvent;
- `positions.lua` — живые позиции базы, границы и биомов;
- `esp.lua` — клиентский Egg ESP с цветами по редкости;
- `automation.lua` — автокража, автопостановка, автовылупление, автопродажа, автосбор, дорожка, сервер-хоп, монстр;
- `player.lua` — стелс-скорость (CFrame-glide без WalkSpeed), классический WalkSpeed, прыжок, бесконечный прыжок, noclip, клик-ТП через glide, anti-AFK;
- `features.lua` — 6 вкладок, обновление данных, ESP, статусы, секция СТЕЛС, PANIC.

## Список функций 0.4.1 (STEALTH, 55+)

Вкладка СИСТЕМА — блок «СТЕЛС и античит (BAC-75110)»:

- скрытый маунт GUI и ESP: `gethui()` → `CoreGui` → маскировка под имя игрового ScreenGui в PlayerGui;
- случайные имена всех инстансов (ScreenGui, Bubble, ESP-папка, Highlight, BillboardGui) — статичных «MilfaCheatHUB_*» больше нет;
- `syn.protect_gui`/`protect_gui` при наличии;
- безопасные телепорты: все CFrame-прыжки заменены на плавный glide со скоростью по слайдеру (держать < 70 ст/с);
- СТЕЛС-скорость: движение через CFrame в Heartbeat, `Humanoid.WalkSpeed` остаётся 16 — вотчеры WalkSpeed не срабатывают;
- человеческие задержки: джиттер 0.75x–1.35x на все паузы автокражи/продажи/хатча/экипировки и главный цикл (мин. 1.0 с);
- лимит AskHatch за такт (настройка 1–8, по умолчанию 4);
- диагностика: фактический маунт GUI, поиск античит-скриптов в консоль F9;
- PANIC: кнопка в GUI и `getgenv().MilfaPanic()` — мгновенно убивает GUI, ESP, циклы, возвращает 16/50.

### Функции 0.3.x (сохранены полностью)

Вкладка ЯЙЦА:

- живой список яиц с цветом по редкости и кнопками TP/СТЛ у каждого яйца;
- фильтр редкости (18 чипов, общий для списка, ESP-фильтра и автокражи);
- макс. дистанция списка (слайдер), сортировка rarity/distance, автообновление;
- FirstAreaSlotKey парсится из Uid автоматически (формат `FirstAreaEgg_<id>_<id>_<Bioм:Slot_NNN>`).

Вкладка АВТО:

- автокража с фильтром по редкости, приоритет редкость/дистанция, радиус поиска, пауза;
- телепорт к цели или ходьба; авто-возврат на базу и постановка (AskPlaceEgg);
- сброс яйца из рук; автопостановка яиц из инвентаря;
- автовылупление: AskHatch по hex-UID из save.EggInventory + GrowingEggs-кнопки;
- автосбор дохода (AskCollect `{Kind="Claim"}`);
- дорожка AskWearStill + цикл схода AskDoff каждые 5с;
- автоулучшение дорожки (AskTierRaise с автоопределением ID) и базы (AskBaseTierRaise);
- автонадевание лучших питомцев: ToolTrigger + PenRoster/AskWear + FetchWearBestStatus;
- отключение чужих ловушек (`__DEBRIS.PlayerTrap` → CanTouch/CanQuery=false);
- автопродажа через RE/PetSatchel/SellPet: яйца — AskWearTool(uid) + SellPet({uid}),
  питомцы — SellPet(uid); фильтр НЕ-продавать по редкости, защита Locked/IsFavorite/InFuse;
- смена сервера (ручная и авто при пустых целях), кормление монстра события.

Вкладка ESP:

- Egg ESP с цветом и подписью редкости, дистанция, дальность, режим "только по фильтру".

Вкладка ИГРОК:

- WalkSpeed и JumpPower слайдеры со сбросом, автоприменение после респавна,
  бесконечный прыжок, noclip, телепорт кликом, Anti-AFK.

Вкладка ТОЧКИ: динамические точки, телепорт на базу.
Вкладка СИСТЕМА: проверка Remotes (21 эндпоинт), поиск Sell-ремоутов, дамп всех Remotes в консоль, FPS-режим.

## Редкости (по вики и открытым скриптам)

Divine, Eternal, Secret, Cosmic, Titan, LightDark, Godly, Brainrot, Monster, Mecha,
Mythic, Legendary, Epic, Rare, Uncommon, Common (+ Unknown). Яйца ресетятся каждые 5 минут.
Канонический порядок каталога игры: Common → Uncommon → Rare → Epic → Legendary →
Mythic → Cosmic → Secret → Eternal → Divine; редкость яиц резолвится через `RS.Data.Assets.Directory`.

## Исправления интерфейса 0.2.0

- GUI уменьшен с `660×438` до `570×360`;
- добавлено автоматическое масштабирование под небольшой экран;
- переработаны панели, градиенты, контуры, карточки и переключатели;
- значки вкладок заменены на надёжные бейджи `EGG`, `ESP`, `POS`, `SYS`, которые не зависят от поддержки Unicode-шрифта;
- добавлены отдельные кнопки **скрыть** и **закрыть**;
- при скрытии остаётся перетаскиваемый круг с `icon.png`;
- нажатие на круг возвращает главное окно;
- `RightControl` также переключает окно и круг;
- при закрытии останавливаются циклы, выключается ESP, восстанавливается FPS-режим, удаляются GUI и ESP-объекты;
- повторный запуск сначала полностью очищает старую сессию.

## Исправления загрузки

Причиной зависаний могли быть синхронная повторная загрузка картинки и лишние повторные сканирования.

Сделано:

- `icon.png` теперь загружается асинхронно и только один раз за сессию;
- пока картинка загружается, показывается резервный логотип `M`;
- удалены искусственные долгие задержки loading screen;
- добавлен `xpcall`: ошибка модуля больше не оставляет зависший GUI;
- сканер не запускается постоянно, пока ESP выключен;
- при включённом ESP обновление выполняется раз в 3 секунды;
- устранён двойной скан списка яиц в одном цикле;
- FPS-режим обрабатывает Workspace частями, не блокируя кадр надолго.

## Подтверждённые RSpy-вызовы

Общий путь: `ReplicatedStorage.Packages.Networking`.

| Действие | Endpoint | Аргументы |
|---|---|---|
| Взять яйцо | `RF/EggWorld/AskFieldEggCarry` | `{FirstAreaSlotKey = "Forest:Slot_004", Uid = "FirstAreaEgg_…_Forest:Slot_004"}` |
| Поставить яйцо | `RF/EggWorld/AskPlaceEgg` | `{Uid, LocalCFrame}` |
| Вылупить | `RF/EggWorld/AskHatch` | hex-UID строкой (`"3cb9…"`) |
| Продать яйцо | `RF/EggWorld/AskWearTool` → `RE/PetSatchel/SellPet` | `AskWearTool(uid)`, затем `SellPet:FireServer({uid})` |
| Продать питомца | `RE/PetSatchel/SellPet` | `SellPet:FireServer(uid)` строкой |
| Встать на дорожку | `RF/Treadmill/AskWearStill` | без аргументов |
| Сойти | `RF/Treadmill/AskDoff` | без аргументов |
| Улучшить дорожку | `RF/Treadmill/AskTierRaise` | ID дорожки (`"FlameTreadmill"`) |
| Улучшить базу | `RE/Homestead/AskBaseTierRaise` | `FireServer()` без аргументов |
| Слот питомца | `RE/ToolTrigger/Trigger` | `FireServer(Instance.new("Tool"))` |
| Надеть питомца | `RF/PenRoster/AskWear` | UID питомца строкой |
| Убрать питомца | `RF/PenRoster/AskDoff` | UID питомца строкой |
| Статус лучшего | `RF/Haul/FetchWearBestStatus` | без аргументов |
| Забрать доход | `RF/AwayEarnings/AskCollect` | `{Kind = "Claim"}` |

UID, слоты и `LocalCFrame` динамические. Прямого ремоута кражи яиц у игроков
в игре нет — только полевые яйца биомов, промпты и PvP-механики.
Инвентарь читается клиентски: `RS.Shared.Save.Get()` → `.Inventory` (питомцы:
`.Rarity/.Locked/.IsFavorite/.InFuse`), `.EggInventory` (яйца: `.Placement/.AssetCategory/.Locked`).

## Позиции

Диагностические ориентиры:

```lua
Anchor = Vector3.new(536.4492797851562, 70.28306579589844, -365.0294189453125)
GateIn = Vector3.new(578, 70.3, -365.03)
SafeZone = Vector3.new(545, 68, -364)
```

X-ориентиры: Forest `602`, Lake `746`, Desert `785`, Jungle `936`, Snow `1076`, Volcano `1202`, Abyss Ocean `1370`, Prehistoric `1580`, Cosmic `1772`, Cherry Blossom `2479`.

Код предпочитает живые источники:

- `record.BottomCFrame.Position`;
- `AreaEggSlotsClient`;
- `PlotCmds.GetPlotData().PetArea`;
- `CenterPoint`;
- `Workspace.__OBJECTS.Areas.GuardAreas`;
- `SeparationLine`.

## Текущая сборка

Готово:

- [x] модульная RAW-загрузка;
- [x] компактный loading screen с `icon.png`;
- [x] асинхронная загрузка и кэш иконки;
- [x] фирменный GUI MilfaCheatHUB;
- [x] рабочие бейджи вкладок;
- [x] кнопки закрытия и скрытия;
- [x] круглая кнопка с иконкой после скрытия;
- [x] полный cleanup;
- [x] динамический сканер;
- [x] диагностика Networking;
- [x] Egg ESP с цветами редкости;
- [x] FPS-режим с восстановлением;
- [x] обработка ошибок загрузки;
- [x] список яиц с фильтрами, TP и кражей по кнопке (0.3.0);
- [x] движок редкостей на 16 тиров (0.3.0);
- [x] автокража с фильтром редкости и приоритетом (0.3.0);
- [x] автопродажа яиц и питомцев с keep-фильтром (0.3.0, через SellPet — 0.3.1);
- [x] автовылупление, автосбор дохода, дорожка (0.3.0);
- [x] скорость, прыжок, noclip, клик-ТП, Anti-AFK (0.3.0);
- [x] сервер-хоп и событие монстра (0.3.0);
- [x] RSpy-фиксы: FirstAreaSlotKey, AskHatch строкой, SellPet-продажа (0.3.1);
- [x] автоулучшение дорожки и базы (0.3.1);
- [x] автонадевание лучших питомцев (0.3.1);
- [x] отключение чужих ловушек (0.3.1);
- [x] ресёрч читов Steal A Egg на GitHub/ScriptBlox — карта ремоутов, редкостей и анти-чита (0.3.1);
- [x] STEALTH-слой против BAC-75110: скрытый маунт, рандом-имена, glide-TP, стелс-скорость, джиттер, PANIC (0.4.0).
- [x] фикс краша загрузки 0.4.0 (loadingStep до объявления) + анти-кик-гард клиентского Kick (0.4.1).

Следующий этап:

- [ ] проверить сборку 0.4.1 в игре: загрузка без ошибок консоли и кика;
- [ ] снять RSpy-пакет SellPet для яйца (таблица `{uid}` или строка — сейчас шлём обе формы);
- [ ] проверить реальные ответы подтверждённых RemoteFunction;
- [ ] добавить мобильную настройку положения круглой кнопки;
- [ ] webhook-уведомления о редких яйцах.

## Запуск

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ffffddggt277-debug/MilfaCheatHUB/main/Steal-A-Egg/main.lua"))()
```

## Журнал

### 2026-09-17 — 0.4.1 (STEALTH HOTFIX)

- Краш при каждом запуске: `attempt to call a nil value` на строке 79 main.lua —
  `loadingStep` вызывался до собственного объявления (внесено в 0.4.0 переносом
  стелса до ShowLoader). Скрипт умирал сразу → стелс не вставал → кик через ~5 с.
- Фикс: `loadingStep` объявлен до xpcall-блока; внутри pcall-обёртка.
- loadModule: 3 попытки HttpGet с паузой (мобильные сети отдают таймаут на RAW).
- Новый анти-кик-гард в stealth.lua (`InstallKickGuard`): блок клиентского
  `LocalPlayer:Kick()` через `hookmetamethod __namecall` + `hookfunction`
  (если доступны у экзекьютора), живой тумблер `Stealth.BlockKick`.
  Серверный кик через Lua не проходит — его блокировать нельзя.
- features.lua: тоггл «Блокировать клиентский Kick» в секции СТЕЛС.
- main.lua/config.lua: версия 0.4.1.

### 2026-09-17 — 0.4.0 (STEALTH)

- Причина: кик «You have been removed for cheating… CODE BAC-75110». Разобраны векторы
  детекта: мгновенные CFrame-прыжки на 300+ стадов в автокраже, прямой `Humanoid.WalkSpeed`,
  статичные имена `MilfaCheatHUB_*` при фолбэке GUI в PlayerGui, роботные интервалы ремоутов.
- Новый модуль `stealth.lua`: скрытый маунт (gethui → CoreGui → маскировка под игровое
  ScreenGui в PlayerGui), `syn.protect_gui`, случайные имена (18 симв.), glide-телепорты
  (Heartbeat, скорость 20–100, таймаут-снап), джиттер 0.75–1.35x, поиск античит-скриптов.
- UI/ESP: все имена инстансов случайные; ESP-папка в общем скрытом контейнере;
  загрузчик тоже маунтится скрыто.
- player.lua: СТЕЛС-скорость (CFrame в Heartbeat, WalkSpeed не трогается),
  клик-ТП через glide, сброс скорости при панке/дестрое.
- automation.lua: все телепорты — glide (к цели, домой, к монстру), джиттер всех пауз,
  мин. задержка цикла 1.0 с, лимит хатча 4/такт (настройка), хатч-интервал 3с.
- features.lua: секция «СТЕЛС и античит» — статус маунта, SafeTeleport, GlideSpeed,
  джиттер, лимит хатча, PANIC, поиск античита; все ручные TP через glide.
- main.lua: `getgenv().MilfaPanic()`, stealth грузится первым, полный сброс при панке.
- Версия 0.4.0.

### 2026-09-17 — 0.3.1

- Ресёрч GitHub/ScriptBlox (12 открытых репозиториев): подтверждён sell-ремоут
  `RE/PetSatchel/SellPet`, механика продажи яйца через `AskWearTool` + `SellPet({uid})`,
  инвентарь `RS.Shared.Save.Get()` (`.Inventory`/`.EggInventory`), канонические 10 тиров
  редкостей, каталог `RS.Data.Assets.Directory`, ловушки `__DEBRIS.PlayerTrap`.
- RSpy-фиксы от пользователя: `AskFieldEggCarry` теперь шлёт и `FirstAreaSlotKey`
  (парсится из Uid `FirstAreaEgg_<id>_<id>_<SlotKey>`), `AskHatch` шлёт hex-UID строкой
  из save.EggInventory, `AskTierRaise("FlameTreadmill")`, `AskBaseTierRaise:FireServer()`,
  питомцы через `ToolTrigger` + `AskWear(uid-строка)` + `FetchWearBestStatus`.
- Автопродажа: яйца из save.EggInventory (AskWearTool → SellPet({uid})), питомцы из
  save.Inventory (SellPet(uid)); учёт Locked/IsFavorite/InFuse/Placement; лимит продаж за тик.
- Новое: автоулучшение дорожки и базы, автосход с дорожки (AskDoff), автонадевание
  лучших питомцев по рангу редкости, отключение чужих ловушек.
- Редкости: +18 тиров Titan/LightDark, каталог RS.Data.Assets, определение с инстансов
  (атрибуты/Data.Rarity.Value), автоприменение скорости после респавна.
- Версия 0.3.1, 50+ функций.

### 2026-09-17 — 0.3.0

- Ресёрч скриптов Steal An Egg (GitHub, вики): подтверждены редкости, SmartPromptPart,
  формат вызовов AskFieldEggCarry `{Uid = имя}` и AskPlaceEgg `{LocalCFrame, Uid}`,
  атрибут UID у Tool в руках, папки AreaEggSlotsClient/Eggs/SpawnedEggs.
- Новые модули: rarity, eggs, automation, player.
- UI: слайдеры, чипы редкостей, дропдауны, живой список яиц с кнопками TP/СТЛ.
- ESP перекрашен по редкости, добавлены дальность и режим фильтра.
- 40+ функций в шести вкладках: Яйца, Авто, ESP, Игрок, Точки, Система.
- Версия поднята до 0.3.0, окно увеличено до 570×380.

### 2026-09-17 — 0.2.0

- Уменьшен и полностью переработан GUI.
- Исправлены пропавшие значки вкладок.
- Добавлены скрытие, закрытие и круг с `icon.png`.
- Реализован полный cleanup всех включённых возможностей.
- Оптимизированы загрузка и сканирование для устранения зависаний.

### 2026-09-17 — 0.1.0

- Создана первая модульная сборка Steal An Egg.
- Добавлены config, UI, scanner, network, positions, ESP и feature controller.

### 2026-09-16

- Создан репозиторий, README, иконка и папка Steal An Egg.
- Исследованы механики игры, Remotes и динамические точки.
