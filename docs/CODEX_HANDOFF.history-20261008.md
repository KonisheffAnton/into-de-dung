# Передача — 2026-10-07: переиспользование узлов боя

Main; base dfd08f619b59294fc6a80614ff0685598744b4b5; без push.
Поле сохраняет штатные опоры/стены, HUD — строки по ID в сессии/оболочке.
Свежие значения; custom scenes/бойцы/накладки прежние.
Нет revision-only кэша; порядок after, worker ownership и правила не менялись.
Контракты: ARCHITECTURE, BATTLE_HUD_SCENES_V1, BATTLE_PRESENTATION_V1.

Два production catalog2/deck A/B с _process: за весь AI >25ms44–56→24–25,
>50ms2–3→0, max~55→34–43ms, время8.50–8.56→8.04–8.09s;
shield max71–72→46ms. Hover p95~20.6ms: улучшения в этом срезе нет.
CPU поле median6.07→2.64ms, HUD1.06→0.21ms; визуальных корней5751→486,
новых строк486→0 за AI. Capture~11.6ms не оптимизирован; GPU отдельно не измерен.
Все before/after/events/steps/RNG/counters/admission/publications совпали.
Плавность не принята. Далее F5; технический остаток —
адресно prepare/capture/worker preflight, без расширения механик.

test_reports/battle-view-reuse-20261007/: report.md, summary/manifests,
probe/AB логи, review, verification/completion/next-chat-prompt.
Runner tools/demo/profile_production_smoothness.gd — fixture, не F5/редактор.
Import/startup, headless reuse26/0, HUD230/0, environment312/0,
21 адресный render suite PASS; Python5/0; независимое ревью APPROVE.
Full/core не повторялись: исторически full137PASS/2FAIL control_ui/entangle_ui
(оба на base), core9440/0 с47ObjectDB/18resources; это не новые PASS.
Вне коммита только пользовательская main_menu.tscn; не сбрасывать.

Щитоносец принят (SHIELDBEARER_V1); F5/колода/спрайты предварительно приняты.
Полный маршрут/редактор, HUD, финальный арт/баланс, Q-E/артефакты открыты.
Общий набор/отход/исключения/автостойка — Q DESIGN_DIRECTION §3.1.
Сохранять покомандность/preview/live/queue/RNG/save/frozen и profile1–4.
Не начинать школы/кузню/R16/R17/экипировку13/стаки/backlog, микроплейтесты
ядра, покрытия/реакции, D4-save миграцию, финальный арт. Инициатива вне
full/render; viewport baseline открыт; --screen0; DPAPI вне Git/логов/промптов.
PROJECT_CONTEXT — маршруты, CODEX_WORKFLOW — процесс, DESIGN_DIRECTION §7 — порядок.

Проверенный этап: Conventional Commit; прежний HANDOFF точным архивом
CODEX_HANDOFF.history-20261007-9.md со ссылкой HISTORY. Без push/sidebar/расписаний.
В конце/при блокере предложить новый чат (кроме явного продолжения здесь)
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это правило передачи. Ссылка не заменяет текст; чат не создавать.
