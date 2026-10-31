# Передача — 2026-11-01: интерактивный прогноз

D:/Games/into-de-dung; main; base f80bde6c5224e53d89470b665b3c9684dc49b83f.
Цель — убрать фризы с24+ бойцами. Стабильные60 FPS НЕ подтверждены.
[Измерения/остаток](performance/battle-interactive-forecast-20261101.md).

Пользователь: тот же размер окна, isolate хуже при движении мыши.
Найден prepare прогноза32 на main ~91мс. BattleForecastPreparationWorker
переносит полный prepare в фон с исключительным владением session;
после join — прежний detached-worker. UI хранит смысл кликов/ID/клетки
и последнее наведение. Board получает unit/cell одним обходом.
Контракты: ATTACK_FORECAST/BATTLE_EXECUTION_UI. Core/preview/queue/RNG/save/frozen сохранены.

Headless32: move start медиана0,030мс; hover6,242мс вместо14,127.
GUI D3D12/RTX3050/screen1: start0,044мс; hover7,796/max15,766мс;
main preparation poll max9,537мс. Это обработчики, НЕ full-frame FPS.
After-probe по19PASS/0, live state/RNG/counters/revision неизменны.
Изолированный import/parse, focused worker/UI/picking/камера/масштаб PASS;
Python isolate30/0. Turn UI26/3 — прежние ошибки. Критическое независимое
APPROVE_WITH_LIMITATIONS. Переход pending в панель исправлен; новый UI61/0.
Точный состав проверок — отчёт. Артефакты: test_reports/battle-frame-pacing-20261031/
interactive-forecast-* (source, JSON/log, validation.json/review.md).

Следующее: измерить синхронные _mage_card_cache/_elemental_cast_cache
(полные снимки для строгой свежести), затем длительный интерактивный бой32
с мышью/эффектами и обычный isolate. Display-пики20–24мс не закрыты;
ETL/границы — performance/battle-graphics-trace-20261101.md.
Новых full/core/F5/ручных движение/zoom/DPI/другой GPU проверок нет.
Прежние HUD/lifecycle/цвета/Колода/арт-приёмка открыты.

Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не reset/stage/commit;33 файла сверены. Один GPU runner, isolated project,
без root import/автоповышения/изменения служб и драйверов.
Без push/sidebar tasks/расписаний/нового арта/генерации/интеграции.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261101-2.md), [HISTORY](HISTORY.md).

Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельным архивом+HISTORY. В финале/при блокере предложить
новый чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts,
остаток, ограничения, проверки и это же правило. Чат автоматически не создавать.
