# P04 — независимое ревью пакета ТЗ

Дата: 2026-09-14. Редакция 1. Итог: **APPROVE**.
Это проверка проектирования и документации, не принятие реализации игрового кода.

Вход main/HEAD `006fe1eaeca9fe19e97eed1b9030c0d565286b3a` совпал.
Принятый P03b: 17/17 hashes результата и 43/43 неизменённых исторических входов.
Manifest P04 фиксирует 67 текущих зависимостей; все 67 совпали.

Ревьюер: отдельный game_reviewer, gpt-5.6-terra/high, минимальный контекст,
запрет записи по инструкции. Отдельное техническое read-only принуждение не заявляется.
Адресный поиск API item runtime выполнил game_scout, gpt-5.6-luna/low.
Помощники не делегировали дальше и не коммитили.

Принятая зафиксированная редакция 1 (файлы не менялись во время/после ревью):

| Файл | SHA-256 |
|---|---|
| P04_ACTION_QUEUE_TASK.md | `E63D57E3567AA5E64137E62BEB8652DB02B3425B96BA51D27E942A9A531BC9C8` |
| P04_DEPENDENCIES.json | `A2D8420AE7CA781E3EAFBCBB6F2EF4B0FE8F4A817F81D7BE69C067EDE0338BCA` |

Ревьюер независимо подтвердил оба hashes и 67/67 зависимостей. Проверены ownership,
read-only шов P03b, scheduler и provenance value DTO, BUSY/FAULTED, atomic event
overshoot, смерть/occupancy, stale-vs-invariant revalidation, RNG clone/round-trip,
allowed_paths и C01–C12. Блокирующих сценариев и замечаний нет; исправления не потребовались.

Ведущий отдельно сверил actual API и границы: P03b collector получает только свой
узкий event DTO после preflight/cleanup; item binding хранит локальную identity, journal
её не сериализует. Damage не добавляет impact/STRENGTH, Heal сохраняет over-max HP;
Death использует общий finalize. Нет переноса старых gameplay callbacks или объявления
полного preview/C-3/S-5 готовыми. Порт RNG проверяется детерминированной fixture,
production RNG всей игры остаётся вне P04. Старое утверждение draft-2 о цене атаки
не используется; зависимых от нерешённого геймдизайна работ в пакете нет.

Проверки ведущего: HEAD/status, effective dependency hashes, JSON parse, сохранность
189/189 прежних файлов до обновления передачи, diff/whitespace. Baseline/status/diff,
копия прежней передачи и отчёт лежат в игнорируемых `test_reports/p04-preparation-*`
и `test_reports/p04-handoff-before.md`. Godot/import/startup/tests/UI не запускались:
игровой код не меняется. 1008/0 — исторический результат P03b, не результат P04.

Передача дополнена отдельно; её прежний untracked архив не включается в staging.
Локальный коммит содержит только три новых документа P04. Старые P01/P02,
процессные файлы и смешанные docs/tests не включаются. Push не выполнять.

Готовность: пакет можно передать исполнителю отдельным запуском после свежего gate.
Блокирующих вопросов P04 нет. Открытые цена атаки, переключения и Push отложены до
зависимых пакетов. Реализация P04, C01–C12, Godot и UI этим APPROVE не проверены.
После реализации нужны import/regression и новое независимое ревью фиксированных
hashes, особенно death/occupancy, work stack/reaction keys, fault prefix и item identity.
