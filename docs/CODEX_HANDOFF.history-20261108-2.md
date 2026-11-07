# Передача — 2026-11-08: стабильный блок подсказок

D:/Games/into-de-dung; main; base6f3cb90436ebce5fc038bbe7a1160efc1a032570.
По U убраны DeckSummary и обычная жёлтая инструкция. Hint/Status резерв44px,
Inspection — RichText42px без роста; поле/камера/рука не прыгают от статусов.
Полное описание — tooltip/карточка. Статусы: кровотечение красное, путы коричневые,
оглушение белое, яд тёмно-зелёный, кислота кислотно-зелёная; контур для читаемости.
Единая палитра нижнего осмотра/карточки; published DTO и guards прежние.
Общая гамма, механики, полосы/урон/огонь29 не менялись.
Владельцы BATTLE_HUD_SCENES_V1 и ART_DIRECTION; ARCHITECTURE/TESTING обновлены.
Кадры docs/art/stable-status-hud-20261108/;
отчёт test_reports/stable-status-hud-20261108/.

Свежие isolated import/startup PASS; presentation_status136/0 (две прежние layout
ошибки устранены), card105/0, input163/0, authoring370/0, camera111/0,
execution61/0, mage_presenter164/0, mage_deck_ui141/0; GPU main/H1, пять цветов.
Golden мага:14 намеренных visibility +22 старых height; baselineHEAD подтвердил300.
Финал verified-checks.json; runner demo-ca72cb79a5074dc6b73fc73f96227f4d.
Независимое ревью APPROVE. Full/core, ручные F5/движение/zoom/DPI/
performance не запускались. Прежние foundation141/2 и turn_forecast_ui26/3 не повторены.

Далее — отзыв U в текущем бою; новые срезы без запроса не начинать.
Остаток: стыки/посадка/читаемость, край стрелы4 Лучницы, performance, HUD/Колода.
Карточка: docs/art/character-card-20261107/; огонь29: docs/art/fire29-natural-integration-20261107/.
Чужие33: scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/;
не reset/stage/commit. Сохранить core/preview/queue/RNG/save/frozen,
5 классов F5, PLAYER вправо/ENEMY влево и возврат; каталоги1–3 не мигрировать.
Один Godot runner, isolated project; без root import, служб/драйверов,
принудительного фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261108.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
