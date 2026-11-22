# Передача — 2026-11-22: запись С2 на поле

D:/Games/into-de-dung; main, база3dde79de646d5aa45c6f71609e3577a3d174bf61.
По U записана настоящая смерть троглодита на тестовой доске:
DeathCommand → receipt → BattlePresentationPlayer → fresh corpse.
[GIF/WebP/кадры/проверки](art/troglodyte-c2-live-20261122/README.md),
скрипт tools/demo/capture_troglodyte_death.gd. Gameplay/арт не менялись.
Все33 кадра С2 проверены по texture identity,0–32. Тень остаётся на опоре
во время падения; после clip фигура/полосы/тень скрываются, остаётся
штатная отметка свежего трупа. HP24 во время transient clip — before-state;
в окончательном состоянии HP0. Постоянного лежащего спрайта пока нет.

Чистый committed runtime из git archive + capture script, отдельный APPDATA:
Godot import/GPU capture PASS,38PNG/33death/0 ошибок. State/RNG/counters/
revision неизменны при playback. GIF/WebP960×640,5.36с; WebP lossless.
Технические transition-публикации исключены из экспорта, клип С2 целиком.
Независимое ревью скрипта/GPU APPROVE,35 lossless-кадров WebP сверены с PNG.
Full/core, ручной бой и DPI/performance не повторены. Приёмка U открыта.
[Контракт](TAMED_TROGLODYTE_V1.md), [исправление посадки/С2](art/troglodyte-grounding-c2-20261122/README.md).
Следующий шаг — оценить падение/контакт и при необходимости уточнить финальный труп.

Сохранять отсутствие инициативы, core/queue/preview/RNG/save/frozen,
бронирование у фигуры,5 классов, PLAYER вправо/ENEMY влево, пробу2:1/4:3.
Параллельный host/possession пакет, main_menu и battlefield-reference03
не включены: полный status перед работой, чужое не reset/stage/commit.
Владельцы параллельной работы — DESIGN_DIRECTION§3.2.1/HOST_POSSESSION_V1.
Без push/sidebar/расписаний. Один isolated runner, без root import.
Остатки D:/Games/trog-grounding-check-20261122 не удалять повторно:
предыдущий cleanup отклонён автопроверкой; отчёты сохранены.

[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261122-8.md) + HISTORY.
После этапа/при блокере предложить новый чат и полный промпт: HEAD, результат,
docs/artifacts, остаток, ограничения, проверки и это же правило передачи.
Прежний HANDOFF архивировать побайтно отдельно со ссылкой из HISTORY;
чат автоматически не создавать.
