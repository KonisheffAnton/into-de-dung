# Передача — 2026-09-24: задержка hover K4

Ветка main; base `8667b81e38d666519a5fbd020a497ac7ae198190`, чистый старт.
Прежняя передача — точный [архив](CODEX_HANDOFF.history-20260924-12.md).
Свидетельства — [HISTORY](HISTORY.md), `test_reports/k4-hover-perf-20260924/`.

После жалобы на задержку hover движение ждёт 60 мс стабильной цели и считает
на отдельном worker. Main готовит изолированный Prepared; stale поколения
отбрасываются, клик исполняет свежую команду, shutdown присоединяет worker.
Hover обновляет прежние визуалы без rebuild доски. API атаки/M3 сохранены.
Контракт — [ATTACK_FORECAST §K4](ATTACK_FORECAST.md#k4--прогноз-движения),
границы — [CORE_READINESS §K4](CORE_READINESS.md#k4--прогноз-движения), архитектура —
[ARCHITECTURE](ARCHITECTURE.md). Input callback был ~107 мс, стал ~1 мс;
capture остаётся ~17 мс на main. Это замеры, не приёмка плавности/60 FPS.

Godot 4.7.2 import/startup/full/render PASS: core 9440/0, K4 520/0,
AttackForecast 166/0, UI headless 65/0 и render 69/0. Четыре PNG осмотрены.
Проверены worker/sync/live parity, snapshot/RNG/counters/admission/ID, изоляция,
INTERRUPTED/FAULTED prefix, stale при hover/refresh/click/reset/mode/phase/scenario,
выход и shutdown. Legacy diagnostics прежние; новых ошибок/leaks нет.
Независимое ревью APPROVE; границу main/worker проверил ведущий.
После commit ожидается чистое дерево; push не выполнялся.

K4 ждёт повторного плейтеста после перезапуска. K3 получил только «Пока ок».
Ядро не завершено; ручной повтор UI K2 не заявлен. K2 без M4/D4; D3/D4/D5
частичны, C1 открыт. M4 удар/прогноз и прокрутка приняты. Общего runtime статусов/
прогноза всех действий нет. Поднятие D5/цепочки и новое падение вне K4.
Покрытие ввода ограничено сценариями runner, не всеми переходами приложения.
Бой командный, инициатива отложена. Сохранять D5/M1/M3, 1 main за атаку,
остатки/RNG/ID/preview/live/FAULTED prefix, формулы/округления/цены и Q1–Q6/frozen.
Ждать плейтеста или поручения; новый механизм не начинать.
Без push/sidebar tasks/расписаний.

В конце этапа/при блокере обновить короткий HANDOFF, прежний сохранить точным
отдельным архивом со ссылкой из HISTORY. Предложить новый чат и прямо в финале
дать полный самодостаточный промпт блоком кода: HEAD, результат, docs/artifacts,
остаток, ограничения, проверки и это же правило. Ссылка не заменяет текст;
перенести правило в передачу. Процедура — [CODEX_WORKFLOW](CODEX_WORKFLOW.md).
