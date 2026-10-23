# Передача — 2026-10-23: быстрый запуск isolate
D:\Games\into-de-dung; main; base2cec58fd287baea17658817f7f9cb898d82a061f.
U сообщил о медленном открытии игры через tools/demo/isolate.py.
Обычный cached interactive теперь исключает docs/ с отчётами/арт-пробами.
Полные --fresh/--check/--render-check, SHA содержимого, lease, отдельные профили
и обработка отказов прежние. [Контракт запуска](REPOSITORY_STATE.md),
[проверки](TESTING.md), [отчёт и замеры](../test_reports/isolate-startup-20261023/report.md).
Парный warm-замер подготовки до Popen:22,49→4,29с (5,24×); cold27,44с.
Миграция прежней копии29,78с уже выполнена; источники документов сохранены.
Исторические89,50с включали импорт и не являются парной базой сравнения.
Python launcher30 tests OK, cache15 tests OK. Реальный Godot cold/warm и
same-size/mtime SVG red→green PASS; игры завершились exit0 без diagnostics.
Чистый check:import/startup PASS, defender_idle_clock24/0; итого3PASS/0FAIL.
Независимое ревью APPROVE. Свидетельства и границы — в отчёте.
Full/core и ручные F5/editor/DPI/GPU не заявлены; пользовательская оценка скорости
ожидается. Core/preview/live/worker/queue/RNG/save/frozen не менялись.
Прежний выбор воина как [эталона](../assets/art_presets/approved/warrior_format_v1/README.md)
сохраняется; [ART_DIRECTION](ART_DIRECTION.md) владеет правилами.
Death-2/idle-1 enemy-warrior прежние; [результат и открытая ручная приёмка](art/enemy-warrior-death-20261023/README.md).
Остальные классы не заменялись. Нового персонажа автоматически не начинать.
Следующий шаг — отзыв U о скорости или отдельно выбранное им поручение.
Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не трогать/reset/stage/commit. Без push/sidebar tasks/расписаний.
[Предыдущий HANDOFF побайтно](CODEX_HANDOFF.history-20261023-6.md), [HISTORY](HISTORY.md).
После этапа — проверки и локальный Conventional Commit; короткий HANDOFF,
прежний побайтно в отдельный архив+HISTORY. В финале/при блокере предложить
новый чат и полный самодостаточный промпт:HEAD,результат,docs/artifacts,остаток,
ограничения,проверки и это же правило передачи. Чат автоматически не создавать.
