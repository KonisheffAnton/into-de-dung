# Передача — 2026-11-01: ETL боя и отличие isolate

D:/Games/into-de-dung; main; base ba81d1281e0c281540ab32ff1f6fc3c0340c3c1e.
Стабильные 60 FPS НЕ достигнуты. Runtime/настройки игры и ОС не менялись.
[Владелец измерений/границ](performance/battle-graphics-trace-20261101.md).

Пользователь видел рывки в первом тесте; после второго уточнил: тестовые
движения плавнее обычного isolate, но плохо видны. Это не приёмка игры.
1038 runtime/assets файлов checkout, последнего isolate и soak совпали побайтно;
движок Mobile/D3D12/RTX3050 тот же. Пользователь: размер тот же, хуже от мыши.
Soak отключает GUI-ввод: hover/осмотр/подготовка preview не покрыты.
Следующий шаг — измерить этот интерактивный путь; не объявлять все фризы
системной проблемой по автономному бою. Probe в isolated project: tests/probe_interactive_forecast_perf.gd;
результаты — interactive-forecast-probe*.

Два ручных elevated боя32×5: по53 PASS/0, минимум29 живых, DOT/огонь.
20159ab3(kernel)+3e66c567(graphics), PID25452: все кадры с фокусом,
36 display-пиков max23,9322мс; все кадры готовы до предыдущего display.
Обе новые ETL loss0. В окнах пиков известные ready-задержки <=0,1294мс,
ISR/DPC <=0,295мс;34 off-CPU интервала неизвестны. Причина не доказана.
Есть CPU samples/StackWalk; символы и trigger-stack join не выполнены.
Нет точного Godot↔PresentMon или независимого physical scanout.

Артефакты: test_reports/battle-frame-pacing-20261031/; ETL IDs выше,
graphics-stage-{validation.json,review.md}, isolate-vs-soak-runtime-20261101.json.
Python parse,18 collector+4 analyzer tests PASS; C# compile/offline PASS;
независимое APPROVE с ограничениями.
Новых full/core/F5/движение/zoom/DPI/другой GPU проверок нет. Прежние
HUD/lifecycle/цвета/Колода/арт-приёмка открыты.

Сохранять core/preview/queue/RNG/save/frozen. Один GPU runner, isolated project,
без root import, автоповышения прав/обхода политик/изменения служб и драйверов.
Чужие scenes/demo/main_menu.tscn и docs/art/battlefield-reference-03-20261017/
не reset/stage/commit. Без push/sidebar tasks/расписаний/нового арта/интеграции.
[Прежний HANDOFF побайтно](CODEX_HANDOFF.history-20261101.md), [HISTORY](HISTORY.md).

Завершение: проверки, локальный Conventional Commit, короткий HANDOFF;
прежний побайтно отдельным архивом+HISTORY. В финале/при блокере предложить новый
чат и полный самодостаточный промпт: HEAD, результат, docs/artifacts, остаток,
ограничения, проверки и это же правило. Чат автоматически не создавать.
