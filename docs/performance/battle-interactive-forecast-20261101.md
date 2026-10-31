# Интерактивный прогноз и наведение — 2026-11-01

База `f80bde6c5224e53d89470b665b3c9684dc49b83f`, main. Пользователь уточнил:
размер окна isolate тот же, рывки сильнее при движении мыши. Предыдущий автономный
soak блокировал GUI-ввод. Его ETL не объяснял этот интерактивный путь; история
и выводы по display остаются в [предыдущем отчёте](battle-graphics-trace-20261101.md).
Стабильные 60 FPS пока не подтверждены.

## Найденный расход и изменение

На production HeroHubBattleView с 32 бойцами prepare прогноза выполнял полный
ItemSimulationSnapshot capture, проверки и копирование на main. Headless замер
десяти переходов мыши дал медиану 90,927 мс, максимум 99,428 мс для запуска move
прогноза; одиночный attack prepare — 89,990 мс. Restore/симуляция уже были фоновыми.
Отдельные компонентные измерения подтвердили расход capture; они перекрываются,
поэтому их нельзя суммировать.

Теперь полный prepare выполняет BattleForecastPreparationWorker после порционного
TransferAudit и передачи исключительного владения session. UI временно читает
опубликованную проекцию. После join session возвращается, отделённый Prepared
идёт прежнему worker симуляции. Полные проверки, изоляция, RNG, очередь, результат
команды и синхронный fallback сохранены. Правила отмены, semantic input buffer,
панели чтения и reset — [ATTACK_FORECAST](../ATTACK_FORECAST.md#ui-и-приёмка),
владение — [BATTLE_EXECUTION_UI](../BATTLE_EXECUTION_UI.md).

Board также получает unit и cell за один обход показанной геометрии на mouse motion
и при клике во время подготовки. Верхний рельеф закрывает нижнюю фигуру как раньше;
межкадрового кэша геометрии нет. Во время live-исполнения осмотр не ищет клетки пола.

## Повторяемый диагностический замер

Локальный пакет: `test_reports/battle-frame-pacing-20261031/` (далее R).
Исходная фикстура: `tests/test_battle_soak_performance.gd`, production factory,
32 бойца, карта 24×16, seed9404, 10 move hover и 1 валидный attack hover.
В probe автоматический `_process` остановлен: измеряются реальные
`Board._gui_input(MouseMotion)`, start, порции подготовки и take/publish отдельно.
Ожидание worker не прибавляется к main-cost. State/RNG/counters/revision проверяются
до и после; команды live не исполняются. Это не замер всех кадров длительного боя.

| Участок, мс | До, headless | После, headless | После, D3D12 окно |
|---|---:|---:|---:|
| Move GUI hover, медиана / max | 14,127 / 17,156 | 6,242 / 7,156 | 7,796 / 15,766 |
| Move start, медиана / max | 90,927 / 99,428 | 0,030 / 0,034 | 0,044 / 0,071 |
| Move main poll подготовки, max | — | 5,116 | 9,537 |
| Move take/publish, медиана / max | 4,063 / 4,990 | 3,196 / 3,617 | 4,088 / 6,172 |
| Attack start, один запрос | 89,990 | 0,039 | 0,053 |

Godot4.7.2 `ed1daf0bf001b61586d9930840f2f1394092c079`, Windows,
Mobile/D3D12, RTX3050Laptop; окно1280×850 на screen1/60Гц, VSync1/max_fps0.
В финальном metadata окно имело фокус; непрерывное покрытие фокуса этот probe
не записывает. Приёмка FPS или ручное наблюдение плавности из этого не следуют.
Малый набор запросов и меняющаяся нагрузка машины не дают аппаратной гарантии
по максимумам. В GUI отдельный hover уже достигает 15,766 мс до прочей работы кадра.

Артефакты и воспроизведение:

- До: `R/probe_interactive_forecast_perf.gd`, `interactive-forecast-probe.json/log`
  (47PASS/0, включая компонентные проверки). В старом JSON limits есть ошибочное
  описание direct `_hover`; исходник действительно вызывает `Board._gui_input`.
- После: `R/probe_interactive_forecast_after.gd`, `interactive-forecast-after.json/log`,
  `interactive-forecast-after-render.json/log` (по19PASS/0; компонентные замеры убраны).
  Промежуточный замер только переноса prepare: `interactive-forecast-after-prep-only.json`.
- Source и JSON SHA256, проверки и границы: `R/interactive-forecast-validation.json`;
  критическое независимое ревью: `R/interactive-forecast-review.md`.
- `R/run_forecast_integration.py` копирует выбранные текущие файлы в существующий
  изолированный mirror, использует отдельный APPDATA и записывает логи.
  `make_interactive_after_probe.py` создаёт after-probe из сохранённой baseline.
  Для переноса на другую машину нужны исходники проекта и эти локальные файлы;
  ссылки на R не означают, что игнорируемые артефакты находятся в Git.

## Проверки и ограничения

Изолированный Godot import/parse; focused результаты:

| Проверка | PASS / FAIL |
|---|---:|
| forecast preparation worker / UI | 33/0; 61/0 |
| pointer pick | 13/0 |
| attack async UI / move UI / action async UI | 110/0; 75/0; 13/0 |
| execution worker / UI | 313/0; 59/0 |
| attack worker / action worker | 47/0; 58/0 |
| camera UI / current art zoom | 104/0; 484/0 |
| turn forecast UI | 26/3 — прежние ошибки transition/AI/phase |
| Python isolate mocks | 30/0 |

Legacy fixtures явно возвращают владельца перед прямыми мутациями, затем
проверяют прежний detached-worker. Новая UI проверка отдельно покрывает ввод
во время lease, latest target, переход в панель и уход, клик после pan, очередь
ввода, отказ рестарта H1, настоящий reset основного BattleDemo и exit/join.
Независимый reviewer выявил потерю pending при переходе в панель; исправление
проверено для move/attack по синхронному oracle, включая точный REJECTED.
Итог ревью — APPROVE_WITH_LIMITATIONS, без заявления GPU/FPS приёмки.

Остаток:

- `_mage_card_cache` и `_elemental_cast_cache` всё ещё синхронно снимают полный
  снимок для строгой свежести. Эта работа не удалена и не заменена одной revision;
  следующий замер должен покрыть hover карт/магии и неподвижный готовый прогноз.
- Нужен длительный интерактивный бой32 с движением мыши, эффектами и покадровой
  трассой. Самостоятельный GUI probe выше не заменяет такого боя и обычный isolate.
- Ранее измеренные display-пики 20–24мс остаются отдельным неразрешённым вопросом.
  Новых ETL, повышенных прав, изменений ОС/драйвера/рендера не было.
- Full/core, ручной F5/движение/zoom/DPI и другой GPU заново не проверялись.
  Прежние HUD/lifecycle/цвета/Колода/арт-приёмка остаются открытыми.

33 чужих файла сверены по прежнему hash-manifest без изменений. Входные документы
AGENTS/PROJECT_CONTEXT/CODEX_WORKFLOW не меняются; HANDOFF заменён кратким, прежний
сохранён побайтно отдельным архивом. Размеры и проверка ссылок — в validation JSON.
