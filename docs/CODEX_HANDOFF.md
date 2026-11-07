# Передача — 2026-11-07: рост языков29 и карты у нижнего края

D:/Games/into-de-dung; main; base0deb7c5ef9e2b2a083e353e5418d988c45cddef2.
HUD commit9d7ae928: убрана общая серая подсказка H1; карты у нижнего края.
Status/отказы/terminal/faulted сообщения выше руки сохранены. Контракт:
BATTLE_HUD_SCENES_V1. Свежий isolated demo-4be21bfba38a402b8880410cf3072793:
import/startup PASS, authoring310/0, input163/0, hero_hub_ui44/0,
mage_deck_ui140/0; active/terminal/faulted при1280×720, ревью APPROVE.
Предыдущие geometry failures и замеры — в отчёте этапа.

[Огонь29 — новый кандидат](art/fire29-growth-20261107/README.md): по отзыву U
языки дорисовываются наружу, вместо изгиба. PixelLab:3 completed jobs,
51 raw PNG,17 генераций (4359→4342). Выбраны7 raw поз motion01,12×120мс,
прямой/обратный показ без локальной деформации. Motion02 отклонён за цветовой
скачок. Новая палитра отличается от исходной; отдельные точки контура меняются,
монотонно растёт площадь, не каждый пиксель. Показ с соседями384×288 и128×96.
PNG/SHA/маска, оба lossless WebP и GPU capture PASS; техревью APPROVE. Арт-приёмка открыта;
кандидат НЕ внедрён, runtime-огонь/шипы прежние.
Отчёт test_reports/fire29-growth-hud-20261107/; raw/requests/selection — пакет.
Full/core, ручные F5/движение/zoom/DPI/performance не запускались.
Прежние проверки и APPROVE за пределами свежего набора не считать повторёнными.

Следующий шаг — отзыв U о новом росте огня и HUD; новый срез/генерацию не начинать.
Остаток: выбор/внедрение нового огня, стыки/посадка/читаемость, ручные проверки,
край стрелы способности4 Лучницы, performance; presentation_foundation141/2,
turn_forecast_ui26/3, HUD/Колода. Стиль персонажей — ART_DIRECTION2026-11-03.

Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не reset/stage/commit. Сохранять core/preview/queue/RNG/save/frozen,5 классов F5,
PLAYER вправо/ENEMY влево и возврат после атаки; каталоги1–3 не мигрировать.
Один Godot runner, isolated project; без root import, служб/драйверов,
принудительного фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261107-4.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный самодостаточный промпт: HEAD, результат, docs/artifacts, остаток,
ограничения, проверки и это же правило. Чат автоматически не создавать.
