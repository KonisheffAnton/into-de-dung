# Передача — 2026-10-12: анимации разбойника в игре
D:\Games\into-de-dung; main; base fe88f2b10677ec688e0a9729f63d334ac2e0dbfe.
U поручил интеграцию выбранных idle/B1/D3. В походе и пробной сцене обе стороны
получили idle12×200ms, B1 5кадров/0.97s с исправленным контуром, D3 13×200ms.
B1 — существующая «Защита»/guarded, новой способности нет. После D3 — штатное
generic-тело окружения; падения/VOID/HAZARD/обвал прежние. PNG/ритм источников
сохранены; новых генераций/поз нет. Масштаб/опора/отражение/picking подключены.
Пакет: assets/art_presets/trials/rogue_animations_v1/README.md и manifest.json.
Источники: docs/art/rogue-idle-cadence-20261012,
docs/art/rogue-buff-outline-20261012/final,
docs/art/rogue-buff-death-variants-20261012/death-03-side.
Поведение/приёмка: ART_DIRECTION, BATTLE_VISUAL_SCENE_CONTRACT; команды TESTING.
Отчёт/PNG: test_reports/rogue-animation-integration-20261012/REPORT.md.
Godot import/startup/render21/21 PASS; Rogue109/0, B1 37/0, death routes408/0,
zoom/picking396/0, регрессия Защитника, lifecycle/HUD/execution/pounce PASS.
Пробное поле410/0; Python22/22; сборка36/36,32PNG, idleRGBA12/12.
Независимое ревью APPROVE. Full/core/manual F5/editor/DPI/GPU не запускались.
Технический PASS не художественная приёмка. Остаток — ручной F5-отзыв U
о посадке и швах idle/B1/D3/тела; после приёмки — этап гамм одежды по ART_DIRECTION.
Новые работы/генерации без поручения не начинать. Анимации только PixelLab;
прежнее исключение — явно разрешённая локальная коррекция цветов B1.
Старые пробы сохранять. Защитник принят; отдельный опубликованный арт:
codex/approved-defender-art-20261012,64ba319d. Интеграция локальна, push нет.
«Ветеран» не подключён. Другие ветки/код не push.
Пользовательская scenes/demo/main_menu.tscn незакоммичена: не трогать,
не сбрасывать/stage/commit. Сохранять preview/live/worker/queue/RNG/save/frozen.
Маршрут PROJECT_CONTEXT; процесс CODEX_WORKFLOW; порядок DESIGN_DIRECTION §7.
Инициативы нет; BT/старые save прежние. Без sidebar/расписаний.
DPAPI только api.pixellab.ai вне Git/логов. P-удар/тени/свет/баланс не начинать.
После этапа Conventional Commit; короткий HANDOFF, прежний побайтно отдельным
архивом+HISTORY. В финале/при блокере предложить новый чат и дать полный промпт:
HEAD/результат/docs/artifacts/остаток/ограничения/проверки и это же правило передачи.
Ссылка не заменяет текст; чат автоматически не создавать.
