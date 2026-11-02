# Передача — 2026-11-02: размер Разбойника и диагностика зерна

D:/Games/into-de-dung; main; basef9eea8b7da12dfa5aefa4c8e51d972c642de6765.
Параллельно завершён launcher-этап92bf0a1; его изменения сохранены.
По U Разбойник уменьшен на10%: rogue_art_scale0.8→0.72, высота60.8→54.72px
на тайле128. Picking уменьшается вместе с рисунком; опора и клипы idle3/death2/
ability3 прежние. Владельцы: CHARACTER_SKINS_V1, BATTLE_VISUAL_SCENE_CONTRACT.
[Результат/снимки/диагностика](art/rogue-size-sampling-20261102/README.md).
Логи: test_reports/rogue-size-sampling-20261102/ и
 test_reports/demo-c47902f9a1d04e8c900334a12ad7a716/.

Причина потери деталей относительно превью: исходник256² сначала выбирается
на сетке128², затем ещё уменьшается до игрового размера. Сравнение одинакового
кадра/геометрии: текущий128, прямой nearest256, полный256 с покрытием.
Последний спокойнее сохраняет детали, но мягче. Это проба: production shader
не менялся. Новая генерация/ретушь не выполнялась. Дальше — отзыв U и отдельный
выбор правки рендера; автоматически новый этап не начинать.

PASS isolated import/startup; GPU skins424/0, class UI40/0, attack styles611/0,
unit45/0, visual106/0; legacy Rogue98/0 GPU/headless; zoom496/0 GPU;
диагностический рендер22/0. Независимое APPROVE.
Использован снимок launcher из базы; параллельный этап сообщил о пересечении
native импортов. Performance не измерялся. Full/core не повторялись.
Ручные F5/движение/zoom/DPI, художественная приёмка/швы, performance открыты;
turn_forecast_ui26/3 прежний; HUD/Колода без новой приёмки. Маг пока «М».

Текущий launcher хранит3 последние завершённые копии, --keep-project закрепляет:
[правила](REPOSITORY_STATE.md#автоочистка-тестовых-копий). Логи/снимки сохраняются.
Чужие main_menu.tscn и docs/art/battlefield-reference-03-20261017/ не reset/stage/commit.
Core/preview/queue/RNG/save/frozen сохранять. Один Godot runner, isolated project;
без root import/служб/драйверов/принудительного фокуса/push/sidebar/расписаний.
[Прежняя передача побайтно](CODEX_HANDOFF.history-20261102-3.md), [HISTORY](HISTORY.md).

Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельным архивом+HISTORY. В финале/при блокере предложить
новый чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts,
остаток, ограничения, проверки и это же правило. Чат автоматически не создавать.
