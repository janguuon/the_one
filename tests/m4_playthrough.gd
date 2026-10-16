extends SceneTree
## Full normal-input runs. Build choices use only the offered oath menu.
## No health, damage, position, resource, enemy, or phase injection is allowed.
const Combat = preload("res://scripts/combat_model.gd")
const Policy = preload("res://tests/m3_playthrough.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var failed = false
	var weapons = ["W01", "W02", "W03", "W04", "W05"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--weapon="):
			weapons = [arg.trim_prefix("--weapon=")]
	for weapon_id in weapons:
		var game = Combat.new()
		game.reset(7, "official", 1, weapon_id)
		var choices: Array[String] = []
		var patterns: Dictionary = {}
		var kinds: Dictionary = {}
		var wanted = {"W01":["O05","O06","O10"],"W02":["O04","O08","O09"],"W03":["O03","O07","O12"],"W04":["O02","O07","O11"],"W05":["O04","O05","O12"]}[weapon_id]
		for iteration in range(220000):
			if game.result != "":
				break
			if game.selection_pending:
				var chosen = ""
				for candidate in wanted:
					if game.oath_candidates.has(candidate):
						chosen = candidate
						break
				if chosen == "" and not game.oath_candidates.is_empty():
					chosen = game.oath_candidates[0]
				choices.append(chosen)
				if not game.choose_oath(chosen):
					failed = true
					break
				continue
			var command = Policy.decide(game)
			game.step(command)
			patterns[game.boss_pattern] = true
			for event in game.events:
				if event.type == "attack":
					kinds[event.kind] = true
				elif event.type == "player_hit":
					print("M4_HIT weapon=%s phase=%d pattern=%s hp=%.3f age=%d pos=%s boss=%s facing=%s command=%s" % [weapon_id, game.phase_id, game.boss_pattern, game.player_hp, game.boss_age, str(game.player_pos), str(game.boss_pos), str(game.boss_facing), str(command)])
		print("M4_PLAYTHROUGH weapon=%s result=%s ticks=%d hp=%.3f damage=%.3f patterns=%d choices=%s elements=%s kinds=%s" % [weapon_id, game.result, game.tick, game.player_hp, game.damage_dealt, patterns.size(), str(choices), str(game.collected_elements), str(kinds.keys())])
		if game.result != "victory" or game.phase_history != [1,2,3,4,5] or absf(game.damage_dealt - 6000.0) > 0.002 or choices.size() != 3 or patterns.size() != 15:
			failed = true
	quit(1 if failed else 0)
