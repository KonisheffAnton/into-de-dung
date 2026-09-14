# P07 — независимое ревью пакета

Дата: 2026-09-14. Редакция 1. Статус: **APPROVE**.
Это проверка проектирования, не реализации; Godot в этой подготовке не запускался.

## Вход и согласование

Base/main HEAD: `3819cb50c360247d1994ee7fde49a1936f37e3e2`.
Проверены 31/31 SHA-256 принятого revision1 P06, 5/5 артефактов итогового аудита,
точный исходный status и reverse-check residual/staged patches без применения.
Из 118 старых inputs 104 неизменны, 10 замещены принятой реализацией P06, четыре
документа — финальными addenda с побайтно сохранёнными историческими prefixes.
Новые dependencies содержат 140 эффективных файлов и шесть локальных артефактов.
Исторические manifests/frozen документы не переписаны. Чистого checkout недостаточно.

Пользователь подтвердил накопление IMPACT_POWER, max≤0 immunity, один break/reset0
без избытка, бесплатный одноклеточный Push после attack=1 main. Collision переносит
STRENGTH+WEAPON_DAMAGE до брони: броня вычитается отдельно у каждого получателя;
минимум1 также у fall. Спуск: 25% HP_MAX за полный уровень минус armor, минимум1.
Collision/fall не добавляют impact. Порядок HP→Balance→Push/последствия→item reactions,
два HP collision до реакций. Последнее уточнение заменило ранний запрет входа после
смерти blocker: выжившая цель входит на место погибшего blocker-персонажа.
Если blocker выжил, цель остаётся на месте без фиктивных moved/entry.

Полууровни сохраняются вне реализации P07: при целых высотах положительный delta
больше разрешённых +0.5 и блокируется. Шипы и отдельные разрушаемые terrain objects
зафиксированы как будущие требования. HAZARD/VOID сохраняют прежнюю lethal семантику.

## Делегирование и границы

game_scout (gpt-5.6-luna / low) адресно проверил Balance/Push rules, integer heights,
snapshot representation, отсутствие terrain HP/spikes и существующие test seams.
Ведущий самостоятельно исследовал очередь, HP/death, item reactions и спроектировал
пакет. Кодер в подготовке не нужен; runtime не меняется, помощники не пишут.

game_reviewer (gpt-5.6-terra / high) получает фиксированные task/dependencies/report
hashes и минимальный самодостаточный контекст, только чтение, без делегирования,
Godot, коммитов. Запрет записи задаётся инструкцией; отдельное техническое read-only
принуждение не заявляется. Проверяется полнота contracts/allowed paths/формул,
collision→entry ordering, seals, min1/bypass, четыре events атомарной пары, sequence/
board-version fault prefixes, snapshot compatibility и A01–A17.

## Проверки подготовки

До ревью подтверждены 244/244 исходных файла и 140/140 эффективных dependencies,
31/31 P06 hashes и все локальные audit artifacts. Артефакты подготовки находятся
только в test_reports/p07-*. Передача обновляется отдельно после APPROVE с сохранением
прежнего текста. Новые коммитируемые документы — только TASK/DEPENDENCIES/REVIEW P07.
Игровой import/startup/regression здесь не выполнялся; 1633/0 — принятый P06 baseline.

## Фиксированная редакция 1

| Документ | SHA-256 |
|---|---|
| P07_BALANCE_PUSH_TASK.md | `980C722BC9F5EFB93811B0AABB41803ABD247AAF8E232C6E1BCA51355FDA3C3C` |
| P07_DEPENDENCIES.json | `C8652B93EAF53FE9A2FF408A5E355ADC6C5CA48C9BF4C0C19BECF7AD6C94ED3D` |

Hash исходного draft отчёта во внешнем p07-package-review-r1.json:
`37EA29D91D7E5EFEA97905A178654755F3BA21CB873B0300F2798C0F9EB1DEAD`.
Это hash прочитанного reviewer draft, не текущего дополненного отчёта и не input
будущей реализации. TASK и DEPENDENCIES после ревью не изменялись.

## Результат независимого ревью

game_reviewer / gpt-5.6-terra / high вернул **APPROVE** редакции 1. Блокирующих
замечаний нет; исправления по ревью не потребовались. Зафиксированный ответ
сохранён в test_reports/p07-independent-package-review.md.

Подтверждены все три входных hashes, 140/140 effective dependencies и 6/6 local
artifacts. Ревьюер проверил реальные Board/Resolver/HP/Queue/Item APIs, оба HP
collision одним step, вход выжившего target на место погибшего blocker, обязательные
fall/lethal последствия до реакций, отсутствие moved при сохранившемся blocker,
seals/identity/internal roots, exact-class capacity4/event-seq reserve, versions/
fault prefixes, P06 opt-in profile и Unit v1/v2/P02/P03b совместимость.

Ревьюер не писал файлы, не делегировал, не запускал Godot и не коммитил. Ведущий
дополнительно проверил 15 allowed paths: пять существующих входят в dependencies,
десять новых отсутствуют; числовые примеры, whitespace/code fences и исходный status.
Runtime P07 пока отсутствует; это APPROVE проектирования, не реализации. Перед
коммитом будущего кода обязательны import/startup/runner/A01–A17 и новое независимое
ревью фиксированного runtime diff, особенно queue, partial collision prefix,
occupancy после entry и P02/P03b restore.

Все игровые вопросы текущего среза закрыты. Дробные высоты/спуск, terrain HP/spikes,
Flow/BT, полный preview/token/save-game и общие C-3/S-5/T10/T11 остаются открытыми
вне P07. Новый этап — отдельное поручение на реализацию по двум frozen hashes выше.
