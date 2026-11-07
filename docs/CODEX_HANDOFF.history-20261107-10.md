# Передача — 2026-11-07: нанесённый урон у атакующего

D:/Games/into-de-dung; main; base533a3f743352d75b44b32147732f96408fa9d888.
U уточнил: число показывать у атакующего, у получившего удар убрать.
Реализовано: HP/расход брони/щита и ноль у actor события; восстановление
и статусы у получателя. Значения фактические, overkill не добавлен.
Нет цифры урона при погибшем/отсутствующем/нулевом/self источнике,
включая магию вне бойца. Контратака использует своего автора.
Клетка числа фиксируется; верхнее переполнение стека уходит в соседнюю
колонку либо ниже занятых подписей. Core/preview/queue/RNG/save не менялись.
Контракт — второй срез BATTLE_PRESENTATION_REWORK; ARCHITECTURE; TESTING.

Свежий isolated import/startup и6 GPU-проверок PASS:
presentation_contact337/0, presentation_consequences2044/0,
presentation_environment364/0, presentation_ranged252/0,
presentation_mage349/0, battle_presentation_owned64/0; launcher8/0/0.
Независимое ревью исправленного фиксированного патча APPROVE.
Первый прогон выявил overflow лечения и неверный oracle item healing;
исправлены, весь выбранный набор повторён. GPU chain-wall просмотрен.
Отчёт test_reports/damage-at-attacker-20261107/;
runner demo-e119ce141e4a4547ac658cd907303f6e.
Full/core и ручные F5/движение/zoom/DPI/performance не запускались.
Проверки огня/шипов/HUD этого этапа не повторялись.

Следующий шаг — отзыв U о цифрах в текущем бою; новые срезы без запроса
не начинать. Принятый огонь29 natural02-middle остаётся внедрённым:
пакет docs/art/fire29-natural-integration-20261107/, выбор ART_DIRECTION,
поведение BATTLE_VISUAL_SCENE_CONTRACT. Старый остаток: стыки/посадка/
читаемость, край стрелы4 Лучницы, performance; presentation_foundation141/2,
turn_forecast_ui26/3, HUD/Колода.
Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не reset/stage/commit. Сохранить core/preview/queue/RNG/save/frozen,
5 классов F5, PLAYER вправо/ENEMY влево и возврат после атаки;
каталоги1–3 не мигрировать. Один Godot runner, isolated project;
без root import, служб/драйверов, фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261107-9.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
