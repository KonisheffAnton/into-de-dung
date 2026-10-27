# Передача — 2026-10-27: два каменных набора в первой комнате

D:\Games\into-de-dung; main; base9fa99063ed96efbfa8dbeff95dbd6dd05d2d730a.
По U внедрены два полных листа по24 элемента, а не два отдельных тайла пола:
первая комната похода, layer0, колонки0–3 — первый/темнее, 4–7 — второй/светлее.
Парные половины имеют одинаковую раскладку пола. PNG побайтно сохранены;
UV читают пол и кладку. Геометрия128×96/4:3, высоты, picking, расстановка,
ядро и остальные комнаты прежние. Новых игровых предметов из листов нет.
[Контракт](BATTLE_VISUAL_SCENE_CONTRACT.md#сравнение-каменных-наборов-в-первой-комнате),
[исходники/промпты/снимки](art/dungeon-room-comparison-20261027/README.md),
[ресурсы](../assets/art_presets/trials/dungeon_comparison_v1/README.md).

Финальный render-check:5 PASS,0 FAIL,0 TIMEOUT — import/startup,
dungeon_room_comparison532/0, visual_scene_contract52/0, battle_camera_ui110/0.
Прогон:test_reports/demo-c35b12f70f3c49f9b4eaea7cfeab2e93/.
Launcher30testsOK; оба PNG byte-exact. Отчёт и SHA:
test_reports/dungeon-room-comparison-20261027/. Независимое ревью APPROVE; 19 SHA патча совпали.
Полный/core/F5, отдельная DPI/GPU-приёмка не запускались.
Остаток: отзыв U о двух половинах, ручная F5/движение/zoom/DPI и выбор набора.

Прежние Play Bold+Jersey20 и разворот атакующих не менялись;
их ручная F5-приёмка открыта. Подробности — [прежняя передача](CODEX_HANDOFF.history-20261027-14.md).
Очистка арта отложена U; отзывы о Колоде/одиночном упоре открыты.

Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
сохранены dirty; не трогать/reset/stage/commit. 33 защищённых SHA совпали.
Старый reference01 не удалён: sandbox ошибочно показывал D из-за отказа чтения.
Core/preview/queue/RNG/save/frozen сохранять; без push/sidebar tasks/расписаний.
Новый этап автоматически не начинать. [HISTORY](HISTORY.md).
Завершение: проверки, локальный Conventional Commit, короткая передача;
прежнюю побайтно отдельным архивом+HISTORY. В финале/при блокере предложить новый
чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts, остаток,
ограничения, проверки и это же правило. Чат автоматически не создавать.
