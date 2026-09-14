extends RefCounted
class_name Vitals

## Текущие РЕСУРСЫ юнита: HP и шкала Баланса (R-2).
##
## ЭТО ФИКС ДЕФЕКТА C-2. Раньше текущие HP/Balance хранились как
## `Stat.base_value`, и код делал так:
##
##     hp_stat.set_base_value(hp_stat.get_value() - damage)   # damage_calculator.gd
##
## Поскольку `get_value()` = база + модификаторы, результат ВПЕКАЛ модификаторы
## в базу. Воспроизведение: HP base=10, амулет +5 -> get_value()=15;
## урон 3 -> set_base_value(12) -> get_value()=17. HP ВЫРОС от полученного
## урона; снятие амулета оставляло +2 навсегда.
##
## Здесь `_hp` и `_balance` — ПРОСТЫЕ ЧИСЛА-СОСТОЯНИЯ, а максимумы читаются из
## `StatsBag` (HP_MAX / BALANCE_MAX) как производные значения. Модификаторы
## влияют только на максимум, никогда — на текущее значение. Смешать их уже
## невозможно: это разные объекты с разными типами.
##
## Класс также берёт на себя обязанности, которых раньше не было ни у кого:
##  - КЛАМПЫ: лечение не уходит за максимум, урон не уводит HP ниже нуля
##    (раньше не клампилось нигде);
##  - СМЕРТЬ: `hp <= 0` -> сигнал `died` (раньше смерть не обрабатывалась
##    в принципе, и `InitiativeTimeline` не мог узнать о ней);
##  - СИГНАЛЫ: любое изменение эмитит сигнал, поэтому UI не может "проспать"
##    урон (раньше мутация шла напрямую через `get_stat()` и обходила
##    `stat_changed`).
##
## Сигналы — ЛОКАЛЬНЫЕ (на объекте), а не глобальная шина: `core/**` не имеет
## права ссылаться на автозагрузки (R-3). Проброс в `GameEventBus` — работа
## адаптера на уровне `gameplay/**` или инжектированного `EventSink`.

## Изменилось текущее HP (урон, лечение, установка).
signal hp_changed(old_value: float, new_value: float)

## HP достигло нуля. Эмитится РОВНО ОДИН РАЗ за жизнь (защита от повторного
## срабатывания при добивании уже мёртвого юнита — иначе эффекты вида
## "при смерти союзника" сработали бы дважды).
signal died()

## Изменилось накопление Баланса.
signal balance_changed(old_value: float, new_value: float)

## Баланс достиг BALANCE_MAX: юнит потерял равновесие и должен быть толкнут.
## Сам толчок здесь НЕ выполняется — это работа PushCommand (разделение
## "данные изменились" и "визуальное исполнение").
signal balance_broken()

var _stats: StatsBag
var _hp: float = 0.0
var _balance: float = 0.0
var _is_alive: bool = true


## Receipt хранит собственные записи до сигналов, а не оставленное подписчиком состояние.
class SpatialMutation extends RefCounted:
	var reason: StringName = &""
	var hp_before: float = 0.0
	var hp_after: float = 0.0
	var alive_before: bool = false
	var alive_after: bool = false
	var balance_before: float = 0.0
	var balance_after: float = 0.0
	var balance_max: float = 0.0
	var impact: float = 0.0
	var broke: bool = false
	var hp_written: bool = false
	var balance_written: bool = false
	var death_written: bool = false
	var broken_emitted: bool = false


func _spatial_receipt() -> SpatialMutation:
	var receipt := SpatialMutation.new()
	receipt.hp_before = _hp
	receipt.hp_after = _hp
	receipt.alive_before = _is_alive
	receipt.alive_after = _is_alive
	receipt.balance_before = _balance
	receipt.balance_after = _balance
	return receipt


