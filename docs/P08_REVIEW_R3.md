# P08-SPATIAL r3 — независимое APPROVE спецификации

2026-09-14. Редакция3, фиксированный draft2. **APPROVE** от
game_reviewer / gpt-5.6-terra / high, минимальный контекст (fork_turns=none).
Подтверждённый CONTRACT_GAP S14 редакции2 закрыт на уровне точного контракта.
Runtime в этом этапе не менялся; это НЕ приёмка реализации P08.

## Вход и приоритет источников

Ветка main, входной HEAD `1e3099e35c342f13298093523dc25f164e66f424` совпал
с ожидаемым. Git status совпал с финальным аудитом r2; индекс был пуст.
Принятые dirty P01/P02/P06 и untracked документы/скрипты сохранены.

Сверены 256 files и22 local_artifacts P08 r2,12 artifacts финального gap audit,
12 files gap-review-manifest,26 files принятого P07 implementation manifest
и9 final P07 artifacts вне mutable HANDOFF. DECISIONS/TESTING проверены по
актуальным hashes final-audit r2, выше historical P08/P07 dependencies.
Входной HANDOFF также совпал с final-audit r2; его исходные bytes закреплены
в handoff-before.md. Historical P07 provenance в новом manifest остаётся историей;
текущие effective files задаёт P08_DEPENDENCIES_R3.json.

Frozen P01–P08 r2 не переписаны. Архив paused-substrate не используется как готовый
runtime или как patch для автоматического применения. Базовый регресс1996 passed /
0 failed подтверждён прежним implementation gap audit; он НЕ является S01–S17
приёмкой P08. Godot в текущей подготовке документов не запускался.

## Что закрывает r3

Сохранены игровые разделы2–3 и исходные строки S01–S17. Headless профили остаются
opt-in. Полууровни, стоимость Move, прямая досягаемость, высотные HP/impact,
Push/collision/fall и порядок item reactions прежние. UI/AI/Flow, общий LOS,
полный preview/save-game и неподтверждённые игровые правила вне этапа.

Allowed paths:28, из них24 существующих и4 новых. К22 путям r2 добавлены:

- AttackHitCommand, BalanceCommand, PushDamageCommand — обязательные terminal
  guards, включая impact0/immunity, no-break и terminal HP.
- ActionHpExecutor — отдельный pinned spatial adapter, без повторного чтения
  replacement refs и старого _finalize после callbacks.
- Vitals — узкие spatial receipt/checkpoint методы, фиксирующие собственные
  записи до сигналов и проверяющие binding перед оставшейся фазой. Legacy API прежние.
- DeathCommand — internal bound spatial Move HAZARD, с точной cell_death формой.

BattleBoard уже был разрешён; теперь закреплены identity регистрации death callback
и защита cleanup от replacement. Остальные guards находятся в уже разрешённых
Move/Push/Collision/Binding seams. Новых дополнительных global class files нет.

§4.5 задаёт pinned identities, HP/alive/balance, move/main/bonus всех участников,
geometry, единые board_origin_version/expected_board_version и только известные
board touches. После callback нельзя снимать новый доверенный baseline.
FAULTED сохраняет оплату, собственные выполненные HP/смерть/events и внешние записи,
останавливает остаток cascade. Rollback/revival и общая S-5 реентрантность не вводятся;
event validator Queue не выполняет скрытый replay или повторную симуляцию.

S14a–j/S15a–c расширяют terminal callback/replacement/version/prefix матрицу;
S16 включает restored lifecycle facades и одинаковые fault fixtures на copies.

## Фиксированное независимое ревью

Первый draft получил REQUEST_CHANGES:
1. Явно определить nullable inventory/equipment lifecycle0/1/2 и raw attachment.
2. Согласовать Binding: fall требует non-null request/seal, cell_death — null/null,
   exact source/target/lethal destination; проверить mode и null/non-null подмену.
3. Унифицировать имена двух version fields и тестировать подмену каждого.

Все замечания исправлены в draft2 вместе с матрицей тестов. Повторное независимое
ревью подтвердило exact HEAD/hashes и вернуло **APPROVE**, blockers отсутствуют.
Reviewer только читал документы/код, не писал, не запускал Godot/check scripts,
не делегировал и не коммитил. Scout / Luna / low отдельно локализовал seams;
ведущий сам уточнил необходимый receipt контракт внутри HP/signal границ.

| Зафиксированный файл | SHA-256 точных LF bytes |
|---|---|
| docs/P08_SPATIAL_TASK_R3.md | `965606897F9AC8ACAB72F3D90AB655EEDE32E4712B6FF62880051980FAC72953` |
| docs/P08_DEPENDENCIES_R3.json | `30001BE8BB354FE87A3D729FFCE6DFE49462034D22E68AD5DC2FE00948973662` |

После APPROVE эти bytes не редактируются. Git LF normalization не меняет их.

## Проверки и артефакты

Уникальный каталог: `test_reports/p08-r3-preparation-dbf3db2fd468467cbbb9d39745bada7f/`.
В нём baseline/hash inventory/patch, handoff-before, input-checks, оба exact task
drafts, dependencies-fixed, manifests/checks draft1/draft2, независимые отзывы,
адресные выводы scout/ведущего и итоговый audit. Старые check-скрипты не запускались.

Проверки ведущего:259 effective dependencies/29 local_artifacts, exact allowed28,
4 expected-absent новых paths; исходные игровые разделы и17 acceptance rows
сохранены. Независимые арифметические примеры:6 damage/5 fall/8 reach/6 cost.
Diff/whitespace и LF bytes прошли.260 прежних repo files сохранены (HANDOFF —
точным исходным suffix),1663 прежних report files сохранены побайтно.
Исходный tracked binary diff совпадает с baseline; чужие hunks не staged.

Локальный логический docs commit содержит только TASK_R3, DEPENDENCIES_R3 и этот
REVIEW_R3. Прежний untracked HANDOFF обновлён отдельно, его старый текст не staged.
Итоговый commit/status записаны в HANDOFF и final-audit. Push, задачи боковой панели
и расписания не создавались.

## Следующий этап

Отдельное поручение на реализацию принятой P08-SPATIAL r3 после свежей проверки
HEAD/status/effective hashes. Нужны новые import/startup/весь регресс/S01–S17 и
независимое runtime APPROVE. Особое внимание: signal checkpoints, raw occupancy/
replacement, death cleanup version, lifecycle и точный оплаченный event prefix.
Удобно начать новый чат с CODEX_HANDOFF; автоматическая задача не создаётся.
