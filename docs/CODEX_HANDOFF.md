# Передача — 2026-10-17: палитра всех текущих персонажей
D:\Games\into-de-dung; main; base821e12a9f76657740be150ee639da1b9feb6ace0.
U: применить выбранную чуть более яркую палитру стражника ко всем персонажам.
[Внедрение/сравнение](art/character-brighter-palette-20261017/README.md): общий RGB
shader в art_trial_unit для Защитника, Разбойника, Лучницы, обеих сторон,
всех их кадров и запасных фигур/помощников. Исходные PNG/alpha/anchors/тайминги
сохранены. Маски одежды работают; Archer cloth_enabled=false. Default strength0
сохраняет старые пресеты. Это перенос характера палитры, не точная ImageGen LUT.
Источник — [проба стражника](art/defender-brighter-palette-20261017/README.md);
эталонный PNG не заменён. Новых генераций/PixelLab нет.
Чистый render gate21/0, current_art_zoom460/0; import/startup и visual gates PASS.
Render-аудит160/0: alpha совпадает, RGB/средняя светлота изменены. Ревью APPROVE.
Первый gate20/1 выявил ошибку texture-секции; исправление проверено чистым повтором.
Отчёты: test_reports/demo-ca10bb0d177e4e78b349c4543c312508/, validation/review пакета.
Full/core, ручной F5/editor/DPI/GPU-матрица/художественная приёмка не выполнены.
Дальше только отзыв U по виду в игре; следующий этап автоматически не запускать.
[Idle A/B](art/cutout-idle-20261017/README.md) остаются отдельной пробой:
разворот нормальный, замечание было к высоте камеры; приёмка движения/ракурса открыта.
Серии04/05 сохранены с оценками каждого монстра; выбора нет. Без подставок/видов со спины.
Серия03 остановлена, untracked, manifest/validation устарели — не возобновлять.
Чужой scenes/demo/main_menu.tscn не трогать/reset/stage/commit; hash сохранён.
Сохранять core/preview/live/worker/queue/RNG/save/frozen. Без push/sidebar/расписаний.
Контракты: [ART](ART_DIRECTION.md), [показ](BATTLE_PRESENTATION_REWORK.md), [API](GRAPHICS_WORKFLOW.md).
Прежний HANDOFF побайтно: [архив](CODEX_HANDOFF.history-20261017-6.md), [HISTORY](HISTORY.md).
После этапа — Conventional Commit и короткий HANDOFF; прежний побайтно в отдельный
архив+HISTORY. В финале/при блокере предложить новый чат и полный промпт блоком:
HEAD, результат, docs/artifacts, остаток, ограничения, проверки и это же правило.
Чат автоматически не создавать; ссылка не заменяет текст. Правило переносить дальше.
