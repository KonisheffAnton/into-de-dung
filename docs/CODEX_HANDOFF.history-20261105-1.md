# Передача — 2026-11-05: жидкости, кальтропы и пробы огня

D:/Games/into-de-dung; main; base84957c6bbf4358b21cf521fbcd5eca80c350252d.
Внедрены acidfilm-05 «Рассеянная рябь» (прозрачная плёнка) и caltrops03-01
«Редкие блики». По33 кадра10FPS; кальтропы сохраняют камень внутри верхнего ромба.
Прежняя кислота05/01 теперь утопленная глубокая кислота D7, мелкая — C7.
DEEP_ACID=4 дописан: вход/толчок смертелен без нового тела; BT выбирает обход/ждёт.
Только кислота, без глубокой воды. Каталоги/профиль не мигрируют.
Правила: ENVIRONMENT_HAZARDS_V1, BATTLE_SNAPSHOT_CURRENT;
показ: BATTLE_VISUAL_SCENE_CONTRACT; выбор: ART_DIRECTION.
[Снимки/интеграция](art/liquid-hazards-integration-20261105/README.md).

Получены [12 проб огня PixelLab](art/fire-subtle-animation-20261105/README.md):
по3 fire22/23/24/29,396 исходных кадров,60 генераций. Требуется постоянное
горение с лёгким колыханием, без вспышек/затухания/высоких языков.
0/12 соответствуют; fire24-03 кадр6 касается края. В игру огонь не подключён.
Галерея/байты PASS; art не принят.

PASS import/startup; hazards165/0, move_forecast547/0, push_chain636/0,
core9424/0, core_reactions419/0; GPU acid217/0, environment32/0, visual106/0,
presentation_environment364/0, dungeon1983/0; runtime review APPROVE.
hazards_ui91/2 — те же два сбоя на base84957c6b. Full не запускался.
Отчёты: test_reports/liquid-hazards-20261105/, fire-subtle-animation-20261105/.
docs/.gdignore исключает арт-архивы; root import не выполнялся.
Прежние проверки/APPROVE не считать повторёнными. Ручные F5/движение/zoom/DPI,
стыки/посадка/качество/performance, край стрелы способности4 Лучницы,
presentation_foundation141/2, turn_forecast_ui26/3, HUD/Колода остаются.
Дальше — отзыв/поручение U; новые генерации/срезы не начинать.

33 чужих файла scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не reset/stage/commit.
Сохранять core/preview/queue/RNG/save/frozen, пять классов F5, PLAYER вправо/
ENEMY влево и возврат после атаки; каталоги1–3 не мигрировать. Один Godot runner,
isolated project; без root import, служб/драйверов, принудительного фокуса,
push/sidebar tasks/расписаний. [Архив побайтно](CODEX_HANDOFF.history-20261105.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF,
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения, проверки
и это же правило. Чат автоматически не создавать.
