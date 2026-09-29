class_name Fmt
extends RefCounted
## Small text formatting helpers used by the UI.


## 1234567 -> "1,234,567"
static func number(n: int) -> String:
	var digits: String = str(absi(n))
	var out: String = ""
	var count: int = 0
	var i: int = digits.length() - 1
	while i >= 0:
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
		i -= 1
	if n < 0:
		out = "-" + out
	return out


## Seconds -> "m:ss" (or "h:mm:ss" from one hour).
static func duration(seconds: float) -> String:
	var total: int = maxi(int(seconds), 0)
	var h: int = int(float(total) / 3600.0)
	var m: int = int(float(total % 3600) / 60.0)
	var s: int = total % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, s]
	return "%d:%02d" % [m, s]


## Seconds -> compact text for statistics, e.g. "3 h 12 min".
static func playtime(seconds: float) -> String:
	var total: int = maxi(int(seconds), 0)
	var h: int = int(float(total) / 3600.0)
	var m: int = int(float(total % 3600) / 60.0)
	if h > 0:
		return "%d h %02d min" % [h, m]
	if m > 0:
		return "%d min %02d s" % [m, total % 60]
	return "%d s" % total


## Unix time -> "2026-09-29  16:45" in the device's local time zone.
static func date_time(unix_time: int) -> String:
	if unix_time <= 0:
		return "-"
	var tz: Dictionary = Time.get_time_zone_from_system()
	var bias_minutes: int = int(tz.get("bias", 0))
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(unix_time + bias_minutes * 60)
	return "%04d-%02d-%02d  %02d:%02d" % [int(d["year"]), int(d["month"]), int(d["day"]), int(d["hour"]), int(d["minute"])]


static func date_only(unix_time: int) -> String:
	if unix_time <= 0:
		return "-"
	var tz: Dictionary = Time.get_time_zone_from_system()
	var bias_minutes: int = int(tz.get("bias", 0))
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(unix_time + bias_minutes * 60)
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]
