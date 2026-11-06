extends TestCase

func test_rng_deterministic() -> void:
	var a := Rng.new(123)
	var b := Rng.new(123)
	for i in 100:
		check_eq(a.next_u32(), b.next_u32(), "rng расходится")
	var c := Rng.new(124)
	check(Rng.new(123).next_u32() != c.next_u32(), "разные сиды дают одно значение")

func test_rng_range() -> void:
	var r := Rng.new(5)
	for i in 1000:
		var v: int = r.range_int(3, 9)
		check(v >= 3 and v < 9, "вне диапазона: %d" % v)

func test_isqrt() -> void:
	check_eq(IntMath.isqrt(0), 0)
	check_eq(IntMath.isqrt(1), 1)
	check_eq(IntMath.isqrt(99), 9)
	check_eq(IntMath.isqrt(100), 10)
	check_eq(IntMath.isqrt(1000000), 1000)

func test_hash_sensitive() -> void:
	var h1 := Hasher.new()
	h1.add(1)
	h1.add(2)
	var h2 := Hasher.new()
	h2.add(2)
	h2.add(1)
	check(h1.result() != h2.result(), "хеш не зависит от порядка")
