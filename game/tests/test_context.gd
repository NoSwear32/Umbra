class_name TestContext
extends RefCounted
## Minimal assertion helper shared by all test suites.

var passed: int = 0
var failed: int = 0
var current_suite: String = ""
var failures: PackedStringArray = PackedStringArray()


func suite(suite_name: String) -> void:
	current_suite = suite_name
	print("  [suite] %s" % suite_name)


func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		var line: String = "FAIL [%s] %s" % [current_suite, message]
		failures.append(line)
		printerr(line)


func eq(actual: Variant, expected: Variant, message: String) -> void:
	if typeof(actual) == typeof(expected) and actual == expected:
		passed += 1
	elif (actual is float or actual is int) and (expected is float or expected is int) and float(actual) == float(expected):
		passed += 1
	else:
		failed += 1
		var line: String = "FAIL [%s] %s  (expected %s, got %s)" % [current_suite, message, str(expected), str(actual)]
		failures.append(line)
		printerr(line)


func near(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) <= tolerance * maxf(1.0, absf(expected)):
		passed += 1
	else:
		failed += 1
		var line: String = "FAIL [%s] %s  (expected %.9f, got %.9f)" % [current_suite, message, expected, actual]
		failures.append(line)
		printerr(line)


func fail(message: String) -> void:
	check(false, message)


## Loads a JSON file from the golden folder.
static func load_golden(file_name: String) -> Variant:
	var text: String = FileAccess.get_file_as_string("res://tests/golden/%s" % file_name)
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data
