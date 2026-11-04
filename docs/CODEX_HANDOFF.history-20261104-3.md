# Передача — 2026-11-04: кислота05/01 без камня

D:/Games/into-de-dung; main; base55d9605ec0473a99ffa243a521b1239ba1962d29.
По U анимация01 внедрена в текущую сцену: отдельное покрытие верхнего ромба,
33 кадра/10FPS, без привязки к материалу пола. Собственные боковины сохранены.
[Результат/снимки/review](art/acid01-integration-20261104/README.md),
[визуальный контракт](BATTLE_VISUAL_SCENE_CONTRACT.md),
[поведение](ENVIRONMENT_HAZARDS_V1.md). Исходные360 арт-файлов не изменены.
Эталон — art/current-tile-reference-20261103/; исходная серия —
art/acid05-animation-20261103/. Выбор01 принят U; новая художественная приёмка открыта.

PASS: builder/compile, launcher37; isolated import/startup;
headless acid_animation92/0, visual_scene106/0, acid56/0;
GPU acid_animation194/0, environment32/0, visual_scene106/0, dungeon1983/0.
Все33 маски/отрицательный контроль, шесть биомов, snapshot/RNG; review APPROVE.
GPU hazards_ui105/2: те же два сбоя завершения шипов на base и current-repeat.
Headless environment31/1 — GPU pixel test; GPU32/0. Это не полностью зелёный suite.
Отчёты: test_reports/acid01-integration-20261104/;
demo-ce9c4ce9228e414693577ee02b06d800 и demo-92fd62445c924aeebe5cf35497debee8.
Full/core/root import и ручной F5 не выполнялись; прежние APPROVE не повторены.

Следующий шаг уже поручен U: нарисовать20 новых версий огня, экспериментируя
со стилем; отдельный прозрачный эффект и показ на эталоне, без внедрения до выбора.
Остаток: ручные F5/движение/zoom/DPI, стыки/посадка/качество, performance,
край стрелы способности4 Лучницы; presentation_foundation141/2,
turn_forecast_ui26/3, HUD/Колода и hazards_ui105/2.
33 чужих файла сохранены: scenes/demo/main_menu.tscn и
docs/art/battlefield-reference-03-20261017/ не reset/stage/commit.
Сохранять core/preview/queue/RNG/save/frozen, пять классов F5,
PLAYER вправо/ENEMY влево и возврат после атаки; каталоги1–3 не мигрировать.
Один Godot runner, isolated project; без root import, служб/драйверов,
принудительного фокуса/push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261104-2.md), [HISTORY](HISTORY.md).

Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельным архивом+HISTORY. В финале/при блокере предложить
новый чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts,
остаток, ограничения, проверки и это же правило. Чат автоматически не создавать.
