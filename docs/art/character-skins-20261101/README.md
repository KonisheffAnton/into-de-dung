# Облики и показ всех классов — 2026-11-01

Ветка main, база `f768d779af6991fb3b76bbcb2a85a78837b5e69a`.
Внедрены выбранные02/17 для Щитоносца и11 для Воина. Источник кадров сохранён
побайтно; новый арт не генерировался. Точное поведение принадлежит
[CHARACTER_SKINS_V1](../../CHARACTER_SKINS_V1.md) и
[CLASS_SHOWCASE_V1](../../CLASS_SHOWCASE_V1.md).

В новом профиле каталога4 игрок получает Разбойника, Мага и Воина; отсутствующие
классы представлены врагами. Старые профили1–3 сохраняют состав. Переключатель
«Облик» находится в хабе на странице наёмников; выбор общий для класса и обеих
сторон. Клип способности связан с «Поднять щиты» / Рассекающим ударом.

## Проверки

Один Godot4.7.2 runner, изолированная копия проекта и APPDATA; root import не
выполнялся. Первичная копия: `test_reports/demo-08aa4c6f896d4468824b98067227ef35/`.
Последующие запуски использовали её import cache с побайтной синхронизацией
scripts/scenes/assets/tests и SHA-256-манифестом каждого запуска. Скрипт,
логи, manifests, validation и ревью: `test_reports/character-skins-20261101/`.

| Проверка | Результат |
|---|---|
| Import/parse, startup | PASS |
| class_showcase: каталоги, RNG, состав, actual BT/commands, checkpoint | 223/0 |
| character_skins: runtime, реальные receipts, lifecycle | headless208/0; GPU234/0 |
| character_skins_hub: выбор, запись/backup/отказ, портреты, передача в бой | headless23/0; GPU24/0 |
| shieldbearer_ui: настоящий hover/worker/click/playback | headless24/0; GPU24/0 |
| hero_hub / hub_mercenaries | 98/0;207/0 |
| mage_deck_expedition / expedition_generator | 507/0;1055/0 |
| defender_death_routes / presentation_contact | 877/0;292/0 |
| unit_visual_contract / visual_scene_contract | 45/0;106/0 |
| warrior_class / warrior_visuals / shieldbearer_palette | 67/0;36/0;9/0 |
| Core | 9424/0; единственный ожидаемый occupied-cell ERROR разрешён launcher |
| Python isolate mocks / asset builder --check | 30/0;23 выхода,13 PNG,330 кадров |
| Независимое ревью ассетов, UI/settings, runtime/AI и тестов | APPROVE |

`turn_forecast_ui` остаётся26/3 (transition/AI/phase), как в
[отчёте исходной версии](../../performance/battle-interactive-forecast-20261101.md).
Это не зелёный full suite. Первые ошибки новых тестовых fixtures исправлены:
типизированные статусы, ожидание idle вместо still, HP-gate контроля, флаг жизни,
удаление visual после смерти. Все прогоны, включая неудачные, сохранены.

Ревью выявило неиспользованные персональные атаки врагов; BT теперь выбирает
существующие команды класса и обычную атаку при недоступности умения. Отдельного
RNG в выборе BT нет. Core-команды, preview и очередь не изменены. Повтор каталога4
с тем же checkpoint воспроизводит snapshot/RNG; выбор скина не меняет профиль7.

Полный lethal playback проверен на ENEMY для всех трёх skins, на PLAYER —
кадры/отражение/pose; общая смерть PLAYER покрыта смежным маршрутом. Shield и
Cleave проходят настоящее нормальное завершение, skip/cancel; обычная атака и
Пинок сохраняют прежний маршрут. GPU проверяет видимые кадры, а не только DTO.

## Снимки и границы приёмки

- [Выбор в настоящем хабе](hub-skin-choice.png).
- [Кадры трёх обликов, обе стороны / способность / смерть](selected-skins-gpu.png).
- [Все пять классов, приближение100%](battle-all-five-classes-100.png).
- [Исходный обзор комнаты](battle-all-five-classes.png).

Приближение — только диагностическая камера снимка; стартовая камера и геометрия
не менялись. Маг использует прежний условный рисунок. Швы выбранных PixelLab
idle/ability не ретушировались. Ручные F5, движение/zoom/DPI, художественная
приёмка и full suite открыты. Стабильные60 FPS не измерялись и не заявлены;
остаток предыдущей работы — [performance](../../performance/battle-magic-pacing-20261101.md).

## Передача и сохранность

Чужие main_menu.tscn и battlefield-reference-03:33 SHA-256 сверены; staging их
не включает. Предыдущий HANDOFF сохраняется побайтно отдельным архивом+HISTORY.
Размеры входных документов (символы LF): AGENTS4565 и WORKFLOW4482 без изменений;
PROJECT_CONTEXT3585→3652. Превышение ориентира3500 оставлено ради двух новых
маршрутов к владельцам поведения: уникальные прежние маршруты не удалялись.
HANDOFF ограничен2500; архив не считается ростом текущего входного документа.
Следующий шаг — отзыв пользователя; следующий срез автоматически не начинать.
