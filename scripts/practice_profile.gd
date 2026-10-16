extends RefCounted
## Only official phase reach is persisted in M3. Run results stay in memory.

static func load_phase(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"phase": 1, "error": ""}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"phase": 1, "error": "Practice progress could not be read."}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"phase": 1, "error": "Practice progress was invalid; P1 is available."}
	var data = parser.data
	if not data is Dictionary or data.get("schema", 0) != 1:
		return {"phase": 1, "error": "Practice progress was invalid; P1 is available."}
	var phase_value = data.get("max_phase", null)
	if not phase_value is float and not phase_value is int:
		return {"phase": 1, "error": "Practice progress was invalid; P1 is available."}
	return {"phase": clampi(int(data.max_phase), 1, 5), "error": ""}


static func save_phase(path: String, phase: int) -> Error:
	var absolute := ProjectSettings.globalize_path(path)
	var folder := absolute.get_base_dir()
	var error := DirAccess.make_dir_recursive_absolute(folder)
	if error != OK:
		return error
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"schema": 1, "max_phase": clampi(phase, 1, 5)}))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return write_error
	return DirAccess.rename_absolute(temporary, absolute)
