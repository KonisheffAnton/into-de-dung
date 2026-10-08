# Передача — 2026-10-08: изометрические пресеты врагов

Main; base 3d7e9ca8f7a4e23868cc9235a0567d8fb21bcac8; без push.
«Пока играется ок» — предварительно, до новых пресетов.
Три пресета подключены противникам для пробы.
Исходники сохранены; image_gen удалил серый фон в отдельных RGBA-производных.
Сцена задаёт кадрирование/размер; опубликованный ID — стабильный вариант без RNG.
Союзный Retro прежний; классы/механики/save не менялись. Новые пресеты не приняты.

Владельцы: BATTLE_PRESENTATION_REWORK/ARCHITECTURE; assets/battle_units/README.md —
происхождение; TESTING — проверки; HISTORY — свидетельства.
Отчёт: test_reports/enemy-iso-presets-20261008/; PNG — пути в report.md.
Import/startup PASS, headless foundation105/0; render foundation116/0,
status62/0, contact149/0/PNG; независимое review APPROVE.
Проверены U14 opening, refresh/playback/смерть/fallback/snapshot/RNG.
Full/core не повторялись. Control/entangle закрыты адресно прошлым этапом;
отчёт control-entangle-ui-20261008.
Прежний full138PASS/2FAIL — история, нового общего PASS нет.
Core9440/0 и47ObjectDB/18resources — прежние; viewport baseline открыт.
Пользовательская scenes/demo/main_menu.tscn вне коммита; не сбрасывать/коммитить.

Capture/live_valid приняты; worker-аудит предварительно ок; отчёты — HISTORY.
Общая плавность не доказана; AI p95/пики без устойчивого улучшения.
Parity6 controls/4 probes; вложенные времена не складывать; fixture не F5/GPU.
Щитоносец и прежний срез поля/HUD приняты; F5/колода/спрайты предварительно.
Полный маршрут/редактор/HUD/финальный арт/баланс/Q-E/артефакты открыты.
Общий набор/отход/исключения/автостойка — Q. Следующий пакет — по поручению;
согласование направления не запускает реализацию, R11/R16/R17 не начинали.
Сохранять покомандность/preview/live/queue/RNG/save/frozen, profile1–4.
Не начинать школы/кузню/R16/R17/экипировку13/стаки/backlog, микроплейтесты ядра,
покрытия/реакции, revision-only кэш, D4-save миграцию, финальный арт.
Инициатива вне full/render; --screen 0; DPAPI вне Git/логов/промптов.
PROJECT_CONTEXT — маршруты; CODEX_WORKFLOW — процесс; DESIGN_DIRECTION §7 — порядок.

Этап — Conventional Commit; прежний HANDOFF точно сохранён в
CODEX_HANDOFF.history-20261008-6.md со ссылкой HISTORY. Без push/sidebar/расписаний.
В конце/при блокере предложить новый чат, кроме явного продолжения здесь,
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это правило. Ссылка не заменяет текст; чат не создавать.