func apply_spatial_damage(amount: float, checkpoint: Callable) -> SpatialMutation:
	var receipt := _spatial_receipt()
	if not checkpoint.is_valid() or not is_finite(amount) or amount < 0.0 or not _is_alive or not is_finite(_hp) or _hp < 0.0 or not is_finite(_balance) or _balance < 0.0:
		receipt.reason = &"spatial/invalid_mutation"
		return receipt
	if amount == 0.0:
		receipt.reason = checkpoint.call(&"hp_done")
		return receipt
	receipt.hp_after = maxf(0.0, receipt.hp_before - amount)
	_hp = receipt.hp_after
	receipt.hp_written = true
	if not is_equal_approx(receipt.hp_before, receipt.hp_after):
		hp_changed.emit(receipt.hp_before, receipt.hp_after)
	receipt.reason = checkpoint.call(&"hp_written")
	if receipt.reason != &"":
		return receipt
	# Нельзя завершать смерть по HP, которое callback изменил после нашей записи.
	if receipt.hp_after <= 0.0:
		_is_alive = false
		receipt.alive_after = false
		receipt.death_written = true
		died.emit()
		receipt.reason = checkpoint.call(&"death_written")
		if receipt.reason != &"":
			return receipt
	receipt.reason = checkpoint.call(&"hp_done")
	return receipt


func add_spatial_impact(amount: float, checkpoint: Callable) -> SpatialMutation:
	var receipt := _spatial_receipt()
	if not checkpoint.is_valid() or not is_finite(amount) or amount < 0.0 or not is_finite(_hp) or _hp < 0.0 or not is_finite(_balance) or _balance < 0.0 or _stats == null or _stats.get_script() != StatsBag:
		receipt.reason = &"spatial/invalid_mutation"
		return receipt
	var stats_copy := StatsBag.from_snapshot_dict(_stats.to_snapshot_dict())
	if stats_copy == null or not stats_copy.has_stat(StatTypes.StatType.BALANCE_MAX):
		receipt.reason = &"spatial/invalid_mutation"
		return receipt
	receipt.balance_max = stats_copy.get_value(StatTypes.StatType.BALANCE_MAX)
	receipt.impact = amount
	if not is_finite(receipt.balance_max):
		receipt.reason = &"spatial/invalid_mutation"
		return receipt
	if amount == 0.0 or receipt.balance_max <= 0.0 or not receipt.alive_before:
		receipt.reason = checkpoint.call(&"balance_done")
		return receipt
	var total := receipt.balance_before + amount
	if not is_finite(total):
		receipt.reason = &"spatial/invalid_mutation"
		return receipt
	receipt.broke = total >= receipt.balance_max
	receipt.balance_after = 0.0 if receipt.broke else total
	_balance = receipt.balance_after
	receipt.balance_written = true
	if not is_equal_approx(receipt.balance_before, receipt.balance_after):
		balance_changed.emit(receipt.balance_before, receipt.balance_after)
	receipt.reason = checkpoint.call(&"balance_written")
	if receipt.reason != &"":
		return receipt
	if receipt.broke:
		receipt.broken_emitted = true
		balance_broken.emit()
	receipt.reason = checkpoint.call(&"balance_done")
	return receipt


## `p_stats` обязателен: из него читаются HP_MAX/BALANCE_MAX. Если
## `p_start_full` = true, HP инициализируется максимумом.
func _init(p_stats: StatsBag, p_start_full: bool = true) -> void:
	_stats = p_stats
	if p_start_full and _stats != null:
		_hp = _stats.get_value(StatTypes.StatType.HP_MAX)


# --- Чтение ----------------------------------------------------------------

func get_hp() -> float:
	return _hp


func get_hp_max() -> float:
	if _stats == null:
		return 0.0
	return _stats.get_value(StatTypes.StatType.HP_MAX)


## Доля HP в [0..1] — для полосок здоровья и AI-оценки "добить раненого".
func get_hp_ratio() -> float:
	var max_hp := get_hp_max()
	if max_hp <= 0.0:
		return 0.0
	return clampf(_hp / max_hp, 0.0, 1.0)


func get_balance() -> float:
	return _balance


func get_balance_max() -> float:
	if _stats == null:
		return 0.0
	return _stats.get_value(StatTypes.StatType.BALANCE_MAX)


func get_balance_ratio() -> float:
	var max_balance := get_balance_max()
	if max_balance <= 0.0:
		return 0.0
	return clampf(_balance / max_balance, 0.0, 1.0)


func is_alive() -> bool:
	return _is_alive


# --- Мутация: HP -----------------------------------------------------------

