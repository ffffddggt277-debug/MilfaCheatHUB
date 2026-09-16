# 📋 MilfaCheatHUB — журнал проекта

Этот файл находится в корне репозитория и хранит общее состояние разработки. Первый игровой проект: **Steal An Egg**.

## Проект

**MilfaCheatHUB** — набор модульных Roblox Lua-интерфейсов в едином тёмном Minecraft PvP / cyberpunk-стиле.

- основной фон: `#08070D`;
- панели: `#151020` и `#20152F`;
- главный акцент: `#A855F7`;
- ESP: `#C084FC`;
- движение: `#29D9FF`;
- мир: `#6366FF`;
- текст: `#E7E5EC`;
- общая иконка: `/icon.png`.

## Steal An Egg

Игра про поиск и доставку яиц, питомцев, пассивный доход, развитие базы, дорожки и скорости.

- PlaceId: `107778070777162`;
- папка: `/Steal-A-Egg/`;
- точка входа: `/Steal-A-Egg/main.lua`.

## Созданная структура

```text
MilfaCheatHUB/
├── README.md
├── LIST.md
├── icon.png
└── Steal-A-Egg/
    ├── main.lua
    └── modules/
        ├── config.lua
        ├── ui.lua
        ├── scanner.lua
        ├── network.lua
        ├── positions.lua
        ├── esp.lua
        └── features.lua
```

## Назначение файлов

- `main.lua` — последовательная загрузка модулей, красивый loading screen, запуск и cleanup;
- `config.lua` — название MilfaCheatHUB, версия, RAW-ссылки, палитра и настройки;
- `ui.lua` — собственный неоновый GUI, вкладки, карточки, кнопки, переключатели и загрузка `icon.png`;
- `scanner.lua` — динамический поиск яиц, своего участка и биомов;
- `network.lua` — диагностика известных RemoteFunction/RemoteEvent без автоматического вызова;
- `positions.lua` — живые позиции базы, границы и биомов плюс диагностические ориентиры;
- `esp.lua` — клиентский Egg ESP с названием, биомом и расстоянием;
- `features.lua` — вкладки GUI, автоматическое обновление данных и лёгкий FPS-режим.

## Loading screen и иконка

`ui.lua` пытается скачать корневой `icon.png`, сохранить его как локальный asset и показать в загрузочном окне и боковой панели. Если executor не поддерживает `request`, `writefile` или `getcustomasset`, автоматически используется текстовый логотип `M`.

## Подтверждённые RSpy-вызовы

Общий путь: `ReplicatedStorage.Packages.Networking`.

| Действие | Endpoint | Тип/аргументы |
|---|---|---|
| Взять яйцо | `RF/EggWorld/AskFieldEggCarry` | RemoteFunction, `{FirstAreaSlotKey, Uid}` |
| Поставить яйцо | `RF/EggWorld/AskPlaceEgg` | RemoteFunction, `{Uid, LocalCFrame}` |
| Вылупить | `RF/EggWorld/AskHatch` | RemoteFunction, UID яйца |
| Встать на дорожку | `RF/Treadmill/AskWearStill` | RemoteFunction |
| Сойти с дорожки | `RF/Treadmill/AskDoff` | RemoteFunction |
| Улучшить дорожку | `RF/Treadmill/AskTierRaise` | RemoteFunction, ID дорожки |
| Улучшить базу | `RE/Homestead/AskBaseTierRaise` | RemoteEvent |
| Надеть питомца | `RF/PenRoster/AskWear` | RemoteFunction, UID питомца |
| Убрать питомца | `RF/PenRoster/AskDoff` | RemoteFunction, UID питомца |
| Статус лучших питомцев | `RF/Haul/FetchWearBestStatus` | RemoteFunction |
| Забрать офлайн-доход | `RF/AwayEarnings/AskCollect` | RemoteFunction, `{Kind = "Claim"}` |

UID, слоты и `LocalCFrame` динамические и не должны храниться в коде постоянно.

## Позиции

Найденные диагностические ориентиры:

```lua
Anchor = Vector3.new(536.4492797851562, 70.28306579589844, -365.0294189453125)
GateIn = Vector3.new(578, 70.3, -365.03)
SafeZone = Vector3.new(545, 68, -364)
```

X-ориентиры биомов из стороннего источника:

- Forest `602`;
- Lake `746`;
- Desert `785`;
- Jungle `936`;
- Snow `1076`;
- Volcano `1202`;
- Abyss Ocean `1370`;
- Prehistoric `1580`;
- Cosmic `1772`;
- Cherry Blossom `2479`.

Эти значения не используются как таблица телепортов. `positions.lua` предпочитает:

- `record.BottomCFrame.Position` для яйца;
- `AreaEggSlotsClient` как резервный источник модели;
- `PlotCmds.GetPlotData().PetArea` для базы;
- `CenterPoint` для локальных координат участка;
- `Workspace.__OBJECTS.Areas.GuardAreas` для биомов;
- `SeparationLine` для границы.

## Анализ стороннего Luraph-файла

`Fn-stealanegg.lua` имеет размер около 586 КБ и защищён Luraph v15. Реальная логика скрыта виртуальной машиной; файл не запускался и не копировался в MilfaCheatHUB.

## Текущая сборка 0.1.0

Готово:

- [x] модульная RAW-загрузка;
- [x] loading screen с прогрессом;
- [x] загрузка общей `icon.png` с fallback;
- [x] фирменный GUI MilfaCheatHUB;
- [x] вкладки «Яйца», «ESP», «Точки», «Система»;
- [x] динамический сканер яиц;
- [x] определение участка и биомов;
- [x] диагностика Networking;
- [x] Egg ESP;
- [x] лёгкий FPS-режим с восстановлением настроек;
- [x] повторный запуск с очисткой старой сессии;
- [x] клавиша `RightControl` для скрытия окна.

Следующий этап после проверки сборки в игре:

- [ ] исправить реальные различия структуры `EggState`/`EggCmds`, если они появятся;
- [ ] добавить список яиц в GUI с фильтрами;
- [ ] добавить просмотр питомцев, базы и дорожки;
- [ ] проверить ответы подтверждённых RemoteFunction обычными действиями;
- [ ] добавлять активные функции только после проверки аргументов и состояния сервера;
- [ ] дополнить GUI мобильной кнопкой открытия.

## Запуск

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ffffddggt277-debug/MilfaCheatHUB/main/Steal-A-Egg/main.lua"))()
```

## Журнал

### 2026-09-17

- `LIST.md` перенесён в корень репозитория.
- Создана первая модульная сборка Steal An Egg.
- Добавлены config, UI, scanner, network, positions, ESP и feature controller.
- Добавлен loading screen с общей иконкой MilfaCheatHUB.
- Добавлена готовая RAW-команда запуска.

### 2026-09-16

- Создан репозиторий, README, иконка и папка Steal An Egg.
- Исследованы механики игры, Remotes и динамические точки.
