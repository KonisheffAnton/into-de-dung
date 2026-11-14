# Передача — 2026-11-15: значки экипировки поверх героя

D:/Games/into-de-dung; main; база 0f4fb48ffd6bd7df20b907efc531afea5890dc95.
U выбрал значки надетого поверх фигуры: оружие у руки, доспех у корпуса.
В макете две кнопки48×48, hover/focus-название, клик открывает осмотр справа;
лицо открыто, нижние карточки убраны. В хабе два слота weapon/armor, новых нет.
Выбор записан в HUB_DESIGN_PLAN §4; координаты/размеры/условные вещи — P.
Пакет docs/art/hub-smith-preview-20261115/README.md; hub-smith-overlay.html,
overlay-1024.png/overlay-dark.png. Отчёт test_reports/hub-smith-overlay-20261115/.
JS parse; Edge21/0, отдельно overlay48×48/клик; кадры просмотрены.
Runtime не менялся. Следующий шаг — отзыв U/обсуждение кузнеца, без автовнедрения.

U принял бесплатное полное восстановление брони в хабе, износ в походе сохранён;
предупреждения хаба/платный финальный ремонт убрать, промежуточный прежний.
Ещё не внедрено; HUB_DESIGN_PLAN §3/POST_BATTLE_V1, H1/HUB_SCENES.
Хаб af6b7467: docs/art/hub-approved-implementation-20261114/ и test_reports/;
прежние gates не повторялись, p95≈18,3мс, стабильные60FPS не достигнуты.
Команда3, будущий лимит Q; ручная приёмка/доступность открыты.
Последние Костяши: docs/art/kostyash-feral-small-five-20261115/README.md;
выбор U/стиль/посадка открыты, integration=false; анимации не начинать автоматически.
Бой: status-readability ждёт U; стыки/стрела4 Лучницы/performance/HUD/Колода;
presentation141/2,forecast26/3 не повторены.5атак:
docs/art/warrior-attack-single-five-20261114/ — выбор/возврат/шов открыты.

Godot/import/full/core/F5/движение/zoom/OS-DPI/performance здесь не запускались.
Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не reset/stage/commit. Core/preview/queue/RNG/save/frozen,5классов F5,
PLAYER вправо/ENEMY влево и возврат после атаки сохранить; инициативы нет;
каталоги1–3 не мигрировать. Один isolated Godot runner; без root import,
служб/драйверов/фокуса ОС/push/sidebar tasks/расписаний.
[Прежняя передача побайтно](CODEX_HANDOFF.history-20261115-5.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