## Наносит урон. Возвращает ФАКТИЧЕСКИ снятое количество HP (может быть
## меньше запрошенного, если HP не хватило) — нужно для эффектов вида
## "вампиризм по нанесённому урону", чтобы они не лечили за оверкилл.
func apply_damage(amount: float) -> float:
	if amount <= 0.0 or not _is_alive:
		return 0.0

	var old_hp := _hp
	_hp = maxf(0.0, _hp - amount)
	var dealt := old_hp - _hp

	if not is_equal_approx(old_hp, _hp):
		hp_changed.emit(old_hp, _hp)

	if _hp <= 0.0 and _is_alive:
		_is_alive = false
		died.emit()

	return dealt


## Лечит, КЛАМПЯ по HP_MAX. Возвращает фактически восстановленное количество
## (0.0 при полном HP) — чтобы UI не показывал "+5" там, где вылечило 0.
## Мёртвых не лечит: воскрешение — отдельная явная механика (`revive`).
func heal(amount: float) -> float:
	if amount <= 0.0 or not _is_alive:
		return 0.0

	var max_hp := get_hp_max()
	var old_hp := _hp
	_hp = minf(_hp + amount, max_hp)
	var healed := _hp - old_hp

	if healed > 0.0:
		hp_changed.emit(old_hp, _hp)
	return healed


## Прямая установка HP (загрузка сейва, читы, скриптовые события).
## НЕ эмитит `died` — состояние жизни задаётся явно через `_is_alive`
## при десериализации, чтобы загрузка сейва не триггерила эффекты смерти.
func set_hp(value: float) -> void:
	var old_hp := _hp
	_hp = clampf(value, 0.0, get_hp_max())
	if not is_equal_approx(old_hp, _hp):
		hp_changed.emit(old_hp, _hp)


func revive(hp_ratio: float = 1.0) -> void:
	_is_alive = true
	var old_hp := _hp
	_hp = clampf(get_hp_max() * hp_ratio, 0.0, get_hp_max())
	if not is_equal_approx(old_hp, _hp):
		hp_changed.emit(old_hp, _hp)


# --- Мутация: Balance ------------------------------------------------------

## Накапливает импакт. При достижении BALANCE_MAX сбрасывает шкалу в 0 и
## возвращает true (юнит "сломан", должен быть толкнут).
##
## Сброс в 0 — сохранённое правило из модуля 6: шкала начинает копиться заново.
func add_impact(amount: float) -> bool:
	if amount <= 0.0 or not _is_alive:
		return false

	var max_balance := get_balance_max()
	var old_balance := _balance

	# BALANCE_MAX <= 0 означает "юнит неуязвим к дисбалансу" (статуи, боссы).
	if max_balance <= 0.0:
		return false

	var broke := old_balance + amount >= max_balance
	_balance = 0.0 if broke else old_balance + amount

	if not is_equal_approx(old_balance, _balance):
		balance_changed.emit(old_balance, _balance)
	if broke:
		balance_broken.emit()
	return broke


## Проверка БЕЗ мутации — для превью (R-6): UI должен показать "этот удар
## сломает баланс" не меняя состояние. Раньше это была
## `BalanceSystem.would_break()`; логика сохранена, но теперь живёт рядом с
## данными, поэтому превью и применение не могут разойтись.
func would_break(added_impact: float) -> bool:
	var max_balance := get_balance_max()
	if max_balance <= 0.0:
		return false
	return _balance + added_impact >= max_balance


func reset_balance() -> void:
	var old_balance := _balance
	_balance = 0.0
	if not is_equal_approx(old_balance, _balance):
		balance_changed.emit(old_balance, _balance)


func set_balance(value: float) -> void:
	var old_balance := _balance
	_balance = maxf(0.0, value)
	if not is_equal_approx(old_balance, _balance):
		balance_changed.emit(old_balance, _balance)


# --- Сериализация (R-4) ----------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"hp": _hp,
		"balance": _balance,
		"is_alive": _is_alive,
	}


## `p_stats` передаётся отдельно: Vitals не владеет статами, а ссылается на
## них (максимумы — производные значения владельца).
static func from_dict(data: Dictionary, p_stats: StatsBag) -> Vitals:
	var vitals := Vitals.new(p_stats, false)
	var hp: float = data.get("hp", 0.0)
	var balance: float = data.get("balance", 0.0)
	var alive: bool = data.get("is_alive", true)
	vitals._hp = hp
	vitals._balance = balance
	vitals._is_alive = alive
	return vitals
