# Передача — 2026-11-15: макет кузнеца

D:/Games/into-de-dung; main; база bfce3ec02d370069b07433dee7e5da8d086f5493.
P-макет: инвентарь слева, герой/слоты в центре, предмет/сравнение справа;
без ремонта. Фильтры, владельцы, отдельная передача, совместимость,
фиксированное действие. Числа/названия условные, выбор U открыт.
Пакет: docs/art/hub-smith-preview-20261115/README.md; HTML и2 кадра рядом.
Отчёт: test_reports/hub-smith-preview-20261115/. JS parse; Edge21/0,
1024/736/320, визуальная проверка; ревью APPROVE после исправления фильтрации.
Runtime не менялся. Далее отзыв U/обсуждение кузнеца, без автозапуска внедрения.

U принял бесплатное полное автовосстановление брони в хабе; износ в походе
сохраняется. Убрать предупреждения хаба и платный финальный ремонт;
промежуточный ремонт прежний. Ещё не внедрено. Владельцы HUB_DESIGN_PLAN §3,
POST_BATTLE_V1; H1/HUB_SCENES отделяют действующий код. Прежний отчёт:
test_reports/hub-armor-autorestore-plan-20261115/.
Хаб af6b7467: docs/art/hub-approved-implementation-20261114/ и test_reports/.
Прежние gates не повторялись; frame p95≈18,3мс, стабильные60FPS не достигнуты.
Команда3, будущий лимит Q; ручная приёмка/доступность открыты.
Костяш: docs/art/kostyash-development-five-20261114/README.md — выбор U открыт,
integration=false.5 атак: docs/art/warrior-attack-single-five-20261114/;
выбор/возврат/шов открыты. Бой: status-readability ждёт U; стыки/стрела4 Лучницы/
performance/HUD/Колода; presentation141/2 и forecast26/3 не повторены.

Godot/import/full/core/F5/движение/zoom/OS-DPI/performance здесь не запускались.
Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/;
также появился параллельный docs/art/kostyash-feral-small-five-20261115/.
Чужое не reset/stage/commit. Core/preview/queue/RNG/save/frozen,5классов F5,
PLAYER вправо/ENEMY влево и возврат после атаки сохранить; инициативы нет;
каталоги1–3 не мигрировать. Один isolated Godot runner; без root import,
служб/драйверов/фокуса ОС/push/sidebar tasks/расписаний.
[Прежняя передача побайтно](CODEX_HANDOFF.history-20261115-3.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
