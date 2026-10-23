# Новая модель разбойника и Смерть 3 — 2026-10-23

Base `719fc6af81689ccf0bd4927a3f90350119e95bd4`, ветка `main`.
Поручение U: «реализуй смерть3, и вообще модельку разбойника пока поменяй».
Подключены выбранный зелёный рисунок и Death3 из последней серии PixelLab.
Обе фракции используют [новый пакет](../../../assets/art_presets/trials/rogue_selected_v1/README.md).
Воин warrior_format_v1/idle-1/death-2 и остальные классы сохранены.

Исходные18 PNG скопированы без изменения байтов:128² RGBA, первый кадр равен
статичной позе. Фигура66×72, ArtRoot0.8, своя опора(64,83); обе модели имеют
исходную высоту72px. Враг отражает только рисунок. Цвета исходные, старые
маски одежды к новой геометрии не применяются; индекс выбора сохраняется.
Точные правила — [visual contract](../../BATTLE_VISUAL_SCENE_CONTRACT.md#анимации-разбойника).

Death3 содержит17 кадров по150мс=2.55с; прежние hold0.25/fade0.80 сохранены,
итого3.60с. After и generic corpse публикуются по прежнему общему Tween.
Смерть фактически вперёд-вправо, у врага зеркально. Idle пока не выбран;
персонаж стоит статично, guard использует общее представление без старой B1.

## Визуальные свидетельства

- [Разбойник рядом с воином в одинаковом масштабе тайла](rogue-warrior-in-game.png).
- Смерть в сцене: [союзник](death-3-player.gif), [враг](death-3-enemy.gif).
- [Обычная защита в настоящем экране боя](corrected-captures/rogue_buff/rogue-guard-generic.png).

GIF — повторяющиеся рендеры fixture на тайле с фиксированными полосами, не
запись боя. Они показывают17 кадров, hold и fade; игровая смерть не зациклена.
Render audit проверяет обе стороны, опору, ArtRoot/root/HUD/тень, отсутствие
добавленной деформации и восстановление alpha. Ручная оценка масштаба/переходов
остаётся открытой: одинаковая высота исходника не гарантирует одинаковый вес силуэта.

## Проверки

`python tools/demo/isolate.py --render-check --only current_art_zoom rogue_animations
rogue_buff rogue_death_routes presentation_contact presentation_ranged presentation_mage --screen 0`

Первый изолированный прогон `test_reports/demo-8bcaab2e70644192a4a5f6c922189d26/`:
24 PASS,1 FAIL,0 timeout. [Исходный итог](initial-gates.json) сохранён.
Ошибка в новом guard fixture: внешний player не держал execution_pending,
поэтому resize удалял cue через _clear_falls; тест также ожидал одну публикацию
вместо штатных frame.after+final. [Исходный лог](initial-rogue-buff.log).
Исправление удерживает production-блокировку и проверяет cue после resize/render.

[Адресный повтор](rerun_checks.py) сверил919 runtime/scene/asset-файлов поSHA
с первым snapshot, затем обновил только два проверочных файла.
[Итог](corrected-checks.json): Rogue guard31/0, Defender buff299/0.
Вместе с неизменными PASS первого прогона — **25 итоговых зелёных checks**;
это агрегат адресных проверок, не повторный полный прогон.
Rogue animations98/0, death routes832/0, cloth148/0, current art zoom500/0.
Import/startup, соседние классы и presentation contact/ranged/mage/environment/
consequences, UI/lifecycle также PASS — полный перечень в [итоге](final-checks.json).

Первый render fixture пропустил Role.UNIT до ready: отсутствовали HUD/тень,
процесс остановлен по90с timeout; [диагностика](initial-render-audit.txt).
После исправления [render audit](render-validation.json) **333/0**, обе стороны
и GIF3.60с PASS. [Запуск](run_render_audit.py), [fixture](render_audit.gd).
[Подготовка](prepare_sources.py), [SHA/alpha](source-validation.json).

Независимый game_reviewer **APPROVE**; [границы ревью](review.md).
Ведущий сверил общий Tween, сохранение before до завершения, затем after/тело,
cancel/skip/retire и отдельный fall/VOID/обвал по коду и route-тестам.
Full/core, ручные F5/editor/DPI/GPU и художественная приёмка не заявлены.
Базовые игровые механики, preview/live/worker/queue/RNG/save/frozen не менялись.
Чужие main_menu.tscn и32 файла battlefield-reference сохранены и не входят в коммит.
Локальный Conventional Commit, без push/sidebar/расписаний.
[Проверка закрытия](closeout-validation.json), [точный архив передачи](handoff-archive.json).
