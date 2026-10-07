# Передача — 2026-10-08: один аудит worker

Main; base 7d7777273d66e49e5b518afbe9ed43b910c6dc13; без push.
Пользователь принял прошлый срез поля/HUD и поручил продолжить оптимизацию.
Start объединяет свежий аудит графа, before/capture и запуск потока;
UI получает только DTO. Sync-only/отказ запуска сохраняют прежний показ.
Контракты: ARCHITECTURE/BATTLE_EXECUTION_UI; команды замера — TESTING.
Нет кэша допуска, изменений правил/queue/snapshot codecs.

Production catalog2/deck, два control A/B: AI8.03→7.95–7.98s,
p95 24.0–24.6→21.6–23.0ms, >25ms21→19–20, max33.9–38.1→32.8–33.0ms.
Отдельный probe:8 аудитов вместо16, CPU сумма137→74ms за8 запусков.
Все6 before/after/events/steps/RNG/counters/admission/publications совпали.
Новый срез технически проверен, пользовательская оценка ещё не получена.
Fixture не заменяет F5/редактор; GPU не измерен. Hover p95~20.5ms прежний.
Далее адресно capture~11–12ms; разбивка в отчёте, вложенные времена не складывать.

Отчёт/логи/manifests/review: test_reports/worker-preflight-20261008/;
baseline: snapshot-preflight-20261008/. Runner: profile_snapshot_preflight.py.
Import/startup PASS; worker195/0, UI28/0, presentation44/0, capture33/0,
deck battle313/0; адресные render/headless, независимое APPROVE.
Full/core не повторялись: исторически full137PASS/2FAIL control_ui/entangle_ui
(оба на base), core9440/0 с47ObjectDB/18resources; это не текущие PASS.
Вне коммита пользовательская main_menu.tscn; не сбрасывать.

Щитоносец принят; F5/колода/спрайты предварительно приняты.
Полный маршрут/редактор, HUD, финальный арт/баланс, Q-E/артефакты открыты.
Общий набор/отход/исключения/автостойка — Q DESIGN_DIRECTION §3.1.
Сохранять покомандность/preview/live/queue/RNG/save/frozen, profile1–4.
Не начинать школы/кузню/R16/R17/экипировку13/стаки/backlog, микроплейтесты
ядра, покрытия/реакции, revision-only кэш, D4-save миграцию, финальный арт.
Инициатива вне full/render; viewport baseline открыт; --screen0;
DPAPI вне Git/логов/промптов. PROJECT_CONTEXT — маршруты,
CODEX_WORKFLOW — процесс, DESIGN_DIRECTION §7 — порядок.

Проверенный этап: Conventional Commit; прежний HANDOFF точным архивом
CODEX_HANDOFF.history-20261008.md со ссылкой HISTORY. Без push/sidebar/расписаний.
В конце/при блокере предложить новый чат (кроме явного продолжения здесь)
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это правило передачи. Ссылка не заменяет текст; чат не создавать.
