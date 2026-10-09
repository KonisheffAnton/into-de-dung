# Передача — 2026-10-09: выбранный арт и игровая проекция4:3

D:\Games\into-de-dung; main; base f15c4fdb2f1634e0b157600fdf5239a0f547034a; без push.
Правый чистый рисунок выбран эталоном. ART_DIRECTION — стиль;
assets/art_presets/approved/README.md — вход в утверждённые наборы.
grass_defender_v1 содержит действующие M3/№4, параметры, SHA и ссылки на сцены.
Референс/рендер — docs/art/style-reference-20261009/;
сцена для F6 — scenes/demo/art_style_preview.tscn, обычный F5 сохранён.

Игра переведена на4:3, M3/№4 подключены. Опоры, picking, направления и
ловушки согласованы; кадрирование исправлено. Размер/посадка — preset.json.
Контракты: BATTLE_PRESENTATION_REWORK / ARCHITECTURE / ENVIRONMENT_HAZARDS_V1.

Import/startup PASS; render: foundation143/0, camera110/0, panels81/0,
contact149/0, attack_styles174/0, environment323/0, hazards79/0,
camera math10/0, reuse26/0. Review APPROVE; PNG просмотрены.
Отчёт — test_reports/art-integration-20261009/; команды/снимки — HISTORY.
Core/full/полный render/F5 не повторялись. Прежний full138PASS/2FAIL не общий
PASS; control/entangle закрыты адресно. В status только пользовательская
scenes/demo/main_menu.tscn — не сбрасывать/коммитить.

Далее ручная оценка игры/камеры/стыков/воина/ловушек. Приняты стиль/эталон,
не весь арт/анимации/баланс. Pixel Logic Michael Azzi рекомендована;
полного PDF нет, пользователь может дать книгу для разбора, пока не прочитана.
Capture/live_valid приняты, worker-аудит предварительно; Щитоносец/прежний HUD
приняты. F5/колода/спрайты предварительно; маршрут/редактор/HUD/арт/баланс/Q-E/
артефакты/viewport открыты; набор/отход/исключения/автостойка — Q.
GPU/плавность не доказаны; AI p95 без устойчивого улучшения; времена не складывать,
fixture не F5. Новый пакет по поручению. Сохранять покомандность/preview/live/
worker/queue/RNG/save/frozen/profile1–4. Не начинать школы/кузню/R16/R17/
экипировку13/общие стаки/backlog/микроплейтесты ядра/покрытия/реакции/
revision-only кэш/D4-save/прочий финальный арт. Без sidebar/расписаний;
--screen0; инициатива вне full/render; DPAPI вне Git/логов/промптов.
PROJECT_CONTEXT — маршруты; CODEX_WORKFLOW — процесс; DESIGN_DIRECTION §7 — порядок.

Этап — Conventional Commit, короткий HANDOFF; прежний точным архивом + HISTORY.
В конце/при блокере предложить новый чат, кроме явного продолжения здесь, и полный
промпт: HEAD, результат, docs/artifacts, остаток, ограничения, проверки и это правило.
Ссылка не заменяет текст; чат не создавать.
