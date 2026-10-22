# Death-2 и новый эталон формата персонажей — 2026-10-23

Base `b2d78510f7c3216f01ebf9bbc32d3c4f4a878e7f`, ветка `main`.
U выбрал «death-2 — Колено, затем вперёд» и назначил этого воина эталоном
формата всех следующих персонажей.

Смерть подключена только к текущему вражескому Защитнику:
[ресурс/источники](../../../assets/art_presets/trials/enemy_warrior_death_v1/README.md),
[контракт](../../BATTLE_VISUAL_SCENE_CONTRACT.md#новый-вражеский-воин--2026-10-23).
17 PNG128² по150мс=2,55с, non-loop; исходные пиксели и первый кадр idle сохранены.
Тот же отражённый sprite/anchor(71,83)/ArtRoot0.8. Кадры ведёт общий Tween;
before сохраняется до завершения, затем штатный after/тело. Некорректный ресурс
даёт generic fallback. Падение за край/VOID/обвал сохраняют отдельный путь.

Новый [эталон](../../../assets/art_presets/approved/warrior_format_v1/README.md)
содержит исходник и рендер на тайле; [ART_DIRECTION](../../ART_DIRECTION.md#новый-эталон-формата-всех-персонажей--2026-10-23)
владеет стилем, пропорциями и правилами подготовки следующих персонажей.
Прежний эталон палитры сохранён как исторический. Массового изменения остальных
классов или новой генерации не было.

## Визуальное свидетельство

[Игровые кадры в GIF](death-2-in-game.gif) — рендер текущей сцены на тайле,
17×150мс, увеличено4×. GIF повторяется для просмотра; игровой SpriteFrames не зациклен.
Это отдельный visual fixture с фиксированными полосами, не запись настоящего боя.
[Стоя](death-01.png), [колено](death-09.png), [на земле](death-17.png).

[prepare_sources.py](prepare_sources.py) копирует выбранные исходники без правки,
проверяет SHA/alpha/128²/первый кадр и создаёт SpriteFrames/эталон.
[source-validation.json](source-validation.json):17 побайтных совпадений с исходным
PixelLab job и две точные копии изображений эталона.
[run_render_audit.py](run_render_audit.py) запускает
[render_audit.gd](render_audit.gd) на импортированном изолированном checkout;
проверяются все кадры, общая опора, mirror, root/ArtRoot/HUD/тень, alpha/reset.
[render-validation.json](render-validation.json) фиксирует SHA17 рендеров.

## Проверки и границы

Целевой набор: `python tools/demo/isolate.py --render-check --only defender_death
defender_death_routes defender_idle defender_buff rogue_death_routes presentation_contact
presentation_ranged presentation_mage presentation_consequences presentation_environment
visual_scene_contract unit_visual_contract --screen 0`.
Изолированный запуск `test_reports/demo-57aa0f420dd046aab691a26327e6165f/`:
13 PASS,1 FAIL,0 timeout; import/startup и все смежные проверки прошли,
новые assertions маршрутов потребовали исправления.
[Первый результат](initial-render-gate.json) сохранён, красный запуск не объявляется зелёным.

Второй импортированный snapshot `test_reports/demo-e511e79f6aac438f898cf2830fb52d90/`
использован для адресного повторения общего route-теста после исправления.
Исправлены перенос строки lambda, неверный legacy fixture, отсчёт от фактического
Tween progress и ожидания трансформов/публикации. Отдача меняет action_offset,
resize меняет масштаб клетки; тело может появляться на следующей границе receipt
после завершения клипа. [Диагностика до исправления](test-diagnostics.txt).
Runtime не менялся; побайтно проверены898 runtime/asset-файлов второго snapshot.
[Повторяемый запуск](rerun_routes.py), [итог](corrected-routes.json): parse PASS,
**Defender death routes889/0, Rogue death routes622/0**.
Успехи первого набора и исправленный route-тест дают14 зелёных итоговых проверок;
это агрегат совпадающих исходников, не новый полный прогон.

Проверены melee/ranged/mage и смерть enemy в цепочке, все17 кадров/тайминг,
before/after/тело, ускорение×3, resize, cancel/skip/stale Tween/retire,
null/неполный/zero-speed/null-texture fallback и fall/VOID/обвал без ground death.
Снимки состояния, RNG, counters и packet остаются неизменны при показе.
Отдельный render audit107/0, все17 кадров и GIF timing PASS. Максимальная
погрешность компонента ArtRoot от float —0,0000002384; root/HUD/тень неподвижны.
Независимый game_reviewer: **APPROVE**, блокирующих замечаний нет;
[границы и свидетельства ревью](review.md).
Runtime-команды/preview/live/worker/queue/RNG/save/frozen не изменялись.
Full/core, ручная F5/editor/DPI/GPU и приёмка игровых переходов не заявлены.
Художественный выбор варианта и нового эталона сделан U.
Чужие `scenes/demo/main_menu.tscn` и `docs/art/battlefield-reference-03-20261017/`
сохранены, не включаются в коммит. Без push.

[Проверка закрытия](closeout-validation.json):14 итоговых зелёных checks,
649 совпадающих runtime-файлов первого snapshot, точный архив HANDOFF,
проверенные локальные ссылки и хэш защищённой сцены. PROJECT_CONTEXT остаётся
в прежнем размере3557 символов при ориентире3500; индекс не менялся.
