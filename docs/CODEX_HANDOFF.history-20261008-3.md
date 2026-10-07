# Передача — 2026-10-08: доска capture

Main; base b174552fde0d4c8c12d6a6c1ed4447065e1dafff; без push.
Прежний worker-аудит получил «пока ок»; новый срез реализован по поручению.
ItemSimulationSnapshot.capture принимает изолированный локальный board DTO
без второй копии; прочие ветви копируются как прежде. Все проверки сохранены.
Кэша/смены правил/queue/codecs/save нет. Владение — ARCHITECTURE,
проверки — TESTING; worker/UI — BATTLE_EXECUTION_UI.

Два probe: median capture11.57–11.77→10.92–11.27ms, выигрыш0.50–0.65ms.
Три production A/B: заметное улучшение кадровой плавности не доказано.
Полные состояния/events/steps/RNG/counters/admission/publications
всех6 controls и4 probes совпали. Fixture не F5/редактор; GPU не измерен.
Ручная оценка среза открыта. Далее адресно MageDeckRules.live_valid:
180 вызовов/180 idle кадров; проверить владельца и сериализацию бойцов.
Вложенные времена не складывать; диагностику/свежесть/изоляцию сохранять.

Отчёт/замеры/manifests/review/verification/completion:
test_reports/capture-preflight-20261008/. Runner: profile_snapshot_preflight.py.
Import/startup PASS; live snapshot41/0, value copy12/0, deck313/0,
render presentation44/0 и PNG; независимое APPROVE.
Full с продолжением:138PASS/2FAIL из140 уникальных меток;
control_ui25/1 и entangle_ui21/1 воспроизведены на base. Не общий PASS.
Core9440/0 с прежними47ObjectDB/18resources; логи — отчёт.
Пользовательская main_menu.tscn вне коммита; не сбрасывать.

Прошлый срез поля/HUD и Щитоносец приняты;
F5/колода/спрайты предварительно приняты.
Полный маршрут/редактор, HUD, финальный арт/баланс, Q-E/артефакты открыты.
Общий набор/отход/исключения/автостойка — Q DESIGN_DIRECTION §3.1.
Сохранять покомандность/preview/live/queue/RNG/save/frozen, profile1–4.
Не начинать школы/кузню/R16/R17/экипировку13/стаки/backlog, микроплейтесты
ядра, покрытия/реакции, revision-only кэш, D4-save миграцию, финальный арт.
Инициатива вне full/render; viewport baseline открыт; --screen0;
DPAPI вне Git/логов/промптов. PROJECT_CONTEXT — маршруты,
CODEX_WORKFLOW — процесс, DESIGN_DIRECTION §7 — порядок.

Проверенный этап: Conventional Commit; прежний HANDOFF точным архивом
CODEX_HANDOFF.history-20261008-2.md со ссылкой HISTORY. Без push/sidebar/расписаний.
В конце/при блокере предложить новый чат (кроме явного продолжения здесь)
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это правило передачи. Ссылка не заменяет текст; чат не создавать.
