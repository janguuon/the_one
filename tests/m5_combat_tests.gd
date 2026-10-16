extends SceneTree
const Combat = preload("res://scripts/combat_model.gd")
var checks = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + message)
	if not ok: failures.append(message)

func _run() -> void:
	for entry in [[3,"heartbeat",81,"2번째 타격",22.0],[4,"echo",111,"2번째 잔향",24.0]]:
		var game = Combat.new()
		game.reset(7,"practice",int(entry[0]))
		game.player_pos = Vector2(420,184)
		game.boss_pos = Vector2(320,184)
		game.debug_start_pattern(entry[1])
		for tick in range(1,int(entry[2])):
			game.step()
		_check(game.player_hp == 100.0,"Earlier strike is avoided before the named later hit")
		game.player_pos = game.boss_pos + game.boss_facing * 40.0
		game.step()
		_check(is_equal_approx(game.player_hp,100.0-float(entry[4])),"The real later hit keeps its designed damage")
		_check(game.cause.contains(entry[3]),"The actual damage cause identifies the later strike/echo")
		_check(game.cause.begins_with(game.pattern_name()),"The readable cause preserves its pattern name for codex matching")
	print("M5 COMBAT TESTS: %d checks, %d failures" % [checks,failures.size()])
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
