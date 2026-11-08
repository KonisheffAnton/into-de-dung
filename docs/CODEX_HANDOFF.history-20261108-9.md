# Передача — 2026-11-08: подложка только при наведении

D:/Games/into-de-dung; main; basee76bd01a5f875a039d8d5712c79282ee76c71ddd.
По U общая деревянная подложка с железным краем появляется под рядом состояний
только при hover на живой фигуре/значках. Уход курсора/смерть/пустой ряд скрывают её;
выбор/карточка сами не удерживают. Значки A и числа10px всегда видны, без отдельных
плашек; стаки слева сверху, срок справа снизу. Позиции не сдвигаются.
Ряд входит в общий выбор по глубине вместе с телом; только опубликованные DTO.
Панель переиспользована через assets/ui/status_hover_panel.tres; новых генераций нет.
Гамма/полосы/механики прежние; ПКМ-карточка, область42px, поле/рука сохранены.
Выбор: docs/ART_DIRECTION.md; показ: docs/BATTLE_PRESENTATION_REWORK.md
и docs/BATTLE_HUD_SCENES_V1.md.
Пары idle/hover75/100%: docs/art/status-icon-frame-20261108/.
Ресурсы: assets/art_presets/approved/status_icons_a_v1/ и status_icons_framed_v1/.
Отчёт: test_reports/status-hover-backing-20261108/validation.json.

Свежие isolated import/startup PASS; counter34/0, status158/0, icons418/0,
vital278/0, hud_input163/0, visual_scene106/0 =1157/0; headless status96/0+counter4/0.
Hover on/off, пустой ряд, смерть, попадание по краю, перерисовка/геометрия PASS.
H1-кадры — тестовые DTO, не сыгранный статусный бой; независимое APPROVE.
Diff, ссылки, архив HANDOFF и33 чужих файла PASS. Предыдущие builders/launcher/
огонь/шипы/прочие HUD gates и APPROVE не повторены. Full/core, ручные F5/мышь/
движение/zoom/DPI/performance не запускались.

Далее — отзыв U; новые пробы/срезы без запроса не начинать. Остаток: стыки/посадка,
край стрелы4 Лучницы, performance, HUD/Колода; presentation_foundation141/2,
turn_forecast_ui26/3 не повторены.
Чужие33: scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/;
не reset/stage/commit. Сохранить core/preview/queue/RNG/save/frozen,5 классов F5,
PLAYER вправо/ENEMY влево и возврат; каталоги1–3 не мигрировать.
Один Godot runner, isolated project; без root import, служб/драйверов,
принудительного фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261108-8.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
