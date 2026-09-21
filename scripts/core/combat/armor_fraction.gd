extends RefCounted
class_name ArmorFraction

const MAX_INT: int = 9223372036854775807
const MIN_INT: int = -9223372036854775808

var numerator: int = 0
var denominator: int = 1
var valid: bool = true

static func make(n: int, d: int = 1) -> ArmorFraction:
	var result := ArmorFraction.new()
	if d == 0 or n == MIN_INT or d == MIN_INT:
		result.valid = false
		return result
	if d < 0:
		n = -n
		d = -d
	var divisor := _gcd(abs(n), d)
	result.numerator = n / divisor
	result.denominator = d / divisor
	return result

func add(other: ArmorFraction) -> ArmorFraction:
	var result := ArmorFraction.new()
	if not valid or other == null or not other.valid:
		result.valid = false
		return result
	var left_factor := denominator / _gcd(denominator, other.denominator)
	var right_factor := other.denominator / _gcd(denominator, other.denominator)
	var left: Variant = _safe_mul(numerator, right_factor)
	var right: Variant = _safe_mul(other.numerator, left_factor)
	if left == null or right == null:
		result.valid = false
		return result
	var sum: Variant = _safe_add(int(left), int(right))
	if sum == null:
		result.valid = false
		return result
	var den: Variant = _safe_mul(denominator, right_factor)
	if den == null:
		result.valid = false
		return result
	return make(int(sum), int(den))

func multiply(other: ArmorFraction) -> ArmorFraction:
	var result := ArmorFraction.new()
	if not valid or other == null or not other.valid:
		result.valid = false
		return result
	if numerator == 0 or other.numerator == 0:
		return make(0, 1)
	var g1 := _gcd(abs(numerator), other.denominator)
	var g2 := _gcd(abs(other.numerator), denominator)
	var a := numerator / g1
	var b := other.numerator / g2
	var c := denominator / g2
	var d := other.denominator / g1
	var top: Variant = _safe_mul(a, b)
	var bottom: Variant = _safe_mul(c, d)
	if top == null or bottom == null:
		result.valid = false
		return result
	return make(int(top), int(bottom))

func floor_value() -> int:
	if not valid or numerator < 0:
		return 0
	return numerator / denominator

static func from_decimal(value: float) -> ArmorFraction:
	var result := ArmorFraction.new()
	if not is_finite(value):
		result.valid = false
		return result
	var text := str(value)
	if text.find("e") >= 0 or text.find("E") >= 0:
		result.valid = false
		return result
	var dot := text.find(".")
	var decimals := 0
	if dot >= 0:
		decimals = text.length() - dot - 1
	if decimals > 6:
		result.valid = false
		return result
	var normalized := text
	if dot >= 0:
		normalized = text.substr(0, dot) + text.substr(dot + 1)
	var negative := normalized.begins_with("-")
	var digits := normalized.trim_prefix("-")
	var parsed := 0
	for character: String in digits:
		if character < "0" or character > "9": return make(1, 0)
		var digit := character.unicode_at(0) - 48
		if parsed > (MAX_INT - digit) / 10: return make(1, 0)
		parsed = parsed * 10 + digit
	if negative: parsed = -parsed
	var scale := 1
	for i in range(decimals):
		scale *= 10
	if float(parsed) / float(scale) != value: return make(1, 0)
	return make(parsed, scale)

static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var remainder := a % b
		a = b
		b = remainder
	return max(a, 1)

static func _safe_add(a: int, b: int) -> Variant:
	if b > 0 and a > MAX_INT - b:
		return null
	if b < 0 and a < MIN_INT - b:
		return null
	return a + b

static func _safe_mul(a: int, b: int) -> Variant:
	if a == 0 or b == 0:
		return 0
	if a == MIN_INT or b == MIN_INT:
		return null
	if abs(a) > MAX_INT / abs(b):
		return null
	return a * b
