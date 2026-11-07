# Передача — 2026-11-07: тоньше полосы, чёрные цифры и рамка

D:/Games/into-de-dung; main; basef8dd00269bf2f5b1b91607b3ff09a24d6149ed7c.
По U высота HP/брони12→11px (примерно10%), ширина48 прежняя.
Цифры Jersey20 чёрные, тонкая чёрная рамка1px внутри внешних границ.
Пустая подложка приглушённо осветлена для читаемости нуля; заполнение
и прогноз идут внутри рамки46×9, поэтому малый остаток не скрыт краем.
HP зелёное, броня металлическая. Общий урон над получателем и тайминг прежние.
Владелец: docs/BATTLE_PRESENTATION_REWORK.md; ARCHITECTURE/TESTING обновлены.

Свежие isolated import/startup PASS; unit_visual_contract45/0, contact327/0.
presentation_status84/2: только прежние ошибки размеров поля, ранее
воспроизведённые на base66/2; новые проверки цифр/рамок PASS.
Launcher4/1/0, не полный PASS. GPU общий удар/дробные полосы просмотрены.
Независимое ревью APPROVE. Отчёт test_reports/vitals-bar-trim-20261107/;
runner demo-7135743558574b0790abc72da7dd1a91.
Первый импорт прервался на TTF; повтор без смены кода PASS. Причина
не установлена; прежняя связь с preload не доказана. Затем исправлена
заливка под рамкой и повторены проверки. Full/core, ручные F5/движение/
zoom/DPI/performance не запускались; старые проверки не считать повторёнными.

Далее — отзыв U о полосах в текущем бою; новые срезы без запроса не начинать.
Принятый огонь29 natural02-middle сохранён:
docs/art/fire29-natural-integration-20261107/, ART_DIRECTION.
Остаток: стыки/посадка/читаемость, край стрелы4 Лучницы, performance;
presentation_status84/2, presentation_foundation141/2, turn_forecast_ui26/3, HUD/Колода.
Чужие33 файла: scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/;
не reset/stage/commit. Core/preview/queue/RNG/save/frozen сохранять;
5 классов F5, PLAYER вправо/ENEMY влево и возврат; каталоги1–3 не мигрировать.
Один Godot runner, isolated project; без root import, служб/драйверов,
принудительного фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261107-12.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
