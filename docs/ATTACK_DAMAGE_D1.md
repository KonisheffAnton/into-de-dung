# D1 — выделение нынешнего расчёта прямого удара

Реализовано 2026-09-21 по отдельному поручению после D0. Base:
`f17b7d9bda9ccc5633bbca8650a57b564413fcb0`, ветка main.
Наблюдаемое поведение трёх профилей сохранено. Новая броня из
[ARMOR_DAMAGE_D0](ARMOR_DAMAGE_D0.md) остаётся будущим дизайном.

## API и владение

Чистый [AttackDamageCalculation](../scripts/core/combat/attack_damage_calculation.gd)
наследует RefCounted. Единственная точка расчёта:

```gdscript
static func calculate(strength: float, weapon: float, armor: float,
    spatial: bool, signed_height_steps: int, guarded: bool) -> Result
```

`Result: RefCounted` содержит `reason: StringName`, `raw_attack: float`,
`scaled: float`, `hit_amount: float`. Пустой reason означает успех.
Неконечный вход или промежуточный результат даёт `attack/nonfinite_damage`;
числовые поля результата при ошибке не используются, список стадий пуст.
Отрицательные конечные значения допустимы; floor/квантования нет.

Порядок операций совпадает с кодом до D1:

1. `raw_attack = strength + weapon`.
2. Только spatial: `scaled = raw_attack * SpatialRules.height_multiplier(signed_height_steps)`;
   прочие профили используют raw_attack без умножения.
3. `raw = scaled - armor`, затем `amount = maxf(1.0, raw)`.
4. При стойке цели `amount = maxf(1.0, amount * 0.7)`.

Проверки конечности стоят после суммы, масштабирования и вычитания брони.
Входы — значения, без UnitState/StatsBag/board/Resource/RNG и событий.
Каждый вызов создаёт независимый результат. Его изменение не влияет на бой.

`get_stages() -> Array[Dictionary]` возвращает отдельные копии значений.
Каждая запись имеет ключи StringName: `kind`, `input`, `operand`, `output`;
kind — StringName, остальные значения — float. Стадии:
`base_add`, опциональная `height_multiply`, `armor_subtract`, `minimum`,
при стойке `guard_multiply`, `guard_minimum`. Operand минимума равен 1.0.
Это объяснение одного прямого удара, не суммарного ущерба каскада и не save/token.

## Интеграционная граница

[AttackCommand._prepare](../scripts/core/actions/attack_command.gd) сохраняет
допуск/копирование stats/проверку ресурсов, координат, профиля и reach.
Он передаёт проверенные значения в helper и берёт hit_amount для прежнего
`DamageRequest(physical, bypass)`. Цена остаётся 1 main; sealed hit, проверки
board touches, смерть/occupancy, revision, counters и fault-prefix не меняются.
В `BalancePushRules.prepare_attack` передаётся именно raw_attack до высоты,
брони и стойки: collision сохраняет свою базу. Impact и fall остаются отдельными.

Legacy DamageCalculator, прямые flat/bypass requests и все death-пути не
переведены на helper. Их разные минимумы и защиты не унифицированы.
AttackDefinition/AttackRules, serialized enum, snapshot schema и receipts прежние.
UI продолжает читать итог настоящего [forecast](ATTACK_FORECAST.md), включая
последствия и предметное лечение; формулы в UI нет. В D1 стадии доступны из
Result для технического объяснения, но не добавляются в UI или frozen receipt.
Вывод нового объяснения брони/HP в UI относится к D2.

## Проверки и следующий шаг

[Тест расчёта](../tests/test_attack_damage_calculation.gd): адресные эталоны,
ошибки, копии стадий и 5880 сочетаний против прежнего порядка операций с exact float `==`.
[Интеграционный тест](../tests/test_attack_damage_d1.gd) сравнивает 57 сценариев
с [эталоном до D1](../tests/fixtures/attack_damage_d1_baseline.json): полные
snapshot/receipt/forecast, RNG/counters/resources и отказы, включая fault-prefix.
Эталон снят запуском настоящего base commit из git archive; hash считается по
Variant bytes, а не округлённому JSON. Обновлять его новым кодом нельзя.
При переходе на [Unit9/Item11](BATTLE_SNAPSHOT_CURRENT.md) все 57 исходных traces
повторены на d18 и сверены с прежними хэшами; затем только форма снимка и порядок
ключей приведены к текущим. Значения/actions/events не пересняты с нового executor.
Доказательство проекции — `test_reports/snapshot-current-20261010/`; в Git остаётся
текущий эталон без старого codec.
При сокращении вложенных форматов 57 traces повторены на `f7521338` и сначала
проверены по каждому существующему хэшу. Затем только версии и явные поля
прежних режимов приведены к [текущей форме](BATTLE_SNAPSHOT_CURRENT.md).
Новый executor не использовался для получения ожидаемых значений;
доказательство — `test_reports/schema-cleanup-20261011/d1-projection-checks.json`.
Сценарии включают три профиля, дроби/знаки/высоту/стойку/minimum,
collision→fall, lethal, лимиты очереди, hostile HP callback и отдельные legacy пути.
Внешние hostile callbacks проверяются в live исполнении: forecast их не копирует.

Оба runner включены в `tools/demo/isolate.py`; команды — [TESTING](TESTING.md).
Полные логи/исходные traces и происхождение baseline:
`test_reports/armor-damage-d1-20260921/` (ignored); итоговая приёмка — [HISTORY](HISTORY.md).

D1 выполняет M2a в минимальной границе §7 D0, без новых модификаторов определения.
Следующий рекомендуемый срез — D2, только по отдельному поручению: точные
API/schema/checkpoints новой брони и рабочий вертикальный сценарий по §9 D0.
Q1–Q6 не переоткрывать; технические детали выбирает ведущий.
