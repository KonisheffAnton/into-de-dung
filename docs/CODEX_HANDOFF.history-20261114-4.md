# Передача — 2026-11-14: прокрутка отряда

D:/Games/into-de-dung; main; base926a3afaef5dccced380c572fbc1d9bf07d493bb.
U: отряд слева, диорама в центре, подготовка справа. Drag меняет порядок;
клик открывает иконки своих героев (отряд+резерв) для выбора.
Приняты прокрутка списка слева и автопрокрутка у края при drag.
Карточки равной высоты; портрет/имя/класс/уровень, снизу броня/очки,
оба признака вместе при наличии; у готового строка пустая.
UI предусматривает5–6 героев; точный максимум — Q, игровые лимиты прежние.
Владельцы: docs/HUB_DESIGN_PLAN.md §3/§7/§8; docs/DESIGN_DIRECTION.md §6.1.
Маршрут: docs/HUB_SCENES_V1.md. Порядок ходов выбирает игрок; инициативы нет.
Вкладки+диорама сначала, здания позже; H0→H1→H4 только по поручению.
Осталось: геометрия/фигуры, матрица3/5/6, названия/школы/материалы.
Изменены документы; реализация хаба и генерация не начаты.

Принятый макет6, кадр, QA: test_reports/hub-scroll-choice-20261114/.
При примерке Edge synthetic drag/autoscroll/picker/keyboard/demo PASS,
статическое ревью APPROVE; это не Godot или реальный pointer/reader.
Свежие diff/ссылки/объём/точный архив/чужие33 PASS. Godot не запускался.
Аудит: docs/art/hub-ux-audit-20261108/; полная матрица размеров ещё впереди.

Бой: hover-only статусы над бронёй, до3/+N; HP/броня48×9 с1px отступа цифр.
Постоянный ряд C не принят; ждёт отзыва U в бою.
docs/art/status-readability-20261111/; test_reports/status-readability-20261111/.
Прежние import/startup/suites/RGBA/core/RNG/APPROVE не повторены.
Full/core, ручные F5/движение/zoom/OS-DPI/usability/performance не запускались.
Остаток: читаемость/стыки/посадка, край стрелы4 Лучницы, performance, HUD/Колода;
presentation_foundation141/2, turn_forecast_ui26/3 не повторены.

Чужие33: scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/;
не reset/stage/commit. Core/preview/queue/RNG/save/frozen,5 классов F5,
PLAYER вправо/ENEMY влево и возврат сохранить; каталоги1–3 не мигрировать.
Один Godot runner, isolated project; без root import, служб/драйверов,
принудительного фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261114-3.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit своих изменений,
короткий HANDOFF; прежний побайтно отдельно+HISTORY. В финале/при блокере
предложить новый чат и полный промпт: HEAD, результат, docs/artifacts, остаток,
ограничения, проверки и это же правило. Чат автоматически не создавать.
