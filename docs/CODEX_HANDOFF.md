# Передача — 2026-11-03: idle и размер Лучницы

D:/Games/into-de-dung; main; base b6c596789288567f989b8e339dd14846c46a4c9f.
По U Лучнице14-04 заменены основной idle1→2, дополнительный5→4.
После отзыва о крупной фигуре размер уменьшен на10%: ArtRoot0.8→0.72.
Смерть3/способность4 сохранены; Маг и прочие модели не менялись.
Владелец: [CHARACTER_SKINS_V1](CHARACTER_SKINS_V1.md).
[Отчёт, снимки, validation/review](art/archer-idle-scale-20261103/README.md).
Логи: test_reports/archer-idle-scale-20261103/; headless:
test_reports/demo-9aafd6ba1ed04ffb9cd25b6ff860fc9f/.

PASS isolated import/startup; skins1074/0 headless,1130/0 GPU;
mage_archer_skins415/0 в обоих режимах. GPU zoom496/0, UI47/0,
coverage53/0. Сборщик43 результата/27 PNG/693 ячейки; новые листы побайтно,
37 остальных PNG/TRES и33 чужих файла сохранены. Независимое APPROVE — review.md.
Кадры/опора/направления/полное покрытие сохранены; пикинг и эффекты следуют размеру.
Root import/full/core не запускались. Ручная оценка размера и стыков открыта.

Стиль зафиксирован в [ART_DIRECTION](ART_DIRECTION.md); это не закрывает
ручные F5/движение/zoom/DPI, точную посадку и качество показа на поле.
Край стрелы способности4 Лучницы сохранён без автоматической ретуши.
Прежний остаток: presentation_foundation141/2, turn_forecast_ui26/3,
performance, HUD/Колода. Прежние проверки не считать повторёнными.
Дальше — отзыв/поручение пользователя; новый срез/генерацию не начинать.

F5 ровно5 классов; PLAYER вправо/ENEMY влево, атака поворачивает к цели
и возвращает сторону команды. Каталоги1–3 и legacy-fallback не мигрировали.
Сохранять core/preview/queue/RNG/save/frozen.
Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не reset/stage/commit. Один Godot runner, isolated project; без root import,
служб/драйверов/принудительного фокуса/push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261103-5.md), [HISTORY](HISTORY.md).

Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельным архивом+HISTORY. В финале/при блокере предложить
новый чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts,
остаток, ограничения, проверки и это же правило. Чат автоматически не создавать.
