# Передача — 2026-11-14: утверждённый хаб

D:/Games/into-de-dung; main. База9bddbc2064a2fe39a4d6909f51ccc0e00db43781;
Предыдущий HEAD886acfe76d872843a9910a9fe17cba288854e5dd (параллельный арт).
По U реализованы вкладки/ресурсы, Поход: отряд слева, drag/автопрокрутка,
выбор своих героев/замена/обмен; диорама с idle/static; подготовка справа,
советы/переходы, блокер черновика колоды, неподвижная «В путь».
Наёмники: Мои герои/Найм, портреты слева, герой в центре, осмотр справа;
круглые пассивки/квадратные способности, hover/focus/click-подсказки.
UI проверен3/5/6; фактический максимум3 сохранён, будущий лимит Q.
Владельцы: HUB_SCENES_V1, HERO_HUB_H1, HUB_DESIGN_PLAN, ARCHITECTURE.
Пакет: docs/art/hub-approved-implementation-20261114/ (8GPU PNG);
отчёт: test_reports/hub-approved-implementation-20261114/.

PASS isolated import/startup,14 targeted suites8431/0, launcher37/0,
21новый GPU кадр,500 переключений без роста узлов, независимое APPROVE.
Первичные ошибки/FAIL сохранены; исправленные проверки повторены PASS.
Soak: по5мин static/animated1280×850,293→293 узла; CPU диорамы p950,274мс.
Полный frame p9518,231/18,350мс: цель16,7мс не достигнута, стабильные60FPS
не заявляются; метод/CPU/GPU/память — performance.md в отчёте.
Full/core, ручные F5/движение/zoom/OS-DPI и usability не запускались.

Следующий шаг — отзыв U и ручной проход хаба/посадка/читаемость.
Здания/другие диорамы/новая экономика/школы отдельно; автоматически не начинать.
Бой: status-readability-20261111 ждёт U; стыки/стрела4 Лучницы/performance,
HUD/Колода остаются; presentation_foundation141/2 и turn_forecast_ui26/3 не повторены.
Арт соседнего этапа: docs/art/hobgoblins-ten-20261114/ и
warrior-attack-single-five-20261114/ — выбор/масштаб/стиль/швы ждут U, без внедрения.
Чужие main_menu.tscn и docs/art/battlefield-reference-03-20261017/ не stage/reset;
33файла побайтно сохранены. Core/preview/queue/RNG/save/frozen,5классов F5,
PLAYER вправо/ENEMY влево и возврат после атаки прежние; инициативы нет;
каталоги1–3 не мигрировать. Один Godot runner, isolated project;
без root import/служб/драйверов/фокуса ОС/push/sidebar tasks/расписаний.
[Прежняя передача побайтно](CODEX_HANDOFF.history-20261114-12.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
