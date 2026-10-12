# Передача — 2026-10-12: темп и чистота разбойника
D:\Games\into-de-dung; main; base c464c03d99f316dcebe231dc00794c984e84f197.
По отзыву U D3 падает0.65s (13×50ms), лежит0.25s, плавно исчезает0.80s:
всего1.70s одним Tween, затем прежний after/generic-тело. Fade только рисунка
Rogue, cleanup/resize/class reuse согласованы. D3 PNG/изометрия прежние.
B1: PixelLab дал два этапа раскрытия с меньшим шагом у максимума/удержанием;
6кадров120/240/60/320/120/160ms=1.02s. Прежний возврат, два кинжала.
Сетка материала Rogue128×128 вместо512 снижает зернистость уменьшения;
полный source_region512 и PNG сохранены. ArtRoot0.73/опора/picking прежние.
Пакет: docs/art/rogue-timing-cleanup-20261012/README.md.
Игровой: assets/art_presets/trials/rogue_animations_v1/README.md.
Контракты ART_DIRECTION, BATTLE_VISUAL_SCENE_CONTRACT; команды TESTING.
Отчёт/GIF/A-B: test_reports/rogue-timing-cleanup-20261012/REPORT.md.
Godot import/startup; целевой render19PASS+2syntaxFAIL теста. После scope-fix
повтор4/4: Defender death routes408/0,Rogue433/0. Прочие19PASS актуальны:
Rogue136/0,B1 38/0,zoom396/0,Защитник/lifecycle/HUD/execution/pounce.
Python22/22,сборка37/37,33PNG,idleRGBA12/12,GIF6/6+13/13,capture40/0.
Ревью APPROVE. Full/core/manual F5/editor/DPI/GPU-приёмка не проводились.
Технический PASS не арт-приёмка. Остаток — F5-отзыв U о быстром падении,
исчезновении, зернистости и замедлении размаха; швы idle/B1/D3/тела.
После приёмки — гаммы одежды по ART_DIRECTION, без поручения не начинать.
Анимации только PixelLab; исключение — разрешённая локальная RGB-коррекция B1.
Новых генераций/работ без поручения не начинать. Пробы сохранены;10generations.
DPAPI только api.pixellab.ai, вне Git/логов. Idle/Defender/падения прежние.
Защитник принят; отдельный арт codex/approved-defender-art-20261012,64ba319d.
«Ветеран» не подключён. Интеграция локальная, push нет; другие ветки/код не push.
Пользовательская scenes/demo/main_menu.tscn dirty: не трогать/reset/stage/commit.
Сохранять preview/live/worker/queue/RNG/save/frozen. Инициативы нет; BT/save прежние.
Без sidebar/расписаний; P-удар/тени/свет/баланс не начинать.
Маршрут PROJECT_CONTEXT, процесс CODEX_WORKFLOW, порядок DESIGN_DIRECTION §7.
После этапа Conventional Commit, короткий HANDOFF; прежний побайтно отдельным
архивом+HISTORY. В финале/при блокере предложить новый чат и полный промпт:
HEAD/результат/docs/artifacts/остаток/ограничения/проверки и это же правило передачи.
Чат автоматически не создавать; ссылка не заменяет текст промпта.
