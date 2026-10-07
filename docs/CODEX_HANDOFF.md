# Передача — 2026-10-08: live_valid колоды

Main; base f4fa5180fe7720cc67c63d0e43e9cd80f25f8b9e; без push.
По «Давай» UnitState получил общий проверяющий producer полного/короткого DTO.
MageDeckRules.live_valid берёт id/faction/vitals.is_alive без полного Unit DTO.
Проверки компонентов/HP_MAX/ссылок, raw-форматы и диагностика сохранены.
180 опросов/180 idle кадров прежние; кэша/смены правил/queue/save/RNG нет.
Владение — ARCHITECTURE; UI — BATTLE_EXECUTION_UI; проверки — TESTING.

Два probe: idle live_valid median2.05–2.17→1.54–1.69ms, выигрыш0.48–0.51ms.
Три A/B: hover p95 20.58–20.67→19.68–20.08ms; AI total меньше,
но AI p95/пики не улучшились устойчиво. Общая плавность не доказана.
Полная parity всех6 controls/4 probes сохранена. Вложенные времена не складывать.
Fixture не F5/редактор; GPU не измерен. Ручная оценка capture/live_valid открыта;
прежний worker-аудит предварительно ок. Далее оценка при обычном прохождении;
следующие оптимизации только отдельным поручением, новых механик не начинать.

Артефакты: test_reports/deck-live-valid-20261008/report.md, base/current,
ab-summary, review/verification/completion. Runner: profile_snapshot_preflight.py.
Import/startup PASS; producer809/0, live snapshot41/0, render deck UI110/0/PNG;
независимое APPROVE. Full138PASS/2FAIL из140; control25/1 и entangle21/1 повторены на base.
Не общий PASS. Core9440/0, прежние47ObjectDB/18resources.
Пользовательская main_menu.tscn вне коммита; не сбрасывать.

Щитоносец и прошлый срез поля/HUD приняты; F5/колода/спрайты предварительно.
Полный маршрут/редактор, HUD, финальный арт/баланс, Q-E/артефакты открыты.
Общий набор/отход/исключения/автостойка — Q DESIGN_DIRECTION §3.1.
Сохранять покомандность/preview/live/queue/RNG/save/frozen, profile1–4.
Не начинать школы/кузню/R16/R17/экипировку13/стаки/backlog, микроплейтесты
ядра, покрытия/реакции, revision-only кэш, D4-save миграцию, финальный арт.
Инициатива вне full/render; viewport baseline открыт; --screen0;
DPAPI вне Git/логов/промптов. PROJECT_CONTEXT — маршруты,
CODEX_WORKFLOW — процесс, DESIGN_DIRECTION §7 — порядок.

Этап: Conventional Commit; прежний HANDOFF точным архивом
CODEX_HANDOFF.history-20261008-3.md со ссылкой HISTORY. Без push/sidebar/расписаний.
В конце/при блокере предложить новый чат (кроме явного продолжения здесь)
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это правило передачи. Ссылка не заменяет текст; чат не создавать.
