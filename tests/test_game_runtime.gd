extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var game: Node = scene.instantiate()
	root.add_child(game)
	await process_frame
	assert(game.get_node_or_null("AnimatedWater") != null)
	assert(game.get_node_or_null("PlayerBoat") != null)
	assert(game.get("boat_shadow") != null)
	assert(game.get_node_or_null("PlayerBoat/BoatVisual/BlenderBoatAsset") != null)
	assert(game.get("authored_arch") != null)
	assert(game.get("authored_buoy") != null)
	assert(game.get("authored_reef") != null)
	assert((game.get("buoys") as Array).size() == 4)
	var first_buoy_node: Node3D = game.get_node("MarkerBuoy_00")
	assert(first_buoy_node.get_child_count() > 0)
	assert((first_buoy_node.get_child(0) as Node3D).scale.x > 1.2)
	assert((game.get("gates") as Array).size() == 9)
	var first_gate_node: Node3D = (game.get("gates") as Array)[0]["node"]
	assert(first_gate_node.get_child_count() > 0)
	assert(first_gate_node.get_node_or_null("GateLight") != null)
	assert(first_gate_node.get_node_or_null("StartFinishLine") != null)
	assert((game.get("boost_pads") as Array).size() == 4)
	assert(not (game.get("obstacles") as Array).is_empty())
	assert(game.get_node_or_null("HUD") != null)
	assert(game.get_node_or_null("EngineAudio") != null)
	assert(game.get("boost_label") != null)
	assert(game.get("flow_label") != null)
	assert(game.get_node_or_null("NextGateIndicator") != null)
	assert((game.get_node("NextGateIndicator") as Node3D).visible)
	assert(game.get("wake_trail") != null)
	var previous_layout := -1
	for _route_attempt in range(24):
		game.call("_generate_course")
		var route_layout: int = game.get("current_course_layout")
		if previous_layout >= 0:
			assert(route_layout != previous_layout)
		previous_layout = route_layout
		var route_gates: Array = game.get("gates")
		for a in range(route_gates.size()):
			for b in range(a + 1, route_gates.size()):
				assert(route_gates[a]["position"].distance_to(route_gates[b]["position"]) > 10.0)
			for obstacle in (game.get("obstacles") as Array):
				var gate_position: Vector3 = route_gates[a]["position"]
				var obstacle_center: Vector2 = obstacle["center"]
				assert(Vector2(gate_position.x, gate_position.z).distance_to(obstacle_center) > float(obstacle["radius"]) + 1.0)
		for segment_index in range(route_gates.size()):
			var segment_start: Vector3 = route_gates[segment_index]["position"]
			var segment_end: Vector3 = route_gates[(segment_index + 1) % route_gates.size()]["position"]
			var segment_clear: bool = game.call("_course_segment_clear", segment_start, segment_end)
			if not segment_clear:
				print("INVALID_ROUTE attempt=%d layout=%d segment=%d start=%s end=%s" % [_route_attempt, route_layout, segment_index, segment_start, segment_end])
			assert(segment_clear)
	var initial_route_gate: Vector3 = (game.get("gates") as Array)[1]["position"]
	game.call("_generate_course")
	var regenerated_route_gate: Vector3 = (game.get("gates") as Array)[1]["position"]
	assert(initial_route_gate.distance_to(regenerated_route_gate) > 0.1)
	game.call("_reset_player")
	var player_node: Node3D = game.get("player")
	var first_gate: Dictionary = (game.get("gates") as Array)[0]
	player_node.position = first_gate["position"]
	game.set("heading", PI)
	game.call("_update_course")
	assert((game.get("course_index") as int) == 0)
	game.set("heading", 0.0)
	game.call("_update_course")
	assert((game.get("course_index") as int) == 1)
	game.call("_update_course")
	assert((first_gate["node"] as Node3D).scale.x < 1.0)
	var second_gate: Dictionary = (game.get("gates") as Array)[1]
	player_node.position = second_gate["position"]
	game.set("heading", atan2(second_gate["forward"].x, -second_gate["forward"].z))
	var gate_right := Vector3(cos(game.get("heading") as float), 0.0, sin(game.get("heading") as float))
	game.set("velocity", gate_right * 3.0)
	game.call("_update_course")
	assert((game.get("event_text") as String) == "DRIFT CHECKPOINT")
	var first_pad: Dictionary = (game.get("boost_pads") as Array)[0]
	player_node.position = first_pad["position"]
	game.set("boost_charge", 0.0)
	game.call("_check_boost_pads")
	assert((game.get("boost_charge") as float) > 0.0)
	assert((game.get("boost_heat") as float) > 0.5)
	assert((game.get("audio_burst") as float) > 0.0)
	assert((game.get("boost_pads") as Array)[0]["used"])
	game.set("heading", 0.0)
	var drift_forward := Vector3(0.0, 0.0, -1.0)
	player_node.position = Vector3(0.0, 0.0, 0.0)
	game.set("boost_charge", 0.0)
	game.set("drift_charge", 0.8)
	game.set("drift_was_down", true)
	game.set("velocity", Vector3(4.0, 0.0, -15.0))
	game.set("jump_cooldown", 100.0)
	game.set("skip_cooldown", 100.0)
	game.call("_update_player", 0.016)
	assert((game.get("boost_charge") as float) > 20.0)
	assert((game.get("velocity") as Vector3).dot(drift_forward) > 16.0)
	assert((game.get("drift_boost_timer") as float) > 0.0)
	assert((game.get("event_text") as String) == "SLINGSHOT")
	assert((game.get("drift_spark_left") as MeshInstance3D).visible)
	assert((game.get("flow_score") as int) > 0)
	assert((game.get("flow_combo") as float) > 1.0)
	player_node.position = Vector3.ZERO
	game.set("velocity", Vector3(0.0, 0.0, -16.0))
	game.set("height", 0.0)
	game.set("jump_cooldown", 100.0)
	game.set("skip_cooldown", 100.0)
	game.set("drift_was_down", false)
	Input.action_press("drift")
	Input.action_press("steer_right")
	game.call("_update_player", 0.2)
	Input.action_release("drift")
	Input.action_release("steer_right")
	var drift_right := Vector3(cos(game.get("heading") as float), 0.0, sin(game.get("heading") as float))
	var drift_dot: float = (game.get("velocity") as Vector3).dot(drift_right)
	if drift_dot <= 1.0:
		print("DRIFT_INPUT_FAIL heading=%f velocity=%s dot=%f" % [game.get("heading"), game.get("velocity"), drift_dot])
	assert(drift_dot > 1.0)
	var first_obstacle: Dictionary = (game.get("obstacles") as Array)[0]
	var obstacle_center: Vector2 = first_obstacle["center"]
	var obstacle_radius: float = first_obstacle["radius"]
	player_node.position = Vector3(obstacle_center.x + obstacle_radius * 0.5, 0.0, obstacle_center.y)
	game.set("velocity", Vector3(-8.0, 0.0, 0.0))
	game.call("_resolve_obstacles")
	assert(Vector2(player_node.position.x - obstacle_center.x, player_node.position.z - obstacle_center.y).length() >= obstacle_radius - 0.01)
	assert((game.get("flow_combo") as float) == 1.0)
	Input.action_press("move_forward")
	for _i in range(30):
		await process_frame
	var speed: Vector3 = game.get("velocity")
	assert(speed.length() > 1.0)
	assert((game.get("wake_trail") as MeshInstance3D).visible)
	Input.action_release("move_forward")
	var charge_before: float = game.get("boost_charge")
	Input.action_press("boost")
	for _i in range(10):
		await process_frame
	assert((game.get("boost_charge") as float) < charge_before)
	assert((game.get("event_text") as String) == "BOOST")
	Input.action_release("boost")
	game.call("_reset_player")
	Input.action_press("move_forward")
	for _i in range(45):
		await process_frame
	Input.action_press("steer_right")
	Input.action_press("drift")
	for _i in range(30):
		await process_frame
	Input.action_release("drift")
	for _i in range(8):
		await process_frame
	Input.action_press("boost")
	for _i in range(20):
		await process_frame
	Input.action_release("boost")
	Input.action_release("steer_right")
	Input.action_release("move_forward")
	assert(abs(game.get("heading") as float) > 0.05)
	assert((game.get("flow_score") as int) > 0)
	var ramp_list: Array = game.get("ramps")
	assert(not ramp_list.is_empty())
	var first_ramp: Dictionary = ramp_list[0]
	assert((first_ramp["node"] as Node3D).get_child_count() > 2)
	var ramp_forward: Vector3 = first_ramp["forward"]
	var ramp_position: Vector3 = first_ramp["position"]
	player_node.position = ramp_position - ramp_forward * 2.0
	game.set("heading", atan2(ramp_forward.x, -ramp_forward.z))
	game.set("velocity", ramp_forward * 12.0)
	game.set("height", 0.0)
	game.set("jump_cooldown", 0.0)
	game.set("skip_cooldown", 100.0)
	game.call("_process", 0.016)
	assert((game.get("height") as float) > 0.0)
	assert((game.get("boat_shadow") as MeshInstance3D).visible)
	assert((game.get("event_text") as String) == "JUMP")
	player_node.position = Vector3(0.0, 0.0, 22.0)
	game.set("heading", 0.0)
	game.set("velocity", Vector3(0.0, 0.0, -14.0))
	game.set("boost_charge", 0.0)
	game.set("height", 0.1)
	game.set("vertical_velocity", -10.0)
	game.set("air_time", 0.8)
	game.set("splash_cooldown", 0.0)
	game.call("_update_player", 0.016)
	assert((game.get("boost_charge") as float) > 0.0)
	assert((game.get("event_text") as String) == "AIR TIME")

	game.set("world_time", 0.0)
	var skip_z: float = 0.0
	var skip_x: float = 0.0
	var skip_surface: float = 0.0
	var found_skip := false
	for x in range(-40, 41):
		for z in range(-100, 101):
			var x_float: float = float(x)
			var z_float: float = float(z)
			var surface: float = game.call("water_height", x_float, z_float)
			var nose: float = game.call("water_height", x_float, z_float - 2.0)
			if nose - surface > 0.04:
				skip_x = x_float
				skip_z = z_float
				skip_surface = surface
				found_skip = true
				break
		if found_skip:
			break
	assert(found_skip)
	player_node.position = Vector3(skip_x, skip_surface, skip_z)
	game.set("heading", 0.0)
	game.set("velocity", Vector3(0.0, 0.0, -14.0))
	game.set("height", 0.0)
	game.set("jump_cooldown", 100.0)
	game.set("skip_cooldown", 0.0)
	game.call("_process", 0.016)
	assert((game.get("skip_cooldown") as float) > 0.0)
	assert(-(game.get("velocity") as Vector3).z > 14.5)
	assert((game.get("audio_burst") as float) > 0.0)
	assert(game.get_node_or_null("WaterSplashRing") != null)
	game.set("boost_charge", 0.0)
	game.set("skip_chain", 0)
	game.set("skip_chain_timer", 0.0)
	for pad in (game.get("boost_pads") as Array):
		pad["used"] = true
	for _i in range(2):
		player_node.position = Vector3(skip_x, skip_surface, skip_z)
		game.set("height", 0.0)
		game.set("skip_cooldown", 0.0)
		game.call("_update_player", 0.016)
	assert((game.get("skip_chain") as int) >= 2)
	assert((game.get("boost_charge") as float) > 0.0)
	assert((game.get("event_text") as String).begins_with("WAVE SKIP x"))
	assert(-(game.get("velocity") as Vector3).z > 15.5)
	game.call("_generate_course")
	game.call("_reset_player")
	game.set("boost_charge", 0.0)
	var lap_gates: Array = game.get("gates")
	var lap_pad: Dictionary = (game.get("boost_pads") as Array)[0]
	lap_pad["used"] = true
	lap_pad["node"].visible = false
	for _lap in range(3):
		for gate in lap_gates:
			player_node.position = gate["position"]
			game.set("heading", atan2(gate["forward"].x, -gate["forward"].z))
			game.call("_update_course")
	assert((game.get("lap") as int) == 4)
	assert((game.get("course_index") as int) == 0)
	assert((game.get("event_text") as String) == "LAP COMPLETE")
	assert((game.get("boost_charge") as float) > 0.0)
	assert(not lap_pad["used"])
	assert(lap_pad["node"].visible)
	print("Wavebreak smoke check passed")
	game.queue_free()
	await process_frame
	quit()
