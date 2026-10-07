# Передача — 2026-10-07: приёмка Щитоносца, плавность боя

Main; base 8ad3ef8c62cde7630c740c2787db48f9c2811188; без push.
Пользователь: «По приемке ок» — Щитоносец принят (SHIELDBEARER_V1).
Отдельная жалоба: «в бою в целом все ощущается немного рвано».
Runtime не менялся. Новые механизмы не начинать.

Изолированный production HeroHubBattleView/catalog2/deck: import и два render
запуска завершились без ошибок, --screen 0. Обычный _process включён.
Idle p95~17ms; hover p95~27.3ms, 34/180 и29/180 кадров >25ms.
Live shield max98.5ms, end-turn/AI окно max304.5ms (второй запуск).
Причина/регрессия ещё не установлены; полный F5/редактор не измерен.
Capture cost отдельно не измерен. Старый profile_smoothness отключает _process.
Отчёт/runner/manifest/логи: test_reports/battle-smoothness-20261007/.
Следующее рекомендуемое: ограниченный срез плавности — измерить prepare/capture,
apply/refresh/presentation; затем адресное исправление и сравнение/parity.

Исторические проверки Щитоносца: import/адресные/core9440/0 PASS, ревью APPROVE.
Full137PASS/2FAIL: control_ui25/1, entangle_ui21/1 (оба повторены на base).
Core прежние47ObjectDB/18resources; затронутый render PASS, UI22/0(render),20/0.
Артефакты: test_reports/shieldbearer-v1-20261007/. Full/core здесь не повторялись.
Пользовательские UID/unique_id/offsets main_menu.tscn вне коммита; не сбрасывать.
Прежний HANDOFF — CODEX_HANDOFF.history-20261007-7.md, ссылка HISTORY.

Общий случайный набор/отход/исключения/автостойка — Q в DESIGN_DIRECTION §3.1.
F5/колода/спрайты ранее приняты предварительно; изометрия желательна позже.
Полный маршрут/редактор, HUD, финальный арт/баланс, Q-E/артефакты открыты.
Сохранять покомандность/preview/live/queue/RNG/save/frozen; старые profile1–4.
Не начинать школы/кузню/R16/R17/экипировку13/стаки/backlog, микроплейтесты ядра,
новые покрытия/реакции, revision-only кэш, D4-save миграцию, финальный арт.
Без push/sidebar/расписаний. Проверки по TESTING; инициатива вне full/render;
viewport baseline открыт. Графика — GRAPHICS_WORKFLOW; DPAPI вне Git/логов.
PROJECT_CONTEXT — маршруты, CODEX_WORKFLOW — процесс, DESIGN_DIRECTION §7 — порядок.

Проверенный этап — Conventional Commit, короткий HANDOFF; прежний точным
архивом со ссылкой HISTORY. В конце/при блокере предложить новый чат, кроме
явного продолжения здесь. Финал: полный промпт с HEAD, результатом, docs/artifacts,
остатком, ограничениями, проверками и этим правилом. Ссылка не заменяет текст.
Чат автоматически не создавать.
