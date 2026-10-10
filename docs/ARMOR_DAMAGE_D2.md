# D2 — технический пакет новой брони

Начат по «продолжай» 2026-09-21. Base main
`5f688c4f7354a79072311d3690440d3b48ace3ba`. Вертикальный срез реализован;
приёмка и итоговый commit записываются в HANDOFF/HISTORY и completion отчёта.
Игровой контракт — [D0](ARMOR_DAMAGE_D0.md), особенно §9.

## Граница и API

Новая capability `UnitState.armor: ArmorState` включается явной сборкой сценария.
`ARMOR` и три старых профиля сохраняют смысл. Старые damage/legacy calculator
отказывают для новой capability. Новый профиль `armor_spatial_v1` использует
тот же AttackCommand, очередь, геометрию, impact и отдельные последствия.

`ArmorFraction` хранит точную рациональную величину с проверкой int64 overflow.
`ArmorHitCalculation.calculate(components, current, maximum, hp, hp_max,
defenses, multiplier)` — чистый расчёт: группировка type/policy, один floor,
защиты, пропорциональное покрытие бронёй, overflow и один итог HP.
Компоненты сохраняют provenance. Первый реестр: physical/fire; политики
standard/hp_only_natural/hp_only_unresisted. Неизвестные значения — отказ.

`ArmorState` хранит естественные защиты, перки лимитов, записи E и следующий
grant ID. `ItemInstance` владеет остатком a_i и неизменным ключом создания;
`ItemDef` — A_i и броневыми сопротивлениями. Надетые вещи дают сумму максимума
и сопротивлений независимо от остатка. Снимок состояния для расчёта содержит
только значения. `ArmorRuntime` собирает и проверяет его; `ArmorHitExecutor`
готовит план на клоне RNG и применяет через pinned SpatialRules.Guard.

## Применение и checkpoints

Admission не меняет live, включая stats cache и RNG. Он проверяет всю известную
mandatory-цепь и требуемые board touches по будущему HP/броне. Оплата атаки — 1 main.
У маршрута движения будущие падения переносят E/a_i/HP/RNG последовательно;
между гранями учитываются поддержанные item-heal реакции настоящего collector.
Внутренний request хранит исходные компоненты; legacy bypass не переосмысляется.

План фиксирует входы и raw request. Исполнение: изменённые записи E в порядке
срока/grant → RNG commit, только если были draws → изменённые a_i в порядке
стабильного ключа → один HP → смерть/occupancy. После каждой записи/сигнала
проверяются sealed request, pinned объекты и ожидаемые значения. Сбой сохраняет
собственные выполненные записи и события; полного hit_resolved при сбое нет.
Нулевые записи пропускаются. Полное объяснение hit отделяет gross HP damage,
healing, net hp_loss/hp_gain и допуск состояния по нужной части до лечения.
Старые damaged/healed отражают только net; armor-only/net-zero не запускает
лечение при HP-уроне. Отдельный реализованный срез состояния описан в [D3](BLEEDING_D3.md).

## Снимки и совместимость

В [текущем Unit snapshot](BATTLE_SNAPSHOT_CURRENT.md) armor-блок присутствует
только при наличии capability; armor-блок v1 содержит защиты, перки, E и счётчик.
ItemSimulation сохраняет определения брони и ключи/остатки всех вещей.
Старые Unit/Item envelopes больше не читаются. Restore не создаёт
полный запас, не восстанавливает вещи и не превращает ARMOR в ресурс.
Неизвестные версии, отсутствующие поля и дубли armor identity отклоняются.
Старой оболочкой нельзя скрыть обязательные поля вещей.
SimulationSnapshot проверяет Unit; ItemSimulation дополнительно проверяет
предметные ссылки и definitions. Forecast копирует определения, runtime,
RNG и счётчики, затем исполняет настоящую команду.

## Точные формы первого среза

`AttackDefinition.damage_components: Array[Dictionary]` добавляет компоненты
к одной physical-базе Сила+Оружие. Каждая запись: `type/policy/source: String`,
`numerator/denominator/factor_num/factor_den: int`. Общая Сила не повторяется
в дополнительных типах; отрицательная база ограничивается нулём до множителей.
Высота `(10+signed_steps)/10` с нижней границей ноль и стойка `7/10` применяются
точно ко всем компонентам прямого удара. Неизвестный ключ/операция/тип/политика
отклоняются. Два множителя огненной руны используют те же данные/API.

Внутренний `DamageRequest(armor_mode="armor")` переносит `armor_components`
с `type/policy/source: String`, `numerator/denominator: int`. `amount` в seal —
ожидаемая net потеря HP, включая ноль/отрицательное лечение. Он не применяется
как legacy bypass. Публичный DamageCommand этот режим отвергает; исполнить его
могут только дочерние sealed hit/collision/fall команды. Числовой результат
пересчитывается на pinned состоянии с клоном RNG перед применением.

