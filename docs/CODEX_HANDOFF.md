# Передача — 2026-10-22: цифры вскоре после контакта
D:\Games\into-de-dung; main; base 6bb08ed351a3da3ffd4a901d9e0e324ef8a21152.
U уточнил: урон показывать через долю секунды после касания, сохранив динамику.
Число подтверждённого удара появляется через 0,05 с клипа после контакта;
ближний/дальний/наскок/реакции и mage.fire используют одну задержку.
Callback параллелен отдаче в общем Tween; ×3 ускоряет задержку. Замах,
полёт, hit-stop, отдача, смерть и длительность клипа сохранены.
Полный after, полосы HP/брони и HUD публикуются по-прежнему в конце клипа;
число берётся из уже исполненных событий, не дублируется при завершении.
Mage.heal/поддержка/столкновения/DOT прежние. Skip/cancel/replay очищают показ.
Контракт: [R04/R05/R07](BATTLE_PRESENTATION_REWORK.md), [V1](BATTLE_PRESENTATION_V1.md),
[архитектура](ARCHITECTURE.md); [проверки](TESTING.md).
[Отчёт/evidence](../test_reports/hit-number-timing-20261022/README.md).
10 render-наборов PASS: contact160, styles194, ranged250, mage326,
reactions428, consequences2007, environment323, battle44,
defender death408, rogue death433 (везде 0 failed). Import/startup PASS.
Первый прогон: 9 PASS/3 FAIL из-за синтаксиса новых тестов; исправлен,
повтор трёх наборов: 5 PASS/0 FAIL/0 timeout с import/startup.
PNG раннего числа осмотрен. Независимое финальное review APPROVE.
Новых full/core/Python и ручных F5/editor/DPI/GPU нет; ощущение задержки ждёт U.
Чужие scenes/demo/main_menu.tscn и untracked docs/art/battlefield-reference-03-20261017/
не трогать/reset/stage/commit; SHA сцены прежний, записан в evidence.
Core/preview/live/worker/queue/RNG/save/frozen сохранены; без нового баланса.
Прежние вопросы импульса/серии атак, выбора стиля и диорам остаются открыты;
[арт](ART_DIRECTION.md), детали/пути концептов — в архивной передаче.
Следующий шаг — отзыв U о 0,05 с; новый механизм/арт автоматически не начинать.
Без push/sidebar/расписаний. [Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261022-2.md),
[HISTORY](HISTORY.md).
После этапа — проверки и Conventional Commit; короткий HANDOFF, прежний побайтно
в отдельный архив+HISTORY. В финале/при блокере предложить новый чат и полный
промпт блоком: HEAD, результат, docs/artifacts, остаток, ограничения, проверки
и это же правило передачи. Чат автоматически не создавать; правило переносить.
