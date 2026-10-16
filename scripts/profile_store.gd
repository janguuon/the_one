extends RefCounted
## Versioned local progression only. A running battle is deliberately never saved.
## Save a verified temporary file, preserve the previous valid profile, then replace.

const SCHEMA_VERSION: int = 1
const InputSettings = preload("res://scripts/input_settings.gd")
const MAX_RECORDS: int = 100
const MAX_SAFE_INTEGER: int = 9007199254740991
const WEAPON_IDS: Array[String] = ["W01", "W02", "W03", "W04", "W05"]
const PATTERN_IDS: Array[String] = [
	"claw", "rupture", "pulse", "territory", "rings", "horizon",
	"heartbeat", "dash", "thrust", "echo", "footprints", "fractures",
	"execution", "last_horizon", "nameless_end"
]
const ELEMENT_IDS: Array[String] = ["fire", "frost", "lightning", "void"]
const OATH_IDS: Array[String] = [
	"O01", "O02", "O03", "O04", "O05", "O06",
	"O07", "O08", "O09", "O10", "O11", "O12"
]


static func defaults() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"settings": InputSettings.defaults(),
		"discovered_weapons": ["W01"],
		"highest_phase": 1,
		"seen_patterns": [],
		"pattern_hit_counts": {},
		"official_records": [],
		"best_record": {}
	}


static func sanitize_profile(value: Variant) -> Dictionary:
	var profile := defaults()
	var issues: Array[String] = []
	if not value is Dictionary:
		return {"profile": profile, "error": "프로필 형식이 잘못되어 기본값을 사용합니다.", "valid": false}
	if not _integer(value.get("schema")) or int(value.schema) != SCHEMA_VERSION:
		return {"profile": profile, "error": "지원하지 않는 프로필 버전입니다.", "valid": false}
	var settings_result := InputSettings.sanitize(value.get("settings", {}))
	profile.settings = settings_result.settings
	if settings_result.repaired:
		issues.append("설정")
	profile.discovered_weapons = _ids(value.get("discovered_weapons", ["W01"]), WEAPON_IDS, issues)
	if not "W01" in profile.discovered_weapons:
		profile.discovered_weapons.push_front("W01")
	var phase: Variant = value.get("highest_phase", 1)
	if _integer(phase):
		profile.highest_phase = clampi(int(phase), 1, 5)
		if profile.highest_phase != int(phase):
			issues.append("도달 페이즈")
	else:
		issues.append("도달 페이즈")
	profile.seen_patterns = _ids(value.get("seen_patterns", []), PATTERN_IDS, issues)
	var hit_counts: Variant = value.get("pattern_hit_counts", {})
	if hit_counts is Dictionary:
		for id in hit_counts:
			var count: Variant = hit_counts[id]
			if id in PATTERN_IDS and _integer(count) and int(count) >= 0 and int(count) <= 1000000:
				profile.pattern_hit_counts[id] = int(count)
			else:
				issues.append("패턴 경험")
	else:
		issues.append("패턴 경험")
	var records: Variant = value.get("official_records", [])
	if records is Array:
		for raw in records:
			var record := _record(raw, issues)
			if not record.is_empty():
				profile.official_records.append(record)
	else:
		issues.append("정식 기록")
	var previous: Dictionary = {}
	var raw_best: Variant = value.get("best_record", {})
	if raw_best is Dictionary and not raw_best.is_empty():
		previous = _record(raw_best, issues)
		if previous.get("result") != "victory":
			previous = {}
			issues.append("최고 기록")
	elif not raw_best is Dictionary:
		issues.append("최고 기록")
	# Derive the all-time best before pruning the bounded recent-record history.
	profile.best_record = best_record(profile.official_records, previous)
	if profile.official_records.size() > MAX_RECORDS:
		profile.official_records = profile.official_records.slice(-MAX_RECORDS)
	return {
		"profile": profile,
		"error": "일부 프로필 항목을 복구했습니다." if not issues.is_empty() else "",
		"valid": true
	}


static func best_record(records: Array, previous: Dictionary = {}) -> Dictionary:
	var best: Dictionary = previous.duplicate(true) if previous.get("result") == "victory" else {}
	for record in records:
		if not record is Dictionary or record.get("result") != "victory":
			continue
		if best.is_empty() or float(record.get("seconds", 0)) < float(best.get("seconds", 0)):
			best = record.duplicate(true)
		elif float(record.get("seconds", 0)) == float(best.get("seconds", 0)) and int(record.get("ticks", 0)) < int(best.get("ticks", 0)):
			best = record.duplicate(true)
	return best


static func load_profile(path: String, legacy_path: String = "") -> Dictionary:
	var main := _read_profile(path)
	if main.valid:
		return {"profile": main.profile, "error": main.error}
	var backup := _read_profile(path + ".bak")
	if backup.valid:
		return {"profile": backup.profile, "error": "프로필을 마지막 정상 백업에서 복구했습니다."}
	# Migration is only permitted when the new profile has never been created.
	# A damaged current profile must not silently consume stale legacy progression.
	if not main.exists and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)) and not legacy_path.is_empty():
		var migrated := _legacy_profile(legacy_path)
		if migrated.valid:
			var error := save_profile(path, migrated.profile)
			return {
				"profile": migrated.profile,
				"error": "이전 연습 해금을 가져왔지만 저장하지 못했습니다." if error != OK else ""
			}
		if migrated.exists:
			return {"profile": defaults(), "error": "이전 연습 저장이 잘못되어 기본값을 사용합니다."}
	if main.exists or backup.exists or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		return {"profile": defaults(), "error": "프로필을 읽을 수 없어 안전한 기본값을 사용합니다."}
	return {"profile": defaults(), "error": ""}


