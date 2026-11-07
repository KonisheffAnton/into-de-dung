# Передача — 2026-11-07: карточка персонажа справа

D:/Games/into-de-dung; main; base012db0a08eb19e22287b5abb170dd342eee74695.
По U внедрена карточка300px справа поверх поля, выше руки; собственная прокрутка.
Союзник выбирается+открывает сведения, обычный клик по врагу открывает карточку
без смены союзника. Явная атака/магия сохраняет цель; крестик закрывает только UI.
HP/броня/запас равновесия, действия, характеристики, состояния, свёрнутые свойства.
После действия ресурсы/статусы из показанного DTO, без чтения занятого runtime.
Общая гамма/окружение/персонажи не менялись. Прежние полосы/урон/огонь сохранены.
Владелец BATTLE_HUD_SCENES_V1; TACTICAL_BATTLE/ARCHITECTURE/TESTING обновлены.
Кадры docs/art/character-card-20261107/; отчёт test_reports/character-card-20261107/.

Свежие isolated import/startup PASS; character_card98/0, HUD input163/0,
HUD authoring370/0, inspection text126/0, camera111/0, execution61/0.
Launcher6/2/0: устаревший click-through и ошибки нового fixture; focused PASS.
Runner demo-e43fcf3cdc9b4d13900911aac246b128; card-final.log в отчёте.
GPU main/H1 при1440×1000 и1280×720; пять классов проверены; независимое APPROVE.
Full/core, ручные F5/движение/zoom/DPI/performance не запускались.
Старые presentation_status84/2, foundation141/2, turn_forecast_ui26/3 не повторялись.

Следующий шаг — отзыв U о карточке в текущем бою; новые срезы без запроса не начинать.
Остаток: стыки/посадка/читаемость, край стрелы4 Лучницы, performance, HUD/Колода,
прежние проверки выше. Огонь29: docs/art/fire29-natural-integration-20261107/.
Чужие33 файла: scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/;
не reset/stage/commit. Сохранить core/preview/queue/RNG/save/frozen,
5 классов F5, PLAYER вправо/ENEMY влево и возврат; каталоги1–3 не мигрировать.
Один Godot runner, isolated project; без root import, служб/драйверов,
принудительного фокуса, push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261107-16.md), [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельно+HISTORY. В финале/при блокере предложить новый чат
и полный промпт: HEAD, результат, docs/artifacts, остаток, ограничения,
проверки и это же правило. Чат автоматически не создавать.
