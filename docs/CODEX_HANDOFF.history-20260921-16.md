# Передача — 2026-09-21: D1, прежняя формула выделена

## Результат и Git

Main; base `f17b7d9bda9ccc5633bbca8650a57b564413fcb0`, вход чистый.
После отдельного «продолжай» выполнен D1/M2a. Итоговый HEAD/status — в completion.json
отчёта ниже; сверить перед работой. Все изменения D1 входят в итоговый commit,
незакоммиченного остатка этапа нет.
[ATTACK_DAMAGE_D1](ATTACK_DAMAGE_D1.md): AttackDamageCalculation считает прежний
прямой удар и отдаёт стадии; AttackCommand сохраняет допуск/оплату/sealed hit.
В BalancePushRules передаётся raw_attack до высоты/стойки. Снимки, события,
цена 1 main, RNG/counters, отказы/fault-prefix и итог forecast прежние.
Legacy DamageCalculator, direct flat/bypass, collision/fall/death не унифицированы.
UI прежний; стадии чистого расчёта не добавлены в frozen receipts или панели.

## Границы и следующий шаг

[D0](ARMOR_DAMAGE_D0.md) — завершённый дизайн, новая броня НЕ реализована.
Q1–Q6 не переоткрывать: U сохранены, A/§9 закрывает решения ведущего.
Следующий рекомендуемый этап — D2 по отдельному поручению: точный пакет
API/schema/checkpoints и вертикальный срез новой брони/типов/forecast.
D2–D5/M1/M2b/M3–M4 не запущены; остальные P вне брони не приняты.
Технические детали ведущий выбирает сам, спрашивает только при противоречиях с U;
если вопросы понадобятся, собирать их пакетом. [Контекст](PROJECT_CONTEXT.md).

## Проверки и ограничения

Отчёт `test_reports/armor-damage-d1-20260921/` (ignored): baseline-provenance,
исходные binary traces, verification/review/completion и next-chat-prompt.
5880 комбинаций, 23555 assertions чистого расчёта PASS; 57 baseline-сценариев,
502 integration assertions PASS. Baseline снят с настоящего base через git archive.
Import/startup, адресные тесты, --check --full (core 9440/0), --render-check PASS;
demo 143/0, battle 267/0, реальные input/scrolling в SubViewport, PNG осмотрены.
Core diagnostics совпали с base, включая 47 ObjectDB/18 resources при выходе;
сравнение — verification.json. Независимое ревью — APPROVE, review.md/completion.json.
Прогоны: `test_reports/demo-d4851352a76847d4b9f83e0c8110630c/` (full),
`test_reports/demo-032ec8be9276476db2170312c3dc288f/` (render).
Плейтест удобства/баланса открыт; графика отложена. Без push/sidebar tasks/расписаний.
Архивы *.history-*.md и docs/modules/ автоматически не читать; frozen P02–P08/§4.5 не менять.
Работа и проверки — [CODEX_WORKFLOW](CODEX_WORKFLOW.md)/[TESTING](TESTING.md).
Прежняя передача — точный [снимок](CODEX_HANDOFF.history-20260921-15.md), ссылка в HISTORY.
В конце этапа/при блокере обновить короткий HANDOFF, сохранив прежний отдельным архивом
со ссылкой из HISTORY. Полный самодостаточный промпт следующего чата вывести прямо
в финальном сообщении блоком кода: HEAD, результат, docs/artifacts, остаток,
ограничения, проверки и это же правило. Ссылка не заменяет текст.
