# Передача — 2026-11-22: С2 и посадка троглодита

D:/Games/into-de-dung; main. Код проверен на7b98b01c + только этот срез;
параллельный docs-коммит80cf5c42 сохранён, его runtime-работа не включена.
U заменил смерть наС2 и указал на парение/тень. Подключён точный PixelLab death-2;
якорь128/184 опускает фигуру на6.4px при100%, тень расширена×1.25 под лапами.
Размер~⅔ воина, О3/О2/Р2, пиксели и палитра прежние. Другие скины имеют×1.
[Владелец](TAMED_TROGLODYTE_V1.md), [С2/кадры/проверки](art/troglodyte-grounding-c2-20261122/README.md).
33 кадра С2 точно совпадают с исходниками; сборка --check PASS.

Чистый detached worktree+isolated runner: import/startup и4 visual suites PASS,
1622/0 (unit_visual_contract45, class_showcase_ui60, character_skins1475,
tamed_troglodyte_visual42). Независимые code/GPU reviews APPROVE.
Кадры проверяют тень/лапы/плитку, обе стороны,2:1/4:3 и позу С2.
Снимок С2 использует живой test unit и сохраняет его HP-полоску; это проверка
геометрии, а не финального HUD после смерти. Full/core, ручной F5-бой,
DPI/performance не повторены. Следующий шаг — художественная приёмка U.

Боевые правила троглодита/останков прежние; владелец TAMED_TROGLODYTE/ENVIRONMENT_D5.
Сохранять правило брони у фигуры,5 классов F5, PLAYER вправо/ENEMY влево,
пробу2:1 с возвратом4:3. Инициативы нет; core/queue/preview/RNG/save/frozen сохранять.
Выбор носителя/огонёк и две карты — по DESIGN_DIRECTION§3.2.1; отдельный
параллельный runtime-пакет ещё dirty, не включать и не считать проверенным этим срезом.
Чужие main_menu.tscn, battlefield-reference-03-20261017/ и host-card правки
не reset/stage/commit. Полный git status обязателен. Без push/sidebar/расписаний.
Один isolated runner, без root import. Остатки D:/Games/trog-grounding-check-20261122
оставлены: git cleanup встретил long path, следующий delete отклонён автопроверкой.
Отчёты сохранены в test_reports/troglodyte-grounding-c2-20261122/.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261122-7.md) + HISTORY.
После этапа/при блокере предложить новый чат и полный промпт: HEAD, результат,
docs/artifacts, остаток, ограничения, проверки и это же правило передачи.
Прежний HANDOFF архивировать побайтно отдельно со ссылкой из HISTORY;
чат автоматически не создавать.
