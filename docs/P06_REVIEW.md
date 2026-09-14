# P06 — независимое ревью пакета

Дата: 2026-09-14. Редакция 1. Статус: **APPROVE**.
Это подготовка ТЗ, не реализация и не проверка игрового кода.

## Вход и согласование

Base/main HEAD: `2debe807ab48991c7bfab83d293e994aa0eddd7d`, совпал с ожидаемым.
Окончательные 11/11 hashes runtime/tests P05 и оба frozen hashes task/manifest
совпадают. Исторический manifest P05 сохраняется: 100 входов неизменны, 9 замещены
принятым результатом. В полном review manifest 26/30 совпали; четыре финальных
документа P05 содержат сохранённые review prefixes и принятые addenda.
Текущий P06_DEPENDENCIES фиксирует 118 эффективных зависимостей, включая dirty
P01/P02 и необходимые процессные файлы. Чистого checkout HEAD недостаточно.

Пользователь после явных вопросов утвердил 3 ресурса, attack=1 main, возврат к
частично походившему персонажу (с отдельной будущей политикой запрета), движение
после атаки, maxima из stats с main/bonus base1 и refill в начале хода команды,
предметные изменения maxima и запрет управления инвентарём посреди боя.
Формула: max(1, STR+WEAPON_DAMAGE-ARMOR); никаких критов/случайного уклонения.
Принятый временный scope: P06 на одной высоте, затем баланс/Push, затем высоты
и расширенная досягаемость. Технический pair allowlist не утверждает Faction rules.
Уточнение Push: заблокированная цель остаётся на исходной клетке; возможное
последствие препятствия не требует временного входа. Шипы/урон не реализуются.

## Границы ревью

game_scout Luna/low выполнил адресный поиск damage/items и затем stats/snapshots;
ведущий исследовал queue/Move и спроектировал пакет. Помощники не писали и не
делегировали. Подготовка не требует game_coder: ведущий пишет спецификацию.

Независимому game_reviewer Terra/high передаются фиксированные SHA-256 всех
трёх документов пакета, текущие API и baseline. Запрет записи — инструкция;
отдельное техническое read-only принуждение не заявляется. Ревьюер не запускает
Godot, не делегирует и не коммитит. Задача: найти blocking contract gaps,
особенно ledger/snapshot v1 compatibility, stat gates, exact hit binding/copy,
root payment/HP separation, limits/fault prefix, scope и полноту A01–A14.

Task/manifest не менялись во время или после ревью. Этот отчёт дополнен фактическим
результатом отдельно; самоссылочный hash не используется.

## Проверки подготовки

Выполнены JSON/hash gates, existing-file preservation и diff/whitespace.
Подтверждены 118/118 текущих dependencies, 100 неизменённых исторических входов и
9 явных supersessions. Все 228 прежних файлов вне передачи совпадают с baseline;
исходный P05 текст передачи также сохранён с точным прежним SHA-256.
Новых неигнорируемых файлов ровно три — документы P06. Все существующие allowed
runtime/tests paths присутствуют в manifest. Артефакты: test_reports/p06-preparation-
baseline.json, p06-preparation-audit.json, p06-package-review-r1.json.
Godot/import/tests/UI в документационной подготовке не запускались. Исторические
1421 passed, 0 failed относятся к принятой реализации P05.
Прежние dirty файлы сохраняются; изменяется только untracked передача добавлением
нового текущего раздела, её исходный P05 архив сохранён. В локальный коммит входят
только P06_ATTACK_TASK.md, P06_DEPENDENCIES.json, P06_REVIEW.md; push запрещён.

## Результат

Независимый game_reviewer / gpt-5.6-terra / high вернул **APPROVE** редакции 1.
Блокирующих замечаний нет, исправлений по ревью не потребовалось. Ревьюер подтвердил
три frozen hashes и 118/118 dependencies, HEAD, dirty context и соответствие
реальным queue/HP/occupancy/stat/snapshot API. Помощник не писал, не запускал
Godot/tests, не делегировал и не коммитил.

Зафиксированная принятая версия:

| Документ | SHA-256 |
|---|---|
| P06_ATTACK_TASK.md | `F23427DB3468213E0179D2FF992507984EAFC0918959170329C9EEC1A4E373AA` |
| P06_DEPENDENCIES.json | `23A046B929B26CE8D4CADDC1BC9072531B56B8E9E192876A34A4B210A732A83E` |

Входной hash отчёта до записи этого результата:
`082DE4C86511B587CBC7F4B45F23EFA2F7B81C0B8274279E328B2A9BA50A8282`.
Он идентифицирует прочитанный reviewer draft отчёта, не текущий файл и не dependency
будущей реализации. Финальный отчёт меняет только review/status metadata; ТЗ и
manifest сохраняют два приведённых hashes.

Проверено проектирование owner-bound ledger, v1/v2 Unit snapshot и legacy export
guard, internal sealed Hit/identity/copy, единственная оплата, bypass без двойного
STR/armor, attacked schema, limits/fault prefix, границы Flow/refill и A01–A14.
Ведущий повторно проверил task/manifest hashes после APPROVE. Это не утверждение
о работающем AttackCommand: игрового diff нет. Пакет готов для отдельного поручения
на реализацию после свежего gate. До её коммита обязательны import/startup/runner
и новое независимое ревью fixed runtime/tests; особо проверить snapshot compatibility,
Hit seal/bindings, legacy export refusal, лимиты и no-refill call graph.
