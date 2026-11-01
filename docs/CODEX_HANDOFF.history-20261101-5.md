# Передача — 2026-11-01: облики и все классы на поле

D:/Games/into-de-dung; main; base f768d779af6991fb3b76bbcb2a85a78837b5e69a.
Результат: каталог4 — Разбойник/Маг/Воин у игрока, отсутствующие классы у врага.
Старые профили1–3 сохранены. Скины класса меняются только в хабе, отдельно от
profile7. Щитоносец02: idle1+редкий2/death3/ability2; Щитоносец17 и Воин11:
idle1/death3/ability2. PNG побайтные,330 кадров; новый арт не генерировался.
BT врагов выбирает персональные атаки/доступные классовые команды.
Core-команды/preview/queue/игровые RNG/frozen не изменены.

Владельцы поведения: CHARACTER_SKINS_V1, CLASS_SHOWCASE_V1;
маршрут — PROJECT_CONTEXT. [Отчёт и снимки](art/character-skins-20261101/README.md).
Runtime assets: assets/art_presets/approved/character_skins_v1/.
Логи/manifests/validation/review: test_reports/character-skins-20261101/.

Изолированный import/startup PASS, class223/0, skins208/0 headless и234/0 GPU,
hub23/0 и24/0 GPU, shield UI24/0; core9424/0; Python30/0; asset check PASS.
Смежные и независимое APPROVE — отчёт. turn_forecast_ui26/3 остаётся прежним.
Full suite не пройден. Полный lethal playback трёх skins проверен на ENEMY;
PLAYER — visual/sample, общая смерть — смежный suite. Тест не заменяет плейтест.

Далее — отзыв пользователя о скинах/стыках/посадке, ручные F5/движение/zoom/DPI.
Новый срез без поручения не начинать. Стабильные60 FPS не заявлены;
прежний [performance-остаток](performance/battle-magic-pacing-20261101.md) открыт.
Сохраняются прежние вопросы HUD/Колоды/художественной приёмки.

Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не reset/stage/commit;33 SHA сверены. Один Godot runner, isolated project;
без root import/служб/драйверов/принудительного фокуса. Без push/sidebar tasks/
расписаний. После коммита незакоммиченными остаются только указанные чужие пути.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261101-4.md), [HISTORY](HISTORY.md).

Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельным архивом+HISTORY. В финале/при блокере предложить
новый чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts,
остаток, ограничения, проверки и это же правило. Чат автоматически не создавать.
