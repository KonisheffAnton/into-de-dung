# Передача — 2026-10-31: бюджет кадра с24 бойцами

D:/Games/into-de-dung; main; base e413a9e49e9fd4a5d60e674526645c579bb049d3.
Аудит владения порциями на main; завершающий refresh по стадиям;
публикации before/первого клипа и animated/technical after разделены.
Dirty redraw подсветки, batch меток, native sort, ограниченные action areas.
Полный аудит/fallback, контакт, fresh refresh без revision, skip/reset сохранены.
[Результат/метрики/остаток](performance/action-60fps-20261031.md).
Контракты: BATTLE_EXECUTION_UI, BATTLE_PRESENTATION_V1, BATTLE_VISUAL_SCENE_CONTRACT.

A/B3× в каждом режиме,24 бойца,24×16, реальные колода/экипировка/worker/render.
VSync p95 действий16.72–16.96мс; max движения20.048, атаки18.278мс.
Кадры>20мс34/195→1/259; uncapped p95≤14.411,max18.034,0/454>20.
Регулярные40мс устранены; строгие16.67мс каждый кадр не подтверждены.
В покое бывают20–22мс: причина не установлена; следующий шаг — длинный плейтест/trace.
PASS: импорт/разбор,25 suites/18878 assertions (core9424), launcher30/30;
независимое APPROVE. Логи/JSON: test_reports/action-60fps-20261031/.
Те же FAIL на e413a9e: presentation_foundation131/1 picking,
turn_forecast_ui26/3. Full и ручная F5/движение/zoom/DPI не заявлены.

Галерея6 воинов/72 клипа: docs/art/warrior-animation-six-20261031/README.md;
gallery.html локальный/ignored, восстановление build_gallery.py.
Генерации/расхода/интеграции нет. Стыки36 idle/ability, cutout и арт-приёмка открыты.
Прежние HUD/lifecycle/цвета17/11/Колода/упор остаются отдельной приёмкой.
Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
сохранены33/33 SHA; не reset/stage/commit. Без push/sidebar tasks/расписаний.
Core/preview/queue/RNG/save/frozen сохранены; новых правил боя нет.
Своих незакоммиченных после commit нет. Новый арт/интеграцию без поручения не начинать.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261031-6.md), [HISTORY](HISTORY.md).

Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельным архивом+HISTORY. В финале/при блокере предложить новый
чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts, остаток,
ограничения, проверки и это же правило. Чат автоматически не создавать.
