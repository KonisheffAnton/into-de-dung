# Передача — 2026-11-08: скрытие значков и пробы вертикального HUD

D:/Games/into-de-dung; main; base763e8c76a217d6e8af191063edc0bc7eb5119099.
U уточнил: без hover скрывать не только подложку№4, но и сами значки.
Внедрено: весь ряд у фигуры (значки/числа/+N/панель) только при hover.
Selected/inspected его не удерживают. Bounds/picking/якорь прежние;
HP/броня/равновесие, воплощённые эффекты, карточка и осмотр не скрываются.
Владельцы: docs/BATTLE_PRESENTATION_REWORK.md, docs/BATTLE_HUD_SCENES_V1.md,
docs/ARCHITECTURE.md; выбор docs/ART_DIRECTION.md.

По отдельному запросу U показаны два P-макета: A — вертикальные HP/броня справа,
статусы постоянно снизу; B — нынешние полосы, постоянные статусы вертикально справа.
Пакет docs/art/status-hover-layout-20261108/: comparison.png,11 GPU PNG, исходники.
A/B НЕ внедрены; временный isolated-patch восстановлен побайтно. Нового арта нет,
спрайты/гамма прежние.1/3/5 эффектов и HP/броня — тестовые DTO, core/RNG неизменны.
Плотная группа показывает перекрытия: B сохраняет ширину чисел, A мельчит дроби.
Далее — выбор U; не начинать новые пробы или внедрение автоматически.

Отчёт test_reports/status-hover-layout-20261108/validation.json.
Свежие isolated import/startup PASS; GPU counter67/status158/icons442/vitals278
=945/0; headless18+96=114/0; mockup10 кадров+сравнение. Независимое APPROVE.
Diff/ссылки/точный архив/33 чужих файла PASS. Full/core и ручные F5/движение/zoom/
OS-DPI/performance не запускались; прежние hub/огонь/шипы/launcher не повторены.
План хаба docs/HUB_DESIGN_PLAN.md остаётся предложением H0–H5, реализация не начата;
его аудит62/0 сейчас не повторён.
Остаток: читаемость/стыки/посадка, край стрелы4 Лучницы, performance, HUD/Колода;
presentation_foundation141/2, turn_forecast_ui26/3 не повторены.
Чужие33: scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/;
не reset/stage/commit. Сохранить core/preview/queue/RNG/save/frozen,5 классов F5,
PLAYER вправо/ENEMY влево и возврат; каталоги1–3 не мигрировать. Один Godot runner,
isolated project; без root import, служб/драйверов, фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261108-14.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
