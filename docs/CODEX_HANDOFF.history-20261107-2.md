# Передача — 2026-11-07: исправлена посадка выдвижной плиты

D:/Games/into-de-dung; main; base328fb508e7a9924772f64c71ad4d4303307fdffd.
U отклонил размер внедрённой плиты01. [Исправление](art/spike-tile-fit-20261107/README.md):
весь исходный верх подогнан к тайлу128×96, поля девяти гнёзд сохранены.
Три позы PixelLab, резкие40мс, after/hold700/retract100мс прежние.
Контракты: ENVIRONMENT_HAZARDS_V1/BATTLE_VISUAL_SCENE_CONTRACT.
Кальтропы03 внедрены ранее: два300мс блика за15,6с, неподвижный стык.
[Огонь29](art/fire29-readable-20261106/README.md), commit328fb508:
усилены4 из26 групп, частоты/фазы прежние; кандидат не внедрён.
Только кадры PixelLab; огонь24 не менялся. У края29 на95→0 небольшая
связанная кромка; художественная оценка открыта. Новых jobs нет.

Свежий isolated Godot import/startup PASS; hazards_ui118/0,
environment_visual_contract56/0: три позы, вершины/гнёзда, GPU alpha;
отрицательный контроль ловит старую обрезку. Builder --check PASS;
независимое техническое ревью APPROVE, снимки осмотрены.
Отчёты: test_reports/spike-tile-fit-20261107/ и demo-2dcbef2290f9480fa180f6ab8af2e070/.
Прежние проверки огня/кальтропов не повторены; предыдущий этап —
test_reports/fire29-spikes-20261106/. Full/core и ручные F5/движение/zoom/DPI/
performance не запускались. Технический PASS не означает приёмку U.

Следующий шаг — отзыв U о посадке шипов и огне29. Без нового среза,
генерации или внедрения огня. Остаток: стыки/посадка/качество показа,
F5/движение/zoom/DPI/performance, край стрелы способности4 Лучницы;
presentation_foundation141/2, turn_forecast_ui26/3, HUD/Колода.
Стиль персонажей ART_DIRECTION2026-11-03 сохранён.

Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не reset/stage/commit. Сохранять core/preview/queue/RNG/save/frozen,5 классов F5,
PLAYER вправо/ENEMY влево и возврат после атаки; каталоги1–3 не мигрировать.
Один Godot runner, isolated project; без root import, служб/драйверов,
принудительного фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261107.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
