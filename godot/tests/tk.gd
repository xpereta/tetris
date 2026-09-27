# tests/tk.gd — minimal test kit: per-test PASS/FAIL lines + global counters.
# Each test function calls TK.begin(name) ... TK.end(); assertions in between
# accumulate failure messages for that one test.

extends RefCounted


static var passed := 0
static var failed := 0
static var _failures: Array = []
static var _name := ""


static func begin(test_name: String) -> void:
	_name = test_name
	_failures.clear()


static func end() -> void:
	if _failures.is_empty():
		passed += 1
		print("PASS ", _name)
	else:
		failed += 1
		for m in _failures:
			printerr("FAIL ", _name, " :: ", str(m))


static func check(cond: bool, msg := "") -> void:
	if not cond:
		_failures.append(str(msg) if str(msg) != "" else "assertion failed")


static func ok(cond: bool, msg := "") -> void:
	check(cond, msg)


static func eq(actual, expected, msg := "") -> void:
	if actual != expected:
		var base := str(msg) if str(msg) != "" else "values differ"
		_failures.append("%s (got %s, want %s)" % [base, str(actual), str(expected)])


static func neq(actual, unexpected, msg := "") -> void:
	if actual == unexpected:
		var base := str(msg) if str(msg) != "" else "values should differ"
		_failures.append("%s (got %s, which must not equal it)" % [base, str(actual)])
