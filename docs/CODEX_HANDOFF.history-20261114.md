# Передача — 2026-11-11: цифры с отступом и статусы над бронёй

D:/Games/into-de-dung; main; base4df33b368e85d26ddda5109cd9eac7a394476717.
Последнее U отменило вертикаль: внедрён горизонтальный ряд прямо над бронёй,
через опору полос класса. Пять полевых SVG со сглаживанием; до3 значков и +N,
полный список в осмотре. Hover-only/подложка№4 сохранены; рамочные24 PNG прежние.
Цифры HP/брони теперь с1px свободной заливки до рамки сверху/снизу;
малый AA-штрих усилен,48×9 экранныхpx и фиксированный zoom-размер сохранены.
Гамма/арт фигур/механики прежние. Постоянный ряд C не принят.
Контракт docs/BATTLE_PRESENTATION_REWORK.md; выбор docs/ART_DIRECTION.md;
устройство docs/ARCHITECTURE.md и docs/BATTLE_HUD_SCENES_V1.md.
Пакет docs/art/status-readability-20261111/; ресурсы assets/ui/status_symbols/.
Отчёт test_reports/status-readability-20261111/.

Свежие isolated import/startup PASS; vital548/0, status158/0, counter59/0,
icons442/0, unit_contract45/0, card119/0, hud_input163/0, camera112/0,
execution61/0, visual_scene106/0, contact414/0, reactions1426/0, art_zoom520/0.
GPU30 RGBA полос,8 непрозрачных масок соседей, core/RNG PASS.
Независимое APPROVE; closeout — validation.json. Прежние gates не повторены.
Full/core, ручные F5/движение/zoom/OS-DPI/usability/performance не запускались.
Далее — отзыв U в бою; новые срезы автоматически не начинать.
Хаб: вкладки+диорама «Поход», здания позже; H0→H1→H4;
docs/DESIGN_DIRECTION.md §6.1, docs/HUB_DESIGN_PLAN.md. Первый экран обсуждается;
композиция/названия/школы/материалы P/Q, реализация хаба/H2/H3/H5 не начата.
Остаток: читаемость/стыки/посадка, край стрелы4 Лучницы, performance, HUD/Колода;
presentation_foundation141/2, turn_forecast_ui26/3 не повторены.

Чужие33: scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/;
не reset/stage/commit. Сохранить core/preview/queue/RNG/save/frozen,5 классов F5,
PLAYER вправо/ENEMY влево и возврат; каталоги1–3 не мигрировать. Один Godot runner,
isolated project; без root import, служб/драйверов, фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261111.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложи новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавай.
