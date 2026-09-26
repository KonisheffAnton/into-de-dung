# Передача — 2026-09-26: исполнение вне render

Ветка main; base `89b1225bbbe830173fef0db1347c5dfdbdf08e59`, чистый старт.
Прежняя передача — точный [архив](CODEX_HANDOFF.history-20260926-6.md).
Цель — плавный общий бой, крупные пакеты и один общий плейтест.

Основной BattleCoreReactionsSession передаётся BattleExecutionWorker целиком;
UI лишается доступа к session до join и держит value projection доски/бойцов.
Все действия и ходы исполняют прежние команды/guards.
Callback/custom runtime -> sync fallback; reset/смена/exit сначала join.
D4/инициатива/прямой session API синхронны. Владение и ограничения —
[BATTLE_EXECUTION_UI](BATTLE_EXECUTION_UI.md), устройство — ARCHITECTURE.
Preview остаётся реальным исполнением в изоляции; кэша мира по revision нет.

Godot 4.7.2: полная матрица 72 PASS, включая core 9440/0 и 22 render runner;
worker 117/0, новый UI 20/0 headless и 22/0 render, два PNG осмотрены.
Матрица составная: после исправления test-wait D4/null и ожидания live job
в action async fixture продолжены оставшиеся проверки; production не менялся.
Core diagnostics совпали с baseline, новых нет. Независимое APPROVE и аудит ведущего.
A/B, 8 окон/версия: медианный пик кадра движения 52→28 мс, удара 76→26,
конца хода 49→27, тяжёлого шага ИИ 81→26; fingerprint/RNG/counters равны.
Один сценарий, не FPS/гарантия. Полная плавность НЕ принята; один общий
ручной плейтест подготовлен, результат пользователя ещё нужен.

Отчёт/матрица/A/B: `test_reports/execution-smoothness-20260926/report.md`,
`validation.json`, `benchmark-final/`; итоговый snapshot — `validation-final/project`.
SHA/status и интерактивный запуск — completion/финал. Без push и чужих изменений.

C1/общий K8–K11 открыт, D3/D4/D5 частичны; K3 «Пока ок», K5–K7 приняты.
Остаток — CORE_READINESS, маршруты PROJECT_CONTEXT. U14 согласована, карта
не реализована, D4 линейный. Backlog не запускать. Сохранять командный бой,
D5/M1/M3, 1 main, остатки/RNG/ID, preview/live/FAULTED, формулы/цены/Q1–Q6/frozen.
Падение/инициатива отложены; P не равны U. Без push/sidebar tasks/расписаний.
Следующий шаг — единый плейтест; далее только подтверждённые проблемы плавности.

В конце этапа/при блокере обновить HANDOFF; прежний сохранить точно отдельным
архивом со ссылкой из HISTORY по CODEX_WORKFLOW. Предложить новый чат при
необходимости и прямо в финале дать полный самодостаточный промпт: HEAD,
результат, docs/artifacts, остаток, ограничения, проверки и это же правило.
Ссылка не заменяет текст; правило переносить дальше.
