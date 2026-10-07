# Передача — 2026-10-07: адресное улучшение плавности

Main; base b13e41059555bec20772b74a60f5b12a7ec36422; без push.
Аудит карт разделён внутри refresh; межкадрового кэша нет.
Шаблон строки HUD удерживается как PackedScene. Технические after показа
уступают рендеру по одному за проход; порядок/skip/cancel сохранены.
Контракты: MAGE_DECK_V1, BATTLE_PRESENTATION_V1, BATTLE_HUD_SCENES_V1.

Production catalog2/deck A/B, _process включён, два render:
hover p95 27–28→20.2ms, >25ms 29–36/180→0/180;
AI max312–356→53–66ms, >50ms 14–15→2–3 за весь ход.
Компромисс: >25ms 25→41–56, показ хода +0.7–0.8s; shield max68–74ms.
Полная плавность НЕ закрыта. Все before/after/events/steps/RNG/counters
и публикации A/B совпали. Capture остаётся~11.7ms; GPU отдельно не измерен.
Далее: пользовательский F5 по темпу; при доработке адресно измерять
show_presentation_state/_rebuild_visuals/completion и освобождение узлов.
Не расширять механики и не вводить revision-only кэш.

test_reports/battle-smoothness-fix-20261007/: report.md,
summary/manifests, probe/AB логи, review, completion/next-chat-prompt.
Runner tools/demo/profile_production_smoothness.gd — изолированный fixture,
не полный F5/редактор. Import/startup, адресные headless и20 render suites PASS;
Ревью APPROVE. Ошибки/повторы — отчёт/HISTORY.
Full/core не повторялись. Исторически full137PASS/2FAIL (control_ui/entangle_ui
на base), core9440/0 с47ObjectDB/18resources; это не новые проверки.
Вне коммита только пользовательская main_menu.tscn; не сбрасывать.

Щитоносец принят (SHIELDBEARER_V1). F5/колода/спрайты предварительно приняты;
полный маршрут/редактор, HUD, финальный арт/баланс, Q-E/артефакты открыты.
Общий набор/отход/исключения/автостойка — Q DESIGN_DIRECTION §3.1.
Сохранять покомандность/preview/live/queue/RNG/save/frozen и profile1–4.
Не начинать школы/кузню/R16/R17/экипировку13/стаки/backlog, микроплейтесты
ядра, покрытия/реакции, D4-save миграцию, финальный арт. Инициатива вне
full/render; viewport baseline открыт; --screen0; DPAPI вне Git/логов/промптов.
PROJECT_CONTEXT — маршруты, CODEX_WORKFLOW — процесс, DESIGN_DIRECTION §7 — порядок.

Проверенный этап: Conventional Commit; прежний HANDOFF точным архивом
CODEX_HANDOFF.history-20261007-8.md со ссылкой HISTORY. Без push/sidebar/расписаний.
В конце/при блокере предложить новый чат (кроме явного продолжения здесь)
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это правило передачи. Ссылка не заменяет текст; чат не создавать.
