# Передача — 2026-11-15: броня в хабе

D:/Games/into-de-dung; main; база 4a1187f94114ced25267cc735d96533f2c4be1cf.
U принял полное автоматическое бесплатное восстановление брони в хабе;
походный износ сохраняется. Убрать предупреждения о броне из хаба и платную
починку из финального отчёта перед хабом; промежуточная починка прежняя.
Только документы: решение ещё не реализовано. Владельцы: HUB_DESIGN_PLAN §3
(UI), POST_BATTLE_V1 (восстановление); H1/HUB_SCENES отделяют текущий код.
Проверки и итог: test_reports/hub-armor-autorestore-plan-20261115/.
Следующий шаг — обсуждение кузнеца; его новая композиция не утверждена.
Реализацию брони/новый механизм автоматически не начинать.

Хаб реализован в af6b7467; docs/art/hub-approved-implementation-20261114/
и одноимённый test_reports/. Прежние import/14suites/launcher/GPU/soak/review
здесь не повторялись. Frame p95≈18,3мс, стабильные60FPS не достигнуты.
Команда3, будущий лимит Q; ручная приёмка хаба/доступность открыты.
Костяш: docs/art/kostyash-development-five-20261114/README.md —5 вариантов,
integration=false; ждут выбора U, анимации/внедрение без поручения не начинать.
Детали прежнего этапа — в архиве ниже. Бой: status-readability ждёт U,
стыки/стрела4 Лучницы/performance/HUD/Колода; presentation141/2 и forecast26/3
не повторялись.5 атак: docs/art/warrior-attack-single-five-20261114/;
выбор/возврат/шов открыты.

Документация: diff/ссылки/архив/размеры/33 чужих файла PASS; ревью APPROVE.
Godot/import/full/core/F5/движение/zoom/OS-DPI/performance здесь не запускались.
Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не reset/stage/commit. Core/preview/queue/RNG/save/frozen,5классов F5,
PLAYER вправо/ENEMY влево и возврат после атаки сохранить; инициативы нет;
каталоги1–3 не мигрировать. Один isolated Godot runner; без root import,
служб/драйверов/фокуса ОС/push/sidebar tasks/расписаний.
[Прежняя передача побайтно](CODEX_HANDOFF.history-20261115-2.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
