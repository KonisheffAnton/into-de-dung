# Передача — 2026-11-14: выбран отряд слева

D:/Games/into-de-dung; main; basea4e757a4107bed48e9a2a8f13ecab076c2df60c4.
U оставил отряд слева, диораму в центре, подготовку справа.
Перетаскивание карточек меняет порядок; клик открывает экран с иконками
всех своих героев (отряд+резерв) для выбора. Подробности и границы —
docs/HUB_DESIGN_PLAN.md §3; решение — docs/DESIGN_DIRECTION.md §6.1.
Порядок ходов по-прежнему выбирает игрок; инициативы нет.
Вкладки+диорама «Поход» сначала, кликабельные здания позже; H0→H1→H4.
Композиция принята, размеры/содержимое карточек, названия/школы/материалы P/Q.
Изменены только документы; реализация хаба, H2/H3/H5 и генерация не начаты.
Далее — уточнение этих деталей; реализацию автоматически не запускать.
Маршрут: docs/HUB_SCENES_V1.md; аудит docs/art/hub-ux-audit-20261108/.

Эскиз и прежний browser QA: test_reports/hub-composition-choice-20261114/.
Данные/значки условные. Headless Edge: synthetic drag/keyboard, DOM-клики,
замена/обмен, подавление клика, Esc/focus PASS; это не Godot-проверки.
Свежие diff/ссылки/объём/архив/чужие33 PASS; validation.json там же.

Сохранён результат прошлого этапа: горизонтальные hover-only статусы над
бронёй, пять полевых SVG, до3/+N и подложка№4; рамочные24 PNG прежние.
HP/броня48×9 экранныхpx, цифры с1px свободной заливки до рамки.
Постоянный ряд C не принят; далее — отзыв U в бою.
docs/art/status-readability-20261111/; test_reports/status-readability-20261111/.
Прежние hub/battle import/startup, suites, RGBA/core/RNG и APPROVE не повторены.
Full/core, ручные F5/движение/zoom/OS-DPI/usability/performance не запускались.
Остаток: читаемость/стыки/посадка, край стрелы4 Лучницы, performance, HUD/Колода;
presentation_foundation141/2, turn_forecast_ui26/3 не повторены.

Чужие33: scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/;
не reset/stage/commit. Core/preview/queue/RNG/save/frozen,5 классов F5,
PLAYER вправо/ENEMY влево и возврат сохранить; каталоги1–3 не мигрировать.
Один Godot runner, isolated project; без root import, служб/драйверов,
принудительного фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261114.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit своих изменений, короткий
HANDOFF; прежний побайтно отдельно+HISTORY. В финале/при блокере предложить
новый чат и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
