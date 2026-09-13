# P03b — независимое ревью ТЗ

Дата: 2026-09-13. Редакция 1. Итог: **APPROVE**.
Это одобрение спецификации; реализация P03b не выполнялась и требует отдельного задания.

| Зафиксированный файл | SHA-256 |
|---|---|
| [P03B_ITEM_SNAPSHOT_TASK.md](P03B_ITEM_SNAPSHOT_TASK.md) | `4D3EB9A4DC6ECAE6F88ADB4BB6FE822C61011F846613165FF5D0C1222FBE65C2` |
| [P03B_DEPENDENCIES.json](P03B_DEPENDENCIES.json) | `8D1C490EBF9C5659A8B9A054E99A554A314E91BE5115C228D98B1748900EE6EC` |

Ревьюер: отдельный game_reviewer, gpt-5.6-terra/high, минимальный контекст.
Только чтение по инструкции; отдельное техническое принуждение read-only не заявляется.
Ревьюер не менял файлы, не запускал проверки с записью кэша и не делегировал дальше.
Пакет во время ревью не менялся. Он подтвердил оба hash и **49/49** зависимостей manifest.
Перед коммитом окончания строк manifest нормализованы CRLF→LF по .gitattributes;
содержимое не менялось. Повторная проверка финальных hashes и состава manifest
подтвердила сохранение **APPROVE**.
Адресный поиск текущего runtime отдельно выполнил game_scout, gpt-5.6-luna/low;
его выводы о ledger, source linkage и отсутствии restore API согласуются с ТЗ.

Проверены согласованность с ledger/facades P03a и P02 board snapshot, modifier slots и
evaluation_order, occupancy/callback смерти. Restore запрещает equip, legacy load,
активацию и выдачу UnitId; links адресуют уже сохранённый modifier occurrence.
Lifecycle и ownership фасадов, closed/retired, canonical bytes, лимиты, capability failures,
чистый collect и граница P04 определены достаточно для реализации.
Критерии B01–B14 покрывают runtime isolation, детерминизм, повторный collect,
смерть/occupancy, allocator и владение DTO. Блокирующих замечаний не найдено.

Ведущий дополнительно проверил архитектурные границы: P02 codec не меняется;
ItemSimulationState временно исполняет только обязанность composition root board/items;
ItemSimulationSnapshot сохраняет весь registry/counters/lifecycle и восстанавливает его
без повторного добавления modifiers. Collector возвращает только value descriptions.
ActionContext/очередь, RNG, реальные HealCommand и полный preview остаются за пределами P03b.

Проверки подготовки:

- main/HEAD `2dae04de093ca23e579559767dbda98ffe9b160f` совпали с передачей;
- 25/25 hashes принятого P03a совпали, 10 неизменённых зависимостей P02 совпали;
  исторический P02 hash tests заменён принятым P03a и не используется как текущий;
- 49/49 hashes нового manifest совпали; будущие файлы реализации P03b отсутствуют;
- все 176 прежних файлов до обновления передачи сохранились побайтно;
  единственное разрешённое изменение прежнего файла при завершении — CODEX_HANDOFF:
  новая сводка перед прежним содержимым, которое сохраняется полностью;
- проверка diff/whitespace; staging ограничен тремя новыми документами P03b.

Начальные status/diff/hashes сохранены в игнорируемых test_reports/p03b-preparation-*.
Они служат локальным доказательством сохранности, а не обязательной зависимостью пакета.
Прежние незакоммиченные P01/P02 и процессные изменения не включаются автоматически.
Код P03b не писался. Godot import/startup/tests/визуальное демо не запускались:
исторические 722/0 относятся к принятому P03a, не к текущей подготовке документации.

Непроверенное: будущая реализация и фактическое выполнение B01–B14. После неё обязательны
Godot/regression проверки и новое независимое ревью фиксированных hashes/diff/logs.
Критическое ревью ведущего должно проверить restore call graph, Resource/runtime ownership,
фасады, modifier linkage, canonical encoding и границу P04 queue/preview.
ТЗ не объявляет завершёнными полный C-3/T10/T11, 0.5/0.8, общий S-5 или save-game.
