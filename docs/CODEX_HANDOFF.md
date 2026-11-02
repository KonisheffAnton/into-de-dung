# Передача — 2026-11-02: полный кадр фигур с покрытием

D:/Games/into-de-dung; main; base8f405fe3ac389b9a5832f89710826587db9dace2.
По U убрана дополнительная выборка моделей по уменьшенной сетке. Все текстурные
слои production-фигур читают полный исходный кадр с покрытием: skin-клипы,
legacy-классы, Body и NPC. Палитры/маски/alpha, PNG, опоры, стороны команд,
пикинг и тайминги сохранены. Разбойник0.72, idle3/death2/ability3 прежние.
Владельцы: BATTLE_VISUAL_SCENE_CONTRACT, CHARACTER_SKINS_V1.
[Отчёт/снимки/validation](art/character-coverage-20261102/README.md).
Логи: test_reports/character-coverage-20261102/ и
 test_reports/demo-2f6818ee1cf447c0b22d0517a2480701/ (первичный импорт/набор).

PASS isolated import/startup; GPU coverage53/0, skins424/0, zoom496/0,
cloth321/0+148/0+206/0, palette15/0, warrior39/0, class UI40/0,
attack styles611/0, unit45/0, visual106/0; headless coverage26/0, skins386/0.
Python35/0; builder29 выходов/17PNG побайтно/429 ячеек и таймингов.
Старые shaders дали18 ожидаемых FAIL без script errors; копия восстановлена.
Независимое APPROVE. Full/core не повторялись.

Смежный presentation_foundation141/2 одинаков на текущем коде и базе8f405fe:
ожидания fallback warrior и picking движущегося warrior; не исправлялись.
Прежний turn_forecast_ui26/3 открыт. Ручные F5/движение/zoom/DPI,
художественная приёмка/швы, performance и HUD/Колода остаются открыты.
Короткие интервалы render probe не доказывают FPS игры. Маг пока «М»;
каталоги1–3 не мигрированы. Дальше — отзыв U; новый срез без поручения не начинать.

Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не reset/stage/commit;33 файла SHA неизменны. Core/preview/queue/RNG/save/frozen
сохранять. Один Godot runner, isolated project; без root import/служб/драйверов/
принудительного фокуса/push/sidebar/расписаний. Launcher retention — REPOSITORY_STATE.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261102-4.md), [HISTORY](HISTORY.md).

Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельным архивом+HISTORY. В финале/при блокере предложить новый
чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts, остаток,
ограничения, проверки и это же правило. Чат автоматически не создавать.