static func save_profile(path: String, value: Dictionary) -> Error:
	var sanitized := sanitize_profile(value)
	if not sanitized.valid:
		return ERR_INVALID_DATA
	var absolute := ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(absolute):
		return ERR_CANT_CREATE
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK:
		return error
	var temporary := absolute + ".tmp"
	error = _write_verified(temporary, sanitized.profile)
	if error != OK:
		return error
	var current := _read_profile(path)
	if current.valid:
		# Do not rotate a corrupted main over a good backup. Backup itself uses a
		# temporary file so a failed write never destroys the existing backup.
		var backup_temporary := absolute + ".bak.tmp"
		error = _write_verified(backup_temporary, current.profile)
		if error != OK:
			_remove_temporary(temporary)
			return error
		error = DirAccess.rename_absolute(backup_temporary, absolute + ".bak")
		if error != OK:
			_remove_temporary(temporary)
			_remove_temporary(backup_temporary)
			return error
	# Godot's rename replaces an existing file. Never remove the main first:
	# failed replacement keeps the last good main and backup available.
	error = DirAccess.rename_absolute(temporary, absolute)
	if error != OK:
		_remove_temporary(temporary)
	return error


static func _write_verified(path: String, profile: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(profile, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		_remove_temporary(path)
		return error
	var verified := _read_profile(path)
	if not verified.valid or not str(verified.error).is_empty():
		_remove_temporary(path)
		return ERR_FILE_CORRUPT
	return OK


static func _read_profile(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"exists": false, "valid": false, "profile": defaults(), "error": ""}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"exists": true, "valid": false, "profile": defaults(), "error": "프로필을 읽을 수 없습니다."}
	var content := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(content) != OK:
		return {"exists": true, "valid": false, "profile": defaults(), "error": "프로필이 손상되었습니다."}
	var result := sanitize_profile(parser.data)
	result["exists"] = true
	return result


static func _legacy_profile(path: String) -> Dictionary:
	var result := {"exists": FileAccess.file_exists(path), "valid": false, "profile": defaults()}
	if not result.exists:
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK or not parser.data is Dictionary:
		return result
	var data: Dictionary = parser.data
	if not _integer(data.get("schema")) or int(data.schema) != 1 or not _integer(data.get("max_phase")):
		return result
	result.profile.highest_phase = clampi(int(data.max_phase), 1, 5)
	result.valid = true
	return result


static func _record(value: Variant, issues: Array[String]) -> Dictionary:
	if not value is Dictionary or not value.get("result") in ["victory", "dead", "abandoned"]:
		issues.append("정식 기록")
		return {}
	var phase: Variant = value.get("phase", 1)
	if not _integer(phase) or int(phase) < 1 or int(phase) > 5 or (value.result == "victory" and int(phase) != 5):
		issues.append("정식 기록")
		return {}
	var seed_value: Variant = value.get("seed", 1)
	var ticks: Variant = value.get("ticks", 0)
	var seconds: Variant = value.get("seconds", 0.0)
	if not _integer(seed_value) or not _integer(ticks) or int(ticks) < 0 or not _finite_number(seconds) or float(seconds) < 0.0:
		issues.append("정식 기록")
		return {}
	var weapon: Variant = value.get("weapon_id", "W01")
	if not weapon is String or not weapon in WEAPON_IDS:
		weapon = "W01"
		issues.append("무기 ID")
	var oaths := _ids(value.get("oaths", []), OATH_IDS, issues)
	if oaths.size() > 3:
		oaths = oaths.slice(0, 3)
		issues.append("각인")
	var element_uses := {"fire": 0, "frost": 0, "lightning": 0, "void": 0}
	var raw_uses: Variant = value.get("element_uses", {})
	if raw_uses is Dictionary:
		for element in ELEMENT_IDS:
			var count: Variant = raw_uses.get(element, 0)
			if _integer(count) and int(count) >= 0:
				element_uses[element] = int(count)
			else:
				issues.append("기운 기록")
	else:
		issues.append("기운 기록")
	return {
		"result": value.result, "phase": int(phase), "seed": int(seed_value),
		"seconds": float(seconds), "ticks": int(ticks), "weapon_id": weapon,
		"oaths": oaths, "element_uses": element_uses
	}


static func _ids(value: Variant, allowed: Array[String], issues: Array[String]) -> Array:
	var result: Array = []
	if not value is Array:
		issues.append("ID 목록")
		return result
	for id in value:
		if id is String and id in allowed and not id in result:
			result.append(id)
		else:
			issues.append("ID 목록")
	return result


static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= float(MAX_SAFE_INTEGER)


static func _integer(value: Variant) -> bool:
	return _finite_number(value) and float(value) == floor(float(value))


static func _remove_temporary(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
