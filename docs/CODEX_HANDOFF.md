# Передача — 2026-11-07: резкость цифр полос

D:/Games/into-de-dung; main; base ef72c0a04d45da97f5f3690ac059ee791b805460.
По U исправлены размытые цифры HP/брони: приватный Jersey20 без сглаживания,
целый экранный кегль/baseline, компенсация canvas/stretch и redraw при pan/zoom/resize.
Размеры/цвета полос, формат, общий урон над получателем и тайминг прежние.
Общий шрифт урона/HUD не менялся. Владелец: BATTLE_PRESENTATION_REWORK;
ARCHITECTURE/TESTING обновлены. Кадры docs/art/vitals-crisp-numbers-20261107/.

Свежие isolated import/startup PASS; current_art_zoom520/0, unit_visual45/0,
visual_scene106/0, contact327/0, consequences2096/0, environment364/0,
camera111/0, execution61/0 и запущенные арт-gates PASS.
Первый launcher23/2/0: status84/2 — прежние ошибки размеров поля; unit_vitals276/2
захватывал тень HP из-за неверного центра пробы. Исправлен только sampler,
повтор в isolated project: unit_vital_bars278/0. Negative control старого кода
246/32: все32 ошибки именно резкости; финальный код восстановлен побайтно.
GPU75/100/125/113% просмотрены, независимое ревью APPROVE.
Отчёт test_reports/vitals-crisp-numbers-20261107/;
runner demo-7137574fab1a4622bd49c2ec633a2d28, positive/negative-control.log в отчёте.
Full/core, ручные F5/движение/zoom/DPI/performance не запускались;
прежние проверки не считать повторёнными. Старый layout baseline здесь не повторялся.

Далее — отзыв U о резкости в текущем бою; художественная приёмка открыта.
Новые срезы без запроса не начинать. Принятый огонь29 natural02-middle сохранён:
docs/art/fire29-natural-integration-20261107/, ART_DIRECTION.
Остаток: стыки/посадка/читаемость, край стрелы4 Лучницы, performance;
presentation_status84/2, presentation_foundation141/2, turn_forecast_ui26/3, HUD/Колода.
Чужие33 файла: scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/;
не reset/stage/commit. Core/preview/queue/RNG/save/frozen сохранять;
5 классов F5, PLAYER вправо/ENEMY влево и возврат; каталоги1–3 не мигрировать.
Один Godot runner, isolated project; без root import, служб/драйверов,
принудительного фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261107-14.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
