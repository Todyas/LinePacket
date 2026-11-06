class_name IntMath
extends RefCounted
## Целочисленная математика без float.

static func isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var x: int = n
	var y: int = (x + 1) / 2
	while y < x:
		x = y
		y = (x + n / x) / 2
	return x

static func ceil_div(a: int, b: int) -> int:
	return (a + b - 1) / b

static func clampi_(v: int, lo: int, hi: int) -> int:
	return lo if v < lo else (hi if v > hi else v)
