# Передача — 2026-10-15: плейтест рестарта принят
D:\Games\into-de-dung; main; base bacfdc503375164529ea6dc23ec4684c6a016df9.
U после сценария кнопки/R: «Ну вроде все ок»; ручной плейтест рестарта закрыт.
[Владелец](BATTLE_HUD_SCENES_V1.md#рестарт-текущего-уровня).
Общий отзыв, без отдельных PASS по пунктам и проверки FAULTED/ошибок записи.
Только docs: diff/ссылки/размеры/побайтный архив проверены; Godot не запускался.
Свидетельства: test_reports/restart-playtest-20261015/REPORT.md, validation.json.
V1 реализован: пять характеристик, найм/развитие, формулы, дроби, DOT, UI,
preview/worker, save v7; старые файлы не мигрировать/не удалять.
DOT: общие сроки, отдельные вклады авторов сохраняются после смерти/ухода.
[Правила V1](CHARACTER_ATTRIBUTES_V1.md); [DTO](BATTLE_SNAPSHOT_CURRENT.md);
[save](SAVE_FORMAT_CURRENT.md). Новых временных ослаблений нет;
пересчёт производных для них требует отдельного контракта.
Прежние проверки: test_reports/character-attributes-v1-20261015/REPORT.md,
review.md/validation.json: full174/0, core9424/0, Python22/22, APPROVE.
После финальной UI-правки import/startup, worker873/0, expedition UI56/0 PASS;
hub/HUD render PASS, PNG просмотрены. Здесь не повторялись.
Общая F5/editor/DPI/GPU-матрица и баланс открыты; поход100 не проверяет ветерана20.
Опубликован только документ формул: codex/character-attributes-design-20261015,
commit5c0063537a296797e46d606342be9ec9e9065d15; код V1 локален, worktree архивирован.
scenes/demo/main_menu.tscn — единственный чужой dirty: не трогать/reset/stage/commit.
Сохранять core/preview/live/worker/queue/RNG/save/frozen; без push/sidebar/расписаний/
P-удара/теней/света/дальнейшего баланса. Поле8×8; [окружение](SURROUND_DAMAGE.md), 9/8 снята.
Лучница idle подключена, цвет позже; Rogue гаммы/темп/fade/зернистость/B1/швы открыты.
Защитник принят, Ветеран не подключён. Генерации/цвета/клипы только по U.
Анимации только PixelLab, пробы сохранять; позы/alpha вручную не менять; исключение — RGB Rogue B1.
DPAPI вне Git/логов, только api.pixellab.ai. Следующий этап — ждать поручения U.
Прежний HANDOFF побайтно: [архив](CODEX_HANDOFF.history-20261015-2.md), [HISTORY](HISTORY.md).
После этапа Conventional Commit и короткий HANDOFF; прежний побайтно отдельным
архивом+HISTORY. В финале/при блокере предложить новый чат и полный промпт блоком:
HEAD/результат/docs/artifacts/остаток/ограничения/проверки и это же правило передачи.
Чат автоматически не создавать; ссылка не заменяет текст промпта.
