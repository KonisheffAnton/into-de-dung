# Передача — 2026-11-15: развитие Костяша №5

D:/Games/into-de-dung; main; база интеграции9b6e8e96adeb8601f478b90aaa2474cfa3395efe.
U выбрал№5 маленькой пятёрки, поручил «сам рисуй», рост2/3 героя.
Built-in image_gen:1 новый RGBA1402×1122; крупные формы/костяная морда/горб/лапки.
Пакет: docs/art/kostyash05-imagegen-20261115/README.md; владельцы ART_DIRECTION/GRAPHICS_WORKFLOW.
Сравнение: Воин/Маг456px, Костяш304px, baseline544, точно1,5:1; эквивалент101⅓px.
PASS SHA/референсы/сборка/py_compile/ревью,33 чужих файла. Исходный PNG не изменён.
Alpha1–7 шум вне тела исключён только из измерения; это ещё не native101px.
Выбор U/стиль/посадка/нативный спрайт открыты, integration=false; анимации не запускать.

Кузнец: U выбрал значки экипировки поверх фигуры, weapon/armor, новых слотов нет.
Владелец HUB_DESIGN_PLAN §4; docs/art/hub-smith-preview-20261115/README.md.
Макет/координаты/размеры/условные вещи — P; далее отзыв U, без автовнедрения.
U принял бесплатное полное восстановление брони в хабе, износ в походе сохранён;
предупреждения хаба/платный финальный ремонт убрать, промежуточный прежний.
Ещё не внедрено; HUB_DESIGN_PLAN §3/POST_BATTLE_V1, H1/HUB_SCENES.
Хаб af6b7467: docs/art/hub-approved-implementation-20261114/ и test_reports/;
прежние gates не повторялись, p95≈18,3мс, стабильные60FPS не достигнуты;
команда3, будущий лимит Q; ручная приёмка/доступность открыты.
Бой: status-readability ждёт U; стыки/стрела4 Лучницы/performance/HUD/Колода;
presentation141/2,forecast26/3 не повторены.5атак: art/warrior-attack-single-five-20261114/;
выбор/возврат/шов открыты. Детали прежнего этапа — архив ниже.

Godot/import/full/core/F5/движение/zoom/OS-DPI/performance здесь не запускались.
Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не reset/stage/commit. Core/preview/queue/RNG/save/frozen,5классов F5,
PLAYER вправо/ENEMY влево и возврат после атаки сохранить; инициативы нет;
каталоги1–3 не мигрировать. Один isolated Godot runner; без root import,
служб/драйверов/фокуса ОС/push/sidebar tasks/расписаний.
[Прежняя передача побайтно](CODEX_HANDOFF.history-20261115-6.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
