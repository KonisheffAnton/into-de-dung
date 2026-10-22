# Передача — 2026-10-22: очистка неиспользуемого кода
D:\Games\into-de-dung; main; base aaf2d95cf02646a5eaf553b5244cc092a4d3f6e1.
По U выполнен аудит кода/сцен/ресурсов/инструментов и безопасная очистка.
Удалены 4 невызванных внутренних метода и 2 осиротевших скрипта с UID:
ElevatedTileVisual и IsoCameraController; всего 174 строки кода/UID.
Действующие камера/тайлы, проверки AttackRules, preview/live/worker/queue/RNG/save
не менялись. Поддерживаемые legacy HUD/сцены, BT-адаптер и frozen сохранены.
Устаревшие сведения V1/инициативы исправлены в [архитектуре](ARCHITECTURE.md),
Python-команда и диагностика core — в [проверках](TESTING.md).
[Отчёт и evidence](../test_reports/project-cleanup-20261022/README.md).
Headless: 13 PASS/0 FAIL/0 timeout, включая import/startup и core 9424/0;
прогноз/worker/изоляция/окружение/тексты/HUD/хаб/камера PASS.
Render: 5 PASS/0 FAIL/0 timeout, включая import/startup;
visual contract 52/0, camera 110/0, HUD 306/0; PNG хаба осмотрен.
Python оба набора 43/0. Независимое ревью фиксированного diff — APPROVE.
Полный набор всех меток и ручные F5/editor/DPI/GPU не выполнялись.
Чужие dirty scenes/demo/main_menu.tscn и untracked docs/art/battlefield-reference-03-20261017/
не трогать/reset/stage/commit; SHA сцены прежний, записан в evidence.
Прежние вопросы: ощущение импульса/серии атак и баланс ожидают U;
контракты [показа](BATTLE_PRESENTATION_REWORK.md) и [экипировки](EQUIPMENT_ATTACKS.md).
Выбор/внедрение арт-стиля открыт; концепты вне проекта, пути в архиве ниже.
Четыре [диорамы](art/hub-diorama-layered-20261018/README.md) сохранены для возврата;
HTML не внедрять, playback/размещение/подсветка не приняты. Арт — [ART](ART_DIRECTION.md).
Следующий шаг — выбор U; очистка не разрешает удалять поддерживаемые режимы,
менять баланс/арт или автоматически начинать новый механизм.
Без push/sidebar/расписаний. [Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261022.md),
[HISTORY](HISTORY.md).
После этапа — проверки и Conventional Commit; короткий HANDOFF, прежний побайтно
в отдельный архив+HISTORY. В финале/при блокере предложить новый чат и полный
промпт блоком: HEAD, результат, docs/artifacts, остаток, ограничения, проверки
и это же правило передачи. Чат автоматически не создавать; правило переносить.