Базовые поля ArmorState (текущая armor4 — [снимки](BATTLE_SNAPSHOT_CURRENT.md)):
`schema_version`, `natural: {physical:int,fire:int}`,
`perks: Array`, `grants: Array`, `next_grant_id:int`, `battle_id:int`, `in_battle:bool`.
Перк лимита — `{id,type,branch,bonus}`, строки и int bonus; branch both/armor/natural.
Одинаковый id с одинаковыми значениями учитывается один раз, конфликт — отказ.
Перк переноса E — `{id,kind:"persistent_armor",source}`; source — kind источника
или `*`. Он действует только на новые grants.
Grant — `{grant_id:int,source:String,remaining:int,expires:String,battle_id:int}`;
expires battle/persistent. Нулевые остатки допустимы и не создают draw.
Ключи предмета `armor_origin_owner/armor_origin_item` не равны обязательно нынешнему owner/id.
Фактический перенос между владельцами и улучшение определений — вне D2; снимок
сохраняет исходный ключ, не пересоздаёт вещь. Переодевание разрешено только вне боя.

`ArmorRuntime.plan(view, raw, hp, hp_max, rng)` возвращает значения before/after,
поэтапные дельты grants/items, rng_before/after и draws, rows, p_num/p_den,
armor_spent, total_damage/total_healing, hp_before/hp_after и hp_loss/hp_gain. Row содержит D/H0/B0,
R_H/R_B, H_direct/B_damage, healing, armor_spent/overflow/hp_damage и источники.
`hit_resolved` добавляет source и `hit_id="command_seq:target_id"`: обе жертвы
collision различимы внутри одного шага. `armor_changed` содержит фактически
выполненные дельты `{id,before,after}` отдельно grants/items. Вместимость шага
нового hit — 4 события, collision — 8; старые пределы событий сохранены.

`RestoreArmorCommand(target_id, volume=20, expected_revision, source)` —
рабочее восстановление себя в сценарии, цена этой способности — 1 main,
с тем же допуском MoveRules, что у применения лечебного предмета,
включая частичное восстановление вне боя. Объём уже подготовлен целым вызывающей способностью; нулевой
объём/полный комплект вне боя — отказ. `ArmorRecovery.restore` вычисляет
пропорции по недостаче и новый grant избытка. `ArmorRecovery.repair` — чистый
план выбранных надетых вещей с оплатой W; склад материалов/экран/получение
ресурсов остаются D4. Это не реализованный хаб.

После завершения каскада, в котором одна команда боя потеряла всех живых,
ActionQueue выполняет внутренние `ArmorEndBattleCommand` по unit ID: удаляет
обычные grants и помечает выход из боя. Это часть настоящего forecast, включая
счётчики/лимиты/fault-prefix; UI не удаляет E отдельно после прогноза.
Persistent grants и обычные остатки сохраняются. Повторное окончание не чинит
вещи и не списывает persistent E.

Числа hit — int64 с проверкой переполнения промежуточного представления.
Текущие Vitals хранят float: capability принимает только целый HP/max до 2^53−1.
Адаптер старых float статов принимает точное десятичное значение до 6 знаков
после точки, без округления при переносе; неподдерживаемая точность — отказ.
Дробные определения HP-лечения для capability отвергаются, legacy не меняется.
CombatRng хранит seed/state/draws, клонируется и восстанавливается; выбор int63
с rejection sampling поддерживает весь положительный int64 диапазон весов.

## Игровой вход

Броня доступна в «Сочетаниях ядра» и забеге; [маршруты запуска](REPOSITORY_STATE.md).
Исходный отдельный бой 3v3 сохранён в `tests/fixtures/demo/armor_battle.tscn`.
Физическая база и огненная руна расходуют броню экземпляров;
полоса и панель показывают её текущий запас, максимум и E. Наведение в режиме
атаки показывает итог всего каскада и строки каждого hit; формулы в UI нет.
Клавиша 4 / «Броня +20» восстанавливает комплект за 1 main. Стойка/лечение/ИИ
сохраняются. Призыв в этом сценарии явно недоступен; адаптация помощника к
новой capability не заявляется выполненной. В осмотре унаследованной печати
также указан запрет призыва, без описания доступного помощника.
Legacy сцены доступны отдельно.

## Приёмка

Числа D0, точные дроби/переполнение, p, смешанные типы, >100%/уязвимости,
zero/net healing/death; E-first, weighted item RNG и отсутствие draw без выбора;
restore по недостаче/излишек E/срок; snapshot round-trip и invalid schema;
реальная атака, стойка, collision→fall и добровольное падение; отказы и hostile
callbacks между checkpoints, queue limits; forecast/live equivalence и isolation.
Отдельный UI сценарий показывает броню и объяснение полного прогноза.
После адресных runner: import/startup, `python tools/demo/isolate.py --check --full`,
`python tools/demo/isolate.py --render-check`, настоящий input/scroll в SubViewport,
осмотр PNG, затем независимое ревью фиксированного состава. Frozen P02–P08/§4.5
не изменяются. Графика/хаб/ремонтный экран/DoT/новые состояния вне среза.
