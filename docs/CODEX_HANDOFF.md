# Передача — 2026-10-31: бой32 и test planner

D:/Games/into-de-dung; main; base 0483b7243563075c4eed256769c1876241130077.
Стабильные 60 FPS НЕ достигнуты. Пользователь ушёл, разрешил автономную работу
и остановку при неразрешённом вопросе; новых запросов к нему не ожидается.
[Результат и ограничения](performance/battle-foreground-soak-20261031.md),
[системная трасса](performance/battle-system-trace-20261031.md).

В нагрузочном тесте убрана синхронная предварительная validate; строгий допуск
остаётся в штатном worker. Retry только свежего REJECTED, guards pending/owner,
новый receipt и join перед итоговыми чтениями. Runtime/настройки игры не менялись.
Core/preview/queue/RNG/save/frozen сохранены.

Четыре пятираундовых боя32: по 53 PASS/0, минимум29 живых, массовые DOT/огонь,
все записанные кадры с фокусом. Planner max снизился с88,201 до17,962–19,282мс.
Автономные display-пики:25,399/65,1454мс в окне;33,3562мс в fullscreen-контроле.
Запрос fullscreen в68b832f1 не применился; действительный mode4 — aa1534bf.
Present path остался Hardware Composed Independent Flip. Подробнее и границы
CSV-выборок — в отчёте; точного Godot↔QPC сопоставления/визуальной приёмки нет.
Пользователь за анимациями не наблюдал.

Артефакты: test_reports/battle-frame-pacing-20261031/:
focused-soak32-e27f5b66*, autonomous-soak32-{66860c21,68b832f1,aa1534bf}*,
autonomous-soak-comparison.json, foreground-stage-{review.md,validation.json}.
Godot import/startup/planner PASS (61 проверка), launcher unit30/30;
независимое APPROVE кода, диагностические выводы с ограничениями.

Дальше нужен обоснованный разбор остаточных пиков; новой runtime-правки нет.
Дополнительный ETW-сбор получил ACCESS_DENIED; обхода/автоповышения прав нет.
Один GPU runner, isolated project; не root import. Собственные сборы завершены.
Новых full/core/F5/движение/zoom/DPI/другой GPU проверок нет. Прежние
HUD/lifecycle/цвета/Колода/арт-приёмка открыты. Без нового арта/интеграции.
Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не reset/stage/commit. Без push/sidebar tasks/расписаний.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261031-13.md), [HISTORY](HISTORY.md).

Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельным архивом+HISTORY. В финале/при блокере предложить новый
чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts, остаток,
ограничения, проверки и это же правило. Чат автоматически не создавать.
