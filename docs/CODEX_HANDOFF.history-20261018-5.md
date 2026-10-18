# Передача — 2026-10-18: кэш Python launcher
D:\Games\into-de-dung; main; base516dc1069d3dd279f4f228ed764afb68934d5a91.
Interactive isolate.py сохраняет копию/кэш, синхронизирует SHA256 и изменения;
unchanged import SKIPPED. Профиль каждого запуска отдельный; lease до выхода игры.
--fresh даёт новую копию; check/render сохранили чистые копии/import/startup.
[Запуск](REPOSITORY_STATE.md), [отчёт](../test_reports/interactive-launcher-20261018/README.md).
Cold55.3с, warm7.8с подготовки, не до видимого меню.
Python28+15 PASS; реальный changed SVG/class PASS; fresh import/startup PASS,
camera10/0, launcher3PASS. Ревью APPROVE. Далее U: ярче/интереснее путь; выделения/UI не менять.
Поле без clipping HUD внедрено в1db80b3; GUI-ввод за Board прежний:
видимые за ним клетки для клика вернуть камерой. [Контракт](BATTLE_HUD_SCENES_V1.md),
[кадры/проверки](../test_reports/hud-unclipped-20261018/README.md); отзыв U открыт.
Арт-[сборка](art/warrior-tile-scene-20261018/README.md) ждёт отзыва U:
палитра первого листа/размер второго; внедрение арта не разрешено.
Новых full/core/ручных F5/editor/DPI/GPU и финальной приёмки нет.
Ранее: [коричневые боковины](art/tile-brown-depth-20261017/README.md),
18→30px native128, gate23/0, аудит17/0,158PNG побайтно; перекрытия вручную не проверены.
[Лучница](art/archer-placement-20261017/README.md): still/idle anchor(68,95), PNG/тайминги прежние.
Яркий Защитник — [эталон](../assets/art_presets/approved/defender_brighter_v1/README.md).
Круглые тени в игре; направленные/ракурс2:1 — preview.
Поджог/яд мага, спокойные выделения/скрытые плашки, одежда Лучницы сохранены;
баланс яда открыт. Idle A/B не внедрены; разворот нормальный, вопрос о камере.
Серии04/05: выбор открыт, сохранять оценки монстров, ракурс/размеры;
без подставок/спин, PixelLab отменён. Серия03 остановлена, manifest устарел; не менять.
Чужой scenes/demo/main_menu.tscn не трогать/reset/stage/commit; SHA256 прежний.
Незакоммиченное вне этапа: эта сцена и docs/art/battlefield-reference-03-20261017/.
Core/preview/live/worker/queue/RNG/save/frozen сохранять. Без push/sidebar/расписаний.
Прежний HANDOFF: [побайтный архив](CODEX_HANDOFF.history-20261018-4.md), [HISTORY](HISTORY.md).
После этапа — Conventional Commit, короткий HANDOFF; прежний побайтно
в отдельный архив+HISTORY. В финале/при блокере предложить новый чат и полный
промпт блоком: HEAD, результат, docs/artifacts, остаток, ограничения, проверки
и это же правило. Чат автоматически не создавать; правило переносить дальше.
