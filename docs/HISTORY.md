# История и свидетельства проверок

Архив не входит в обязательное чтение. Он хранит причины старых решений,
исходные спецификации и результаты на конкретных версиях. Статусы внутри
снимков не применяются к текущему HEAD; не восстанавливать старый dirty overlay.

## Первая редакторская архивация — 2026-09-20

Исходный HEAD: `dcac6da4afb0d3583db79409c8f2fe1f06593968`.
Каждый снимок ниже содержит короткую архивную пометку и весь исходный файл
точным suffix. Снимки расположены рядом с активными docs для сохранения
относительных ссылок. Предыдущую редакцию цели ссылки смотреть в этом списке
или через `git show <исходный HEAD>:<путь>`, а не считать активный файл старой версией.
Это заменяет накопление всей истории внутри CODEX_HANDOFF.

| Исходный документ | Снимок |
|---|---|
| `AGENTS.md` | [Архив](../AGENTS.history-20260920.md) |
| `docs/ACTION_PANEL_GUARD.md` | [Архив](ACTION_PANEL_GUARD.history-20260920.md) |
| `docs/ARCHITECTURE.md` | [Архив](ARCHITECTURE.history-20260920.md) |
| `docs/ATTACK_FORECAST.md` | [Архив](ATTACK_FORECAST.history-20260920.md) |
| `docs/AUDIT.md` | [Архив](AUDIT.history-20260920.md) |
| `docs/CODEX_HANDOFF.md` | [Архив](CODEX_HANDOFF.history-20260920.md) |
| `docs/CODEX_WORKFLOW.md` | [Архив](CODEX_WORKFLOW.history-20260920.md) |
| `docs/COMMAND_ACTION_QUEUE_CONTRACT.md` | [Архив](COMMAND_ACTION_QUEUE_CONTRACT.history-20260920.md) |
| `docs/DECISIONS.md` | [Архив](DECISIONS.history-20260920.md) |
| `docs/DEMO_SANDBOX.md` | [Архив](DEMO_SANDBOX.history-20260920.md) |
| `docs/DESIGN_DIRECTION.md` | [Архив](DESIGN_DIRECTION.history-20260920.md) |
| `docs/HEALING_ITEM.md` | [Архив](HEALING_ITEM.history-20260920.md) |
| `docs/MECHANICS_REQUIREMENTS.md` | [Архив](MECHANICS_REQUIREMENTS.history-20260920.md) |
| `docs/MODULARITY_PLAN.md` | [Архив](MODULARITY_PLAN.history-20260920.md) |
| `docs/PROJECT_CONTEXT.md` | [Архив](PROJECT_CONTEXT.history-20260920.md) |
| `docs/REPOSITORY_STATE.md` | [Архив](REPOSITORY_STATE.history-20260920.md) |
| `docs/SUMMON_ITEM.md` | [Архив](SUMMON_ITEM.history-20260920.md) |
| `docs/TACTICAL_BATTLE.md` | [Архив](TACTICAL_BATTLE.history-20260920.md) |
| `docs/TACTICAL_DESIGN_NEXT.md` | [Архив](TACTICAL_DESIGN_NEXT.history-20260920.md) |
| `docs/TESTING.md` | [Архив](TESTING.history-20260920.md) |

Карточки [modules](modules/) сохранены на прежних путях с явной исторической
пометкой. Аудит старых дефектов — [AUDIT](AUDIT.md); точные Pxx пакеты
находятся через [контракт исполнения](COMMAND_ACTION_QUEUE_CONTRACT.md).
Все Pxx TASK/DEPENDENCIES/REVIEW, включая §4.5 P08 r3, сохранены без изменений.

## Последняя игровая приёмка (историческая)

Игровой HEAD: `f0f379f6178b8948266aee36c833f83fe4706494`.
Core 9440/0 с известными legacy diagnostics 47 ObjectDB/18 resources;
summon 137/0, summon_snapshot 55/0, healing 106/0, guard 219/0, forecast 166/0;
headless demo 138/0, battle 247/0; render demo 143/0, battle 267/0.
Import/startup, source parity и clean-clone headless PASS; APPROVE v1, 31/31 SHA256.
Эти counts не доказывают проверки новой концепции или будущего изменения.

Источники: раздел «отдельная печать призыва» в
[HANDOFF history](CODEX_HANDOFF.history-20260920.md), локальные
`test_reports/summon-item-20260915/completion.json` и `clean-clone.json`.
Точные пути игровых логов/PNG находятся в том же архиве. Отчёты ignored,
в другом клоне могут отсутствовать; команды воспроизведения — [TESTING](TESTING.md).
Предыдущая оценка дизайна: `test_reports/design-direction-20260920/`, APPROVE v2
только документации. Текущая реорганизация: `test_reports/docs-refactor-20260920/`.

## Проект D0 — 2026-09-20

Base `82a984e45500334ea344365edcad980d5835a2b7`, только документация.
Предыдущая короткая передача сохранена целиком в
[снимке](CODEX_HANDOFF.history-20260920-2.md).
Подготовлен [проект контракта](ARMOR_DAMAGE_D0.md); принятые в обсуждении ответы
записаны в DESIGN_DIRECTION. Расчётные проверки/ревью этого текста:
`test_reports/armor-damage-d0-20260920/` (ignored), не игровая приёмка.

## Уточнение сопротивлений D0 — 2026-09-20

Base `95c48a60c1513d8268905744d448c423b9c970c9`, только документация.
Предыдущая короткая передача сохранена целиком в
[снимке](CODEX_HANDOFF.history-20260920-3.md).
Последний ответ пользователя заменил прежний порядок Q4: броневая ветвь проходит
сумму сопротивлений, естественная защита срабатывает один раз, остаток переходит
в HP без повторного уменьшения. Обновлены D0 и DESIGN_DIRECTION.
Числовые проверки и результат ревью —
`test_reports/armor-damage-d0-resistance-20260920/` (ignored).
Обсуждение D0 продолжается; игровой код и его проверки не менялись.

## Как добавлять историю

Не менять старый снимок. При завершении следующего этапа сохранить прежний
короткий HANDOFF новым `CODEX_HANDOFF.history-<дата>[-N].md` и добавить здесь ссылку.
Полные логи и manifests остаются в отдельных отчётах; активные документы содержат
обновлённые факты и ссылки вместо копий журналов. Правило — [CODEX_WORKFLOW](CODEX_WORKFLOW.md).
