extends Node3D

const WATER_SIZE := 240.0
const WORLD_LIMIT := 112.0
const MAX_BOOST := 100.0

var rng := RandomNumberGenerator.new()
var world_time := 0.0
var player: Node3D
var boat_visual: Node3D
var boat_shadow: MeshInstance3D
var camera: Camera3D
var next_gate_indicator: Node3D
var engine_audio: AudioStreamPlayer
var engine_playback: AudioStreamGeneratorPlayback
var audio_phase := 0.0
var audio_burst := 0.0
var water_material: ShaderMaterial
var water_ripples: Array[Dictionary] = []
var wake_left: MeshInstance3D
var wake_right: MeshInstance3D
var wake_trail: MeshInstance3D
var boost_glow_left: MeshInstance3D
var boost_glow_right: MeshInstance3D
var drift_spark_left: MeshInstance3D
var drift_spark_right: MeshInstance3D
var authored_arch: Node3D
var authored_buoy: Node3D
var authored_reef: Node3D

var velocity := Vector3.ZERO
var heading := 0.0
var height := 0.0
var vertical_velocity := 0.0
var air_time := 0.0
var boost_charge := MAX_BOOST
var boost_heat := 0.0
var drift_charge := 0.0
var drift_boost_timer := 0.0
var skip_cooldown := 0.0
var skip_chain := 0
var skip_chain_timer := 0.0
var jump_cooldown := 0.0
var splash_cooldown := 0.0
var drift_was_down := false
var boost_was_down := false
var camera_shake := 0.0
var camera_shake_strength := 0.0
var event_timer := 0.0
var event_text := "CRUISE"
var flow_score := 0
var flow_combo := 1.0
var flow_timer := 0.0
var rock_hit_cooldown := 0.0
var course_index := 0
var current_course_layout := -1
var last_course_layout := -1
var lap := 1
var lap_time := 0.0
var best_lap := 0.0
var gates: Array[Dictionary] = []
var ramps: Array[Dictionary] = []
var boost_pads: Array[Dictionary] = []
var obstacles: Array[Dictionary] = []
var buoys: Array[Dictionary] = []
var reset_was_down := false

var speed_label: Label
var course_label: Label
var state_label: Label
var flow_label: Label
var boost_label: Label
var hint_label: Label
var boost_bar: ProgressBar

var water_color := Color("#197c9d")
var rock_colors := [Color("#254e59"), Color("#356675"), Color("#467b82"), Color("#566d70"), Color("#725b4b")]

func _ready() -> void:
	rng.randomize()
	_build_environment()
	_build_audio()
	_build_water()
	_build_player()
	authored_arch = _load_gltf_asset("res://assets/wavebreak_arch_refined.glb")
	authored_buoy = _load_gltf_asset("res://assets/wavebreak_buoy_refined.glb")
	authored_reef = _load_gltf_asset("res://assets/wavebreak_reef_refined.glb")
	_build_world_border()
	_generate_course()
	_build_hud()
	_reset_player()

func _process(delta: float) -> void:
	world_time += delta
	lap_time += delta
	event_timer = max(0.0, event_timer - delta)
	audio_burst = max(0.0, audio_burst - delta * 3.5)
	drift_boost_timer = max(0.0, drift_boost_timer - delta)
	flow_timer = max(0.0, flow_timer - delta)
	if flow_timer <= 0.0:
		flow_combo = move_toward(flow_combo, 1.0, delta * 0.75)
	rock_hit_cooldown = max(0.0, rock_hit_cooldown - delta)
	skip_chain_timer = max(0.0, skip_chain_timer - delta)
	if skip_chain_timer <= 0.0:
		skip_chain = 0
	if water_material:
		water_material.set_shader_parameter("wave_time", world_time)
	_update_water_ripples()
	_update_player(delta)
	_update_audio(delta)
	_update_course()
	_update_camera(delta)
	_update_hud()
	if Input.is_key_pressed(KEY_R) and not reset_was_down:
		_generate_course()
		_reset_player()
	reset_was_down = Input.is_key_pressed(KEY_R)

func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#79b9ca")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#a8d3d4")
	environment.ambient_light_energy = 0.75
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.fog_enabled = true
	environment.fog_light_color = Color("#79b9ca")
	environment.fog_density = 0.0035
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_color = Color("#ffe7b0")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25.0, 150.0, 0.0)
	fill.light_color = Color("#6eb7d2")
	fill.light_energy = 0.35
	add_child(fill)

func _build_audio() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 22050.0
	generator.buffer_length = 0.25
	engine_audio = AudioStreamPlayer.new()
	engine_audio.name = "EngineAudio"
	engine_audio.stream = generator
	engine_audio.volume_db = -8.0
	add_child(engine_audio)
	engine_audio.play()
	engine_playback = engine_audio.get_stream_playback() as AudioStreamGeneratorPlayback

func _update_audio(_delta: float) -> void:
	if not engine_playback:
		return
	var planar_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	var throttle: float = absf(Input.get_axis("move_back", "move_forward"))
	var pad_id := _get_controller_id()
	if pad_id >= 0:
		var pad_throttle: float = absf(Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_Y))
		throttle = maxf(throttle, pad_throttle)
	var boosting := Input.is_action_pressed("boost") and boost_charge > 0.0
	if pad_id >= 0 and Input.is_joy_button_pressed(pad_id, JOY_BUTTON_X):
		boosting = boost_charge > 0.0
	var drift_boosting := drift_boost_timer > 0.0
	var frequency: float = 48.0 + planar_speed * 4.0 + throttle * 42.0 + (68.0 if boosting else 0.0)
	if drift_boosting:
		frequency += 34.0
	var amplitude: float = 0.018 + throttle * 0.018 + minf(planar_speed / 31.0, 1.0) * 0.038 + (0.018 if boosting else 0.0)
	while engine_playback.get_frames_available() > 0:
		var sample := sin(audio_phase * TAU) * 0.58 + sin(audio_phase * TAU * 2.0) * 0.25 + sin(audio_phase * TAU * 0.5) * 0.17
		if boosting:
			sample += sin(audio_phase * TAU * 3.7) * 0.16
		if audio_burst > 0.0:
			sample += sin(audio_phase * TAU * 5.5) * audio_burst * 0.22
		engine_playback.push_frame(Vector2(sample, sample) * amplitude)
		audio_phase = fmod(audio_phase + frequency / 22050.0, 1.0)

func _build_water() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, unshaded;

uniform float wave_time = 0.0;
uniform vec4 deep_color : source_color = vec4(0.02, 0.22, 0.32, 1.0);
uniform vec4 light_color : source_color = vec4(0.08, 0.55, 0.63, 1.0);
uniform vec4 foam_color : source_color = vec4(0.62, 0.9, 0.84, 1.0);
varying float wave_height;

float wave(vec2 p) {
	return sin(p.x * 0.075 + wave_time * 0.95) * 0.28
		+ cos(p.y * 0.11 - wave_time * 1.15) * 0.18
		+ sin((p.x + p.y) * 0.035 - wave_time * 0.55) * 0.35;
}

void vertex() {
	vec2 p = VERTEX.xz;
	float h = wave(p);
	float dx = wave(p + vec2(0.35, 0.0)) - h;
	float dz = wave(p + vec2(0.0, 0.35)) - h;
	VERTEX.y += h;
	NORMAL = normalize(vec3(-dx / 0.35, 1.0, -dz / 0.35));
	wave_height = h;
}

void fragment() {
	float bands = sin((UV.x * 13.0 + UV.y * 9.0) + wave_time * 0.7) * 0.5 + 0.5;
	float current = sin(UV.x * 38.0 + UV.y * 11.0 + wave_time * 0.42) * 0.5 + 0.5;
	float glints = sin(UV.x * 92.0 - UV.y * 31.0 - wave_time * 0.8) * 0.5 + 0.5;
	float sweep = sin(UV.x * 27.0 - UV.y * 17.0 + wave_time * 1.35) * 0.5 + 0.5;
	float foam = smoothstep(0.3, 0.72, wave_height);
	vec3 base_color = mix(deep_color.rgb, light_color.rgb, bands * 0.32 + current * 0.28 + foam * 0.22);
	float crest = smoothstep(0.48, 0.78, wave_height);
	float surface_sheen = smoothstep(0.72, 0.98, glints) * (0.12 + current * 0.16);
	float moving_sheen = smoothstep(0.78, 0.98, sweep) * (0.08 + current * 0.1);
	ALBEDO = mix(base_color, foam_color.rgb, crest * 0.26 + surface_sheen + moving_sheen);
}
"""
	water_material = ShaderMaterial.new()
	water_material.shader = shader
	water_material.set_shader_parameter("deep_color", Color("#096477"))
	water_material.set_shader_parameter("light_color", Color("#24b9b9"))
	water_material.set_shader_parameter("foam_color", Color("#9be6d7"))
	var plane := PlaneMesh.new()
	plane.size = Vector2(WATER_SIZE, WATER_SIZE)
	plane.subdivide_width = 96
	plane.subdivide_depth = 96
	var water := MeshInstance3D.new()
	water.name = "AnimatedWater"
	water.mesh = plane
	water.material_override = water_material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

	for i in range(26):
		var ripple := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 0.6
		ring.outer_radius = 0.68
		ring.rings = 8
		ring.ring_segments = 12
		ripple.mesh = ring
		ripple.position = Vector3(rng.randf_range(-90.0, 90.0), 0.08, rng.randf_range(-90.0, 90.0))
		ripple.scale = Vector3(rng.randf_range(1.5, 3.0), 0.08, rng.randf_range(1.5, 3.0))
		ripple.material_override = _material(Color(0.35, 0.9, 0.9, 0.25), 0.1, true)
		add_child(ripple)
		water_ripples.append({
			"node": ripple,
			"position": ripple.position,
			"base_scale": ripple.scale,
			"phase": rng.randf_range(0.0, TAU),
		})

func _update_water_ripples() -> void:
	for ripple_data in water_ripples:
		var ripple: MeshInstance3D = ripple_data["node"]
		if not is_instance_valid(ripple):
			continue
		var ripple_position: Vector3 = ripple_data["position"]
		var base_scale: Vector3 = ripple_data["base_scale"]
		var pulse := 1.0 + sin(world_time * 0.85 + float(ripple_data["phase"])) * 0.12
		ripple.position.y = water_height(ripple_position.x, ripple_position.z) + 0.05
		ripple.scale = Vector3(base_scale.x * pulse, base_scale.y, base_scale.z * pulse)

func _get_controller_id() -> int:
	var controllers := Input.get_connected_joypads()
	return int(controllers[0]) if not controllers.is_empty() else -1

func _build_player() -> void:
	player = Node3D.new()
	player.name = "PlayerBoat"
	add_child(player)
	boat_visual = Node3D.new()
	boat_visual.name = "BoatVisual"
	player.add_child(boat_visual)

	var authored_boat: Node3D = _load_authored_boat()
	if authored_boat:
		authored_boat.name = "BlenderBoatAsset"
		authored_boat.rotation.x = PI * 0.5
		boat_visual.add_child(authored_boat)
	else:
		var hull := MeshInstance3D.new()
		hull.name = "LowPolyHull"
		hull.mesh = _make_hull_mesh()
		hull.material_override = _material(Color("#f47c38"), 0.38)
		boat_visual.add_child(hull)

		_add_box(boat_visual, Vector3(1.65, 0.12, 2.15), Vector3(0, 0.62, 0.1), _material(Color("#f6c74a"), 0.32))
		_add_box(boat_visual, Vector3(0.95, 0.6, 0.16), Vector3(0, 1.0, -0.5), _material(Color("#103e56"), 0.16), deg_to_rad(-12.0), 0.0, 0.0)
		_add_box(boat_visual, Vector3(1.05, 0.22, 0.82), Vector3(0, 0.72, 0.85), _material(Color("#123447"), 0.28))
		_add_box(boat_visual, Vector3(0.16, 0.22, 1.3), Vector3(-1.02, 0.17, 0.65), _material(Color("#f6c74a"), 0.35))
		_add_box(boat_visual, Vector3(0.16, 0.22, 1.3), Vector3(1.02, 0.17, 0.65), _material(Color("#f6c74a"), 0.35))
		_add_box(boat_visual, Vector3(0.55, 0.18, 0.55), Vector3(0, 0.18, 2.15), _material(Color("#26343b"), 0.42))
		_add_sphere(boat_visual, Vector3(0.17, 0.17, 0.17), Vector3(-0.52, 0.72, -1.6), _material(Color("#7ffff1"), 0.08, true, Color("#39fff0")))
		_add_sphere(boat_visual, Vector3(0.17, 0.17, 0.17), Vector3(0.52, 0.72, -1.6), _material(Color("#7ffff1"), 0.08, true, Color("#39fff0")))

	wake_left = _make_wake(Vector3(-0.45, 0.16, 2.15))
	wake_right = _make_wake(Vector3(0.45, 0.16, 2.15))
	boat_visual.add_child(wake_left)
	boat_visual.add_child(wake_right)
	wake_trail = _make_wake_trail()
	wake_trail.position = Vector3(0.0, 0.13, 2.05)
	boat_visual.add_child(wake_trail)
	boost_glow_left = _make_boost_glow(Vector3(-0.42, 0.34, 2.28))
	boost_glow_right = _make_boost_glow(Vector3(0.42, 0.34, 2.28))
	boat_visual.add_child(boost_glow_left)
	boat_visual.add_child(boost_glow_right)
	drift_spark_left = _make_drift_spark(Vector3(-1.0, 0.2, 0.85))
	drift_spark_right = _make_drift_spark(Vector3(1.0, 0.2, 0.85))
	boat_visual.add_child(drift_spark_left)
	boat_visual.add_child(drift_spark_right)
	boat_visual.scale = Vector3.ONE * 1.16
	boat_shadow = _make_boat_shadow()
	add_child(boat_shadow)

	camera = Camera3D.new()
	camera.name = "ChaseCamera"
	camera.current = true
	camera.fov = 72.0
	add_child(camera)
	_build_gate_indicator()

func _build_gate_indicator() -> void:
	next_gate_indicator = Node3D.new()
	next_gate_indicator.name = "NextGateIndicator"
	add_child(next_gate_indicator)
	var indicator_material := _material(Color("#ffe28a"), 0.08, true, Color("#ff9d38"))
	var shaft := MeshInstance3D.new()
	var shaft_mesh := BoxMesh.new()
	shaft_mesh.size = Vector3(0.14, 0.12, 1.1)
	shaft.mesh = shaft_mesh
	shaft.position = Vector3(0.0, 0.0, -0.34)
	shaft.material_override = indicator_material
	next_gate_indicator.add_child(shaft)
	for side in [-1.0, 1.0]:
		var bar := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = Vector3(0.14, 0.12, 0.82)
		bar.mesh = bar_mesh
		bar.position = Vector3(side * 0.28, 0.0, -0.78)
		bar.rotation.y = -side * 0.55
		bar.material_override = indicator_material
		next_gate_indicator.add_child(bar)
	next_gate_indicator.visible = false

func _load_authored_boat() -> Node3D:
	return _load_gltf_asset("res://assets/wavebreak_boat_refined.glb")

func _load_gltf_asset(path: String) -> Node3D:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(path, state)
	if error != OK:
		return null
	return document.generate_scene(state) as Node3D

func _build_world_border() -> void:
	for i in range(54):
		var angle := TAU * float(i) / 54.0 + rng.randf_range(-0.06, 0.06)
		var radius := rng.randf_range(96.0, 112.0)
		var pos := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		_create_rock_cluster(pos, rng.randf_range(2.5, 6.5), 2)
	for pos in [Vector3(-72, 0, -62), Vector3(72, 0, -48), Vector3(-76, 0, 48), Vector3(74, 0, 58)]:
		_create_rock_cluster(pos, rng.randf_range(4.0, 7.0), 4)
	var landmark_positions := [Vector3(-58, 0, -18), Vector3(58, 0, 8), Vector3(-56, 0, 42), Vector3(58, 0, 50)]
	for i in range(landmark_positions.size()):
		_create_landmark(landmark_positions[i], rng.randf_range(5.5, 8.0), i)
	var buoy_positions := [Vector3(-16, 0, -24), Vector3(16, 0, -24), Vector3(-30, 0, 22), Vector3(30, 0, 22)]
	for i in range(buoy_positions.size()):
		_create_buoy_marker(buoy_positions[i], i)

func _create_landmark(pos: Vector3, size: float, index: int) -> void:
	var root := Node3D.new()
	root.name = "ReefLandmark_%02d" % index
	root.position = Vector3(pos.x, water_height(pos.x, pos.z) - 0.5, pos.z)
	add_child(root)
	obstacles.append({"center": Vector2(pos.x, pos.z), "radius": maxf(size * 0.9, 4.5), "node": root})
	var rock_material := _material(rock_colors[(index + 1) % rock_colors.size()], 0.92)
	if authored_reef:
		var reef_instance: Node3D = authored_reef.duplicate()
		reef_instance.scale = Vector3.ONE * (size / 6.5)
		root.add_child(reef_instance)
	else:
		_add_rock(root, Vector3(0.0, size * 0.62, 0.0), Vector3(size * 0.48, size * 0.95, size * 0.48), rock_material)
		for i in range(4):
			var angle := TAU * float(i) / 4.0 + rng.randf_range(-0.3, 0.3)
			var offset := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(size * 0.35, size * 0.75)
			var rock_size := Vector3(size * 0.3, size * rng.randf_range(0.42, 0.7), size * 0.3)
			_add_rock(root, offset + Vector3(0.0, rock_size.y, 0.0), rock_size, rock_material)
	var beacon_material := _material(Color("#ffcc63"), 0.2, true, Color("#ff9e36"))
	_add_sphere(root, Vector3(0.3, 0.3, 0.3), Vector3(0.0, size * 1.72, 0.0), beacon_material)

func _create_buoy_marker(pos: Vector3, index: int) -> void:
	var root := Node3D.new()
	root.name = "MarkerBuoy_%02d" % index
	root.position = Vector3(pos.x, water_height(pos.x, pos.z) - 0.22, pos.z)
	add_child(root)
	if authored_buoy:
		var buoy_instance: Node3D = authored_buoy.duplicate()
		buoy_instance.rotation.x = PI * 0.5
		buoy_instance.scale = Vector3.ONE * 1.22
		root.add_child(buoy_instance)
	else:
		_add_sphere(root, Vector3(0.7, 0.42, 0.7), Vector3(0.0, 0.45, 0.0), _material(Color("#f05a2a"), 0.45))
		_add_box(root, Vector3(0.12, 1.9, 0.12), Vector3(0.0, 1.35, 0.0), _material(Color("#2bd2c8"), 0.35))
		_add_box(root, Vector3(0.6, 0.28, 0.08), Vector3(0.28, 2.0, 0.0), _material(Color("#ffd45a"), 0.35))
	buoys.append({"node": root, "position": pos, "phase": float(index) * 1.7})

func _generate_course() -> void:
	for gate in gates:
		if is_instance_valid(gate.node):
			gate.node.queue_free()
	for ramp in ramps:
		if is_instance_valid(ramp.node):
			ramp.node.queue_free()
	for pad in boost_pads:
		if is_instance_valid(pad.node):
			pad.node.queue_free()
	gates.clear()
	ramps.clear()
	boost_pads.clear()
	course_index = 0
	lap = 1
	lap_time = 0.0

	var points: Array[Vector3] = [Vector3(0.0, 0.0, -30.0)]
	var course_layout := rng.randi_range(0, 3)
	if course_layout == last_course_layout:
		course_layout = (course_layout + 1 + rng.randi_range(0, 2)) % 4
	current_course_layout = course_layout
	last_course_layout = course_layout
	for i in range(1, 9):
		var progress := float(i) / 8.0
		var angle := -PI * 0.5 + progress * TAU + rng.randf_range(-0.12, 0.12)
		var point := Vector3.ZERO
		match course_layout:
			0:
				var radius := rng.randf_range(37.0, 52.0)
				point = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			1:
				point = Vector3(sin(progress * TAU) * 56.0, 0.0, cos(progress * TAU) * 38.0 + 16.0)
			2:
				point = Vector3(sin(progress * TAU * 2.0) * 44.0, 0.0, cos(progress * TAU) * 38.0 + sin(progress * TAU) * 14.0 - 4.0)
			_:
				point = Vector3(sin(progress * PI * 2.0) * 42.0, 0.0, -56.0 + progress * 112.0)
		point += Vector3(rng.randf_range(-4.0, 4.0), 0.0, rng.randf_range(-3.0, 3.0))
		var separation_attempts := 0
		while separation_attempts < 80 and not _course_point_clear(point, points):
			point += Vector3(rng.randf_range(-7.0, 7.0), 0.0, rng.randf_range(-7.0, 7.0))
			point.x = clampf(point.x, -88.0, 88.0)
			point.z = clampf(point.z, -88.0, 88.0)
			separation_attempts += 1
		if not _course_point_clear(point, points):
			var fallback_attempts := 0
			while fallback_attempts < 256 and not _course_point_clear(point, points):
				point = Vector3(rng.randf_range(-84.0, 84.0), 0.0, rng.randf_range(-84.0, 84.0))
				fallback_attempts += 1
		point.x = clampf(point.x, -88.0, 88.0)
		point.z = clampf(point.z, -88.0, 88.0)
		points.append(point)

	var closing_valid := _course_segment_clear(points[-1], points[0])
	var closing_attempts := 0
	while not closing_valid and closing_attempts < 512:
		var candidate: Vector3 = Vector3(rng.randf_range(-84.0, 84.0), 0.0, rng.randf_range(-84.0, 84.0))
		candidate.x = clampf(candidate.x, -88.0, 88.0)
		candidate.z = clampf(candidate.z, -88.0, 88.0)
		var candidate_valid := true
		for existing_index in range(points.size() - 1):
			if candidate.distance_to(points[existing_index]) < 16.0:
				candidate_valid = false
				break
		if candidate_valid and _course_segment_clear(points[-2], candidate) and _course_segment_clear(candidate, points[0]):
			points[-1] = candidate
			closing_valid = true
		closing_attempts += 1

	for i in range(points.size()):
		var next_point: Vector3 = points[(i + 1) % points.size()]
		var direction := (next_point - points[i]).normalized()
		if i == 0:
			direction = Vector3(0, 0, -1)
		var gate := _create_arch(points[i], atan2(direction.x, -direction.z), i)
		gates.append({"node": gate, "position": points[i], "forward": direction, "passed": false})
		if i > 0 and i % 2 == 0:
			var ramp_pos := points[i] - direction * 11.0
			var ramp := _create_ramp(ramp_pos, atan2(direction.x, -direction.z))
			ramps.append({"node": ramp, "position": ramp_pos, "forward": direction})
			if course_layout == 2 and i == 4:
				var lateral := Vector3(-direction.z, 0.0, direction.x)
				var split_pos := ramp_pos + lateral * 6.8
				var split_ramp := _create_ramp(split_pos, atan2(direction.x, -direction.z))
				ramps.append({"node": split_ramp, "position": split_pos, "forward": direction})
		if course_layout == 1 and i == 7:
			var extra_ramp_pos := points[i] - direction * 11.0
			var extra_ramp := _create_ramp(extra_ramp_pos, atan2(direction.x, -direction.z))
			ramps.append({"node": extra_ramp, "position": extra_ramp_pos, "forward": direction})
		if i > 0 and i % 2 == 1:
			var pad_pos := points[i] - direction * 6.0
			var pad := _create_boost_pad(pad_pos, atan2(direction.x, -direction.z))
			boost_pads.append({"node": pad, "position": pad_pos, "used": false})

func _course_segment_clear(start: Vector3, end: Vector3) -> bool:
	var start_2d := Vector2(start.x, start.z)
	var segment := Vector2(end.x, end.z) - start_2d
	var segment_length_squared := segment.length_squared()
	for obstacle in obstacles:
		var obstacle_center: Vector2 = obstacle.center
		var along := 0.0
		if segment_length_squared > 0.001:
			along = clampf((obstacle_center - start_2d).dot(segment) / segment_length_squared, 0.0, 1.0)
		var closest := start_2d + segment * along
		if closest.distance_to(obstacle_center) < float(obstacle.radius) + 4.0:
			return false
	return true

func _course_point_clear(point: Vector3, existing_points: Array[Vector3]) -> bool:
	for existing_point in existing_points:
		if point.distance_to(existing_point) < 16.0:
			return false
	for obstacle in obstacles:
		var obstacle_center: Vector2 = obstacle.center
		if Vector2(point.x, point.z).distance_to(obstacle_center) < float(obstacle.radius) + 4.0:
			return false
	if not existing_points.is_empty() and not _course_segment_clear(existing_points[-1], point):
		return false
	return true

func _create_arch(pos: Vector3, angle: float, index: int) -> Node3D:
	var root := Node3D.new()
	root.name = "RockArch_%02d" % index
	root.position = Vector3(pos.x, water_height(pos.x, pos.z) - 0.3, pos.z)
	root.rotation.y = angle
	add_child(root)
	if authored_arch:
		var arch_instance: Node3D = authored_arch.duplicate()
		arch_instance.rotation.x = PI * 0.5
		root.add_child(arch_instance)
	else:
		var rock_material := _material(rock_colors[index % rock_colors.size()], 0.88)
		_add_rock(root, Vector3(-5.4, 3.2, 0.0), Vector3(2.2, 3.9, 2.5), rock_material)
		_add_rock(root, Vector3(5.4, 3.2, 0.0), Vector3(2.2, 3.9, 2.5), rock_material)
		_add_rock(root, Vector3(-3.2, 7.0, 0.0), Vector3(2.2, 1.55, 2.3), rock_material)
		_add_rock(root, Vector3(0.0, 7.7, 0.0), Vector3(2.7, 1.8, 2.4), rock_material)
		_add_rock(root, Vector3(3.2, 7.0, 0.0), Vector3(2.2, 1.55, 2.3), rock_material)
	if not authored_arch:
		var beacon_material := _material(Color("#ffcc63"), 0.2, true, Color("#ff9e36"))
		_add_sphere(root, Vector3(0.28, 0.28, 0.28), Vector3(-3.2, 5.35, 0.0), beacon_material)
		_add_sphere(root, Vector3(0.28, 0.28, 0.28), Vector3(3.2, 5.35, 0.0), beacon_material)
	var gate_light := OmniLight3D.new()
	gate_light.name = "GateLight"
	gate_light.position = Vector3(0.0, 4.6, 0.0)
	gate_light.light_color = Color("#ffb34d")
	gate_light.omni_range = 9.0
	gate_light.shadow_enabled = false
	gate_light.visible = false
	root.add_child(gate_light)
	if index == 0:
		var start_line := Node3D.new()
		start_line.name = "StartFinishLine"
		root.add_child(start_line)
		var start_dark := _material(Color("#17333e"), 0.5)
		var start_light := _material(Color("#f6d36a"), 0.28, true, Color("#d78332"))
		for row in range(2):
			for column in range(6):
				var tile_material: Material = start_light if (row + column) % 2 == 0 else start_dark
				_add_box(start_line, Vector3(0.9, 0.06, 0.52), Vector3((float(column) - 2.5) * 0.92, 0.03, (float(row) - 0.5) * 0.55), tile_material)
	return root

func _create_ramp(pos: Vector3, angle: float) -> Node3D:
	var root := Node3D.new()
	root.name = "JumpRamp"
	root.position = Vector3(pos.x, water_height(pos.x, pos.z), pos.z)
	root.rotation.y = angle
	add_child(root)
	var ramp_material := _material(Color("#e05b37"), 0.55)
	var ramp_mesh := MeshInstance3D.new()
	ramp_mesh.mesh = _make_ramp_mesh()
	ramp_mesh.material_override = ramp_material
	root.add_child(ramp_mesh)
	var stripe_material := _material(Color("#ffd45a"), 0.3, true, Color("#ff8e2c"))
	for z in [2.6, 1.1, -0.4, -1.9, -3.4]:
		var stripe_y: float = (3.75 - float(z)) / 7.5 * 1.8 + 0.07
		_add_box(root, Vector3(5.8, 0.1, 0.12), Vector3(0.0, stripe_y, z), stripe_material)
	return root

func _create_boost_pad(pos: Vector3, angle: float) -> Node3D:
	var root := Node3D.new()
	root.name = "BoostPad"
	root.position = Vector3(pos.x, water_height(pos.x, pos.z), pos.z)
	root.rotation.y = angle
	add_child(root)
	var pad_material := _material(Color("#0bb8c2"), 0.2, true, Color("#0b788e"))
	_add_box(root, Vector3(4.2, 0.12, 2.8), Vector3(0.0, 0.08, 0.0), pad_material)
	var stripe_material := _material(Color("#ffd45a"), 0.3, true, Color("#ff8e2c"))
	for x in [-1.25, 0.0, 1.25]:
		_add_box(root, Vector3(0.18, 0.18, 2.45), Vector3(x, 0.2, 0.0), stripe_material)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.65
	torus.outer_radius = 0.82
	torus.rings = 8
	torus.ring_segments = 16
	ring.mesh = torus
	ring.position = Vector3(0.0, 0.32, 0.0)
	ring.scale = Vector3(1.15, 0.08, 0.72)
	ring.material_override = stripe_material
	root.add_child(ring)
	return root

func _create_rock_cluster(pos: Vector3, size: float, count: int) -> void:
	var root := Node3D.new()
	root.position = Vector3(pos.x, water_height(pos.x, pos.z) - 0.5, pos.z)
	add_child(root)
	obstacles.append({"center": Vector2(pos.x, pos.z), "radius": maxf(size * 0.86, 2.5), "node": root})
	for i in range(count):
		var angle := rng.randf_range(0.0, TAU)
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.0, size * 0.7)
		var rock_size := Vector3(rng.randf_range(1.2, 2.3), rng.randf_range(1.4, 3.1), rng.randf_range(1.2, 2.3)) * size * 0.34
		_add_rock(root, offset + Vector3(0, rock_size.y, 0), rock_size, _material(rock_colors[rng.randi_range(0, rock_colors.size() - 1)], 0.9))

func _update_player(delta: float) -> void:
	skip_cooldown = max(0.0, skip_cooldown - delta)
	jump_cooldown = max(0.0, jump_cooldown - delta)
	splash_cooldown = max(0.0, splash_cooldown - delta)
	var forward := Vector3(sin(heading), 0.0, -cos(heading))
	var right := Vector3(cos(heading), 0.0, sin(heading))
	var throttle := Input.get_axis("move_back", "move_forward")
	var steer := Input.get_axis("steer_left", "steer_right")
	var drifting := Input.is_action_pressed("drift")
	var boosting := Input.is_action_pressed("boost") and boost_charge > 0.0
	var pad_id := _get_controller_id()
	if pad_id >= 0:
		var pad_steer: float = Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_X)
		var pad_throttle: float = -Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_Y)
		if absf(pad_steer) > 0.12:
			steer = pad_steer
		if absf(pad_throttle) > 0.12:
			throttle = pad_throttle
		drifting = drifting or Input.is_joy_button_pressed(pad_id, JOY_BUTTON_A)
		boosting = boosting or (Input.is_joy_button_pressed(pad_id, JOY_BUTTON_X) and boost_charge > 0.0)
	var drift_boosting := drift_boost_timer > 0.0
	var boost_started := boosting and not boost_was_down
	boost_was_down = boosting
	var drift_release := false
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var forward_speed := horizontal.dot(forward)
	var side_speed := horizontal.dot(right)
	var max_speed := 31.0 if boosting else (27.0 if drift_boosting else 22.0)
	var target_speed := throttle * max_speed
	var acceleration := 21.0 if boosting else 15.0
	if abs(throttle) > 0.05:
		forward_speed = move_toward(forward_speed, target_speed, acceleration * delta)
	else:
		forward_speed = move_toward(forward_speed, 0.0, (7.0 if drifting else 12.0) * delta)
	side_speed = move_toward(side_speed, 0.0, (0.65 if drifting else 7.0) * delta)
	if drifting and abs(forward_speed) > 7.0 and abs(steer) > 0.05:
		var drift_lateral_gain: float = (5.5 + abs(forward_speed) * 0.2) * delta
		side_speed = clampf(side_speed + steer * drift_lateral_gain, -12.0, 12.0)
	var driven_horizontal: Vector3 = forward * forward_speed + right * side_speed
	var turn_strength := 2.05 if drifting else (1.35 if boosting else 1.15)
	var turn_speed: float = clampf(abs(forward_speed) / 5.0, 0.18, 1.35)
	heading += steer * turn_strength * turn_speed * delta * (1.0 if forward_speed >= -0.1 else -1.0)
	forward = Vector3(sin(heading), 0.0, -cos(heading))
	right = Vector3(cos(heading), 0.0, sin(heading))
	horizontal = driven_horizontal
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if boosting:
		if boost_started:
			camera_shake = max(camera_shake, 0.1)
			camera_shake_strength = max(camera_shake_strength, 0.07)
			audio_burst = maxf(audio_burst, 0.35)
			event_text = "BOOST"
			event_timer = 0.25
			_award_flow(25)
		velocity += forward * 8.5 * delta
		boost_charge = max(0.0, boost_charge - 24.0 * delta)
		boost_heat = min(1.0, boost_heat + delta * 2.5)
	else:
		boost_charge = min(MAX_BOOST, boost_charge + 11.0 * delta)
		boost_heat = max(0.0, boost_heat - delta * 2.0)
	if drifting and abs(forward_speed) > 11.0:
		drift_charge = min(1.0, drift_charge + delta * 0.75)
	else:
		drift_charge = max(0.0, drift_charge - delta * 1.4)
	if not drifting and drift_was_down and drift_charge > 0.2:
		boost_charge = min(MAX_BOOST, boost_charge + drift_charge * 35.0)
		velocity += forward * drift_charge * 6.5
		drift_boost_timer = 0.65
		boost_heat = maxf(boost_heat, drift_charge * 0.8)
		event_text = "SLINGSHOT"
		event_timer = 0.45
		_award_flow(100)
		camera_shake = max(camera_shake, 0.12)
		camera_shake_strength = max(camera_shake_strength, 0.12)
		drift_release = true
	drift_was_down = drifting

	var surface_y := water_height(player.position.x, player.position.z)
	var nose_y := water_height(player.position.x + forward.x * 2.0, player.position.z + forward.z * 2.0)
	var stern_y := water_height(player.position.x - forward.x * 2.0, player.position.z - forward.z * 2.0)
	var wave_lift := nose_y - surface_y
	var state := "CRUISE"
	if height <= 0.02:
		height = 0.0
		vertical_velocity = 0.0
		if jump_cooldown <= 0.0 and forward_speed > 8.0 and _near_ramp(forward):
			height = 0.12
			vertical_velocity = 7.0 + forward_speed * 0.1
			air_time = 0.0
			jump_cooldown = 1.0
			event_text = "JUMP"
			event_timer = 0.35
			_award_flow(45)
			camera_shake = max(camera_shake, 0.16)
			camera_shake_strength = max(camera_shake_strength, 0.1)
			state = "JUMP"
		elif skip_cooldown <= 0.0 and forward_speed > 11.0 and wave_lift > 0.04:
			height = 0.05
			vertical_velocity = 2.5 + wave_lift * 5.0
			velocity += forward * (1.8 + wave_lift * 3.0)
			velocity += forward * minf(float(skip_chain - 1), 3.0) * 0.8
			skip_cooldown = 0.55
			skip_chain += 1
			skip_chain_timer = 1.25
			if skip_chain >= 2:
				boost_charge = min(MAX_BOOST, boost_charge + 5.0)
				event_text = "WAVE SKIP x%d" % skip_chain
				event_timer = 0.45
			else:
				event_text = "WAVE SKIP"
				event_timer = 0.3
			_award_flow(70 + skip_chain * 20)
			_spawn_splash()
			camera_shake = max(camera_shake, 0.06)
			camera_shake_strength = max(camera_shake_strength, 0.045)
			state = "SKIP"
	else:
		vertical_velocity -= 15.0 * delta
		height += vertical_velocity * delta
		air_time += delta
		state = "AIRBORNE"
		if height <= 0.0:
			height = 0.0
			vertical_velocity = 0.0
			var landed_air_time: float = air_time
			air_time = 0.0
			if splash_cooldown <= 0.0:
				_spawn_splash()
				_award_flow(55 + int(minf(landed_air_time * 70.0, 120.0)))
				splash_cooldown = 0.45
				if abs(forward_speed) > 13.0:
					boost_charge = min(MAX_BOOST, boost_charge + 10.0)
					event_text = "AIR TIME" if landed_air_time > 0.65 else "SPLASH BOOST"
					event_timer = 0.35
				camera_shake = max(camera_shake, 0.18)
				camera_shake_strength = max(camera_shake_strength, 0.1)
	if boosting:
		state = "BOOST"
	if drifting and abs(side_speed) > 2.0:
		state = "DRIFT %02d%%" % int(drift_charge * 100.0)
	if drift_release:
		state = "DRIFT EXIT"

	player.position += velocity * delta
	player.position.x = clamp(player.position.x, -WORLD_LIMIT, WORLD_LIMIT)
	player.position.z = clamp(player.position.z, -WORLD_LIMIT, WORLD_LIMIT)
	_resolve_obstacles()
	_check_boost_pads()
	if event_timer > 0.0:
		state = event_text
	player.position.y = water_height(player.position.x, player.position.z) + height
	boat_shadow.position = Vector3(player.position.x, water_height(player.position.x, player.position.z) + 0.04, player.position.z)
	boat_shadow.rotation.y = heading
	boat_shadow.scale = Vector3(1.0 + height * 0.04, 1.0 - minf(height * 0.12, 0.55), 1.0)
	boat_visual.rotation.y = heading
	var pitch_target: float = clampf((stern_y - nose_y) * 0.42 - vertical_velocity * 0.025, -0.28, 0.28)
	var roll_target: float = clampf(-side_speed * 0.018 - steer * (0.08 if drifting else 0.035), -0.3, 0.3)
	boat_visual.rotation.x = lerp(boat_visual.rotation.x, pitch_target, min(1.0, delta * 8.0))
	boat_visual.rotation.z = lerp(boat_visual.rotation.z, roll_target, min(1.0, delta * 8.0))
	var wake_amount: float = clampf(abs(forward_speed) / 16.0, 0.0, 2.0)
	wake_left.scale = Vector3(0.55 + wake_amount * 0.12, 0.08 + wake_amount * 0.03, 0.35 + wake_amount * 0.95)
	wake_right.scale = wake_left.scale
	var wake_visible: bool = abs(forward_speed) > 1.5 and height < 0.22
	wake_left.visible = wake_visible
	wake_right.visible = wake_visible
	wake_trail.visible = wake_visible
	wake_trail.scale = Vector3(0.7 + wake_amount * 0.16, 1.0, 0.45 + wake_amount * 0.48)
	boost_glow_left.visible = boosting or drift_boosting
	boost_glow_right.visible = boosting or drift_boosting
	var boost_bloom: float = 0.72 + boost_heat * 0.9 + drift_boost_timer * 0.45
	boost_glow_left.scale = Vector3(0.2, 0.2, 0.55) * boost_bloom
	boost_glow_right.scale = boost_glow_left.scale
	var drift_visual: bool = (drifting and abs(side_speed) > 1.5 or drift_boosting or drift_boost_timer > 0.0 or drift_release) and height < 0.3
	drift_spark_left.visible = drift_visual
	drift_spark_right.visible = drift_visual
	var spark_bloom: float = 0.7 + drift_charge * 1.4 + sin(world_time * 28.0) * 0.14
	drift_spark_left.scale = Vector3.ONE * spark_bloom
	drift_spark_right.scale = drift_spark_left.scale
	if boosting:
		camera_shake = max(camera_shake, 0.03)
		camera_shake_strength = max(camera_shake_strength, 0.018)
	state_label.text = state

func _resolve_obstacles() -> void:
	var horizontal := Vector2(player.position.x, player.position.z)
	for obstacle in obstacles:
		var offset: Vector2 = horizontal - obstacle.center
		var distance := offset.length()
		var radius: float = obstacle.radius
		if distance >= radius:
			continue
		var normal := offset / maxf(distance, 0.001)
		horizontal = obstacle.center + normal * radius
		var planar_velocity := Vector2(velocity.x, velocity.z)
		var into := planar_velocity.dot(normal)
		if into < 0.0:
			planar_velocity -= normal * into * 1.35
		planar_velocity *= 0.65
		velocity.x = planar_velocity.x
		velocity.z = planar_velocity.y
		player.position.x = horizontal.x
		player.position.z = horizontal.y
		if rock_hit_cooldown <= 0.0:
			flow_combo = 1.0
			flow_timer = 0.0
			rock_hit_cooldown = 0.35
			event_text = "ROCK HIT"
			event_timer = 0.45
			camera_shake = max(camera_shake, 0.18)
			camera_shake_strength = max(camera_shake_strength, 0.12)
		break

func _check_boost_pads() -> void:
	for pad in boost_pads:
		if pad.used:
			continue
		var pad_position: Vector3 = pad.position
		if Vector2(player.position.x - pad_position.x, player.position.z - pad_position.z).length() > 3.2:
			continue
		pad.used = true
		pad.node.visible = false
		boost_charge = min(MAX_BOOST, boost_charge + 42.0)
		boost_heat = 0.9
		audio_burst = maxf(audio_burst, 0.65)
		_award_flow(45)
		var forward := Vector3(sin(heading), 0.0, -cos(heading))
		velocity += forward * 5.0
		event_text = "BOOST PICKUP"
		event_timer = 0.65
		camera_shake = max(camera_shake, 0.08)
		camera_shake_strength = max(camera_shake_strength, 0.05)
		break

func _award_flow(points: int) -> void:
	flow_score += int(round(float(points) * flow_combo))
	flow_combo = minf(4.0, flow_combo + 0.25)
	flow_timer = 2.4

func _near_ramp(forward: Vector3) -> bool:
	for ramp in ramps:
		var offset: Vector3 = player.position - ramp.position
		if offset.length() < 5.3 and forward.dot(ramp.forward) > 0.45:
			return true
	return false

func _update_course() -> void:
	if gates.is_empty():
		return
	for gate_index in range(gates.size()):
		var gate_visual: Dictionary = gates[gate_index]
		if not is_instance_valid(gate_visual.node):
			continue
		var gate_pulse: float = 0.93 if gate_visual.passed else 1.0
		if gate_index == course_index:
			gate_pulse = 1.0 + sin(world_time * 5.0) * 0.055
		var gate_light := gate_visual.node.get_node_or_null("GateLight") as OmniLight3D
		if gate_light:
			gate_light.visible = gate_index == course_index
			gate_light.light_energy = 1.0 + sin(world_time * 5.0) * 0.2
		gate_visual.node.scale = Vector3.ONE * gate_pulse
	for buoy in buoys:
		var buoy_position: Vector3 = buoy.position
		var bob := sin(world_time * 2.2 + buoy.phase) * 0.12
		buoy.node.position.y = water_height(buoy_position.x, buoy_position.z) - 0.22 + bob
		buoy.node.rotation.y = sin(world_time * 0.8 + buoy.phase) * 0.08
	for pad in boost_pads:
		if not pad.used:
			pad.node.position.y = water_height(pad.position.x, pad.position.z) + 0.02
			var pulse := 1.0 + sin(world_time * 6.0 + pad.position.x * 0.07) * 0.08
			pad.node.scale = Vector3(pulse, 1.0, pulse)
	var next_gate: Dictionary = gates[course_index]
	var gate_position: Vector3 = next_gate.position
	var boat_forward := Vector3(sin(heading), 0.0, -cos(heading))
	var boat_right := Vector3(cos(heading), 0.0, sin(heading))
	var gate_facing: float = boat_forward.dot(next_gate.forward)
	if Vector2(player.position.x - gate_position.x, player.position.z - gate_position.z).length() < 6.2 and gate_facing > 0.25:
		next_gate.passed = true
		gates[course_index] = next_gate
		course_index += 1
		audio_burst = maxf(audio_burst, 0.45)
		var drifting_through_gate: bool = abs(Vector3(velocity.x, 0.0, velocity.z).dot(boat_right)) > 2.0
		_award_flow(270 if drifting_through_gate else 180)
		event_text = "DRIFT CHECKPOINT" if drifting_through_gate else "CHECKPOINT"
		event_timer = 0.55
		if course_index >= gates.size():
			if best_lap <= 0.0 or lap_time < best_lap:
				best_lap = lap_time
			lap += 1
			lap_time = 0.0
			course_index = 0
			boost_charge = min(MAX_BOOST, boost_charge + 30.0)
			_award_flow(500)
			event_text = "LAP COMPLETE"
			event_timer = 1.0
			for pad in boost_pads:
				pad.used = false
				pad.node.visible = true
	_update_gate_indicator()

func _update_gate_indicator() -> void:
	if not next_gate_indicator or gates.is_empty():
		return
	var gate_position: Vector3 = gates[course_index].position
	var to_gate := Vector3(gate_position.x - player.position.x, 0.0, gate_position.z - player.position.z)
	var distance := to_gate.length()
	if distance < 0.1:
		next_gate_indicator.visible = false
		return
	var direction := to_gate / distance
	var indicator_distance := clampf(distance * 0.18, 3.0, 5.8)
	next_gate_indicator.position = player.position + Vector3.UP * (2.0 + height * 0.15) + direction * indicator_distance
	next_gate_indicator.rotation.y = atan2(direction.x, -direction.z)
	var pulse := 1.0 + sin(world_time * 8.0) * 0.08
	next_gate_indicator.scale = Vector3.ONE * pulse
	next_gate_indicator.visible = true

func _update_camera(delta: float) -> void:
	var forward := Vector3(sin(heading), 0.0, -cos(heading))
	var right := Vector3(cos(heading), 0.0, sin(heading))
	var planar_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var speed := planar_velocity.length()
	var lateral_speed: float = planar_velocity.dot(right)
	var desired: Vector3 = player.position - forward * (6.4 + minf(speed * 0.065, 2.0)) + right * 1.9 + Vector3.UP * (3.5 + height * 0.28)
	camera_shake = max(0.0, camera_shake - delta)
	camera_shake_strength = lerpf(camera_shake_strength, 0.0, minf(1.0, delta * 9.0))
	if camera_shake > 0.0:
		desired += Vector3(sin(world_time * 68.0) * camera_shake_strength, cos(world_time * 53.0) * camera_shake_strength, 0.0)
	camera.position = camera.position.lerp(desired, min(1.0, delta * 5.0))
	camera.look_at(player.position + forward * (2.7 + speed * 0.06) + Vector3.UP * 0.55, Vector3.UP)
	var camera_roll_target: float = clampf(-lateral_speed * 0.012, -0.1, 0.1)
	camera.rotation.z = lerpf(camera.rotation.z, camera_roll_target, min(1.0, delta * 5.0))
	camera.fov = lerp(camera.fov, 67.0 + minf(speed * 0.42, 11.0), min(1.0, delta * 3.0))

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)
	speed_label = _label(canvas, Vector2(30, 26), 26, Color("#f7f1d0"))
	course_label = _label(canvas, Vector2(30, 59), 18, Color("#c9f1ea"))
	state_label = _label(canvas, Vector2(30, 91), 18, Color("#ffca63"))
	flow_label = _label(canvas, Vector2(30, 146), 16, Color("#ffd45a"))
	boost_label = _label(canvas, Vector2(268, 120), 14, Color("#ffd45a"))
	boost_label.text = "BOOST"
	hint_label = _label(canvas, Vector2(30, 670), 15, Color(0.85, 0.95, 0.93, 0.8))
	hint_label.text = "W/S THROTTLE   A/D STEER   SPACE DRIFT   SHIFT BOOST   R NEW COURSE   GAMEPAD LEFT STICK/A/X"
	boost_bar = ProgressBar.new()
	boost_bar.position = Vector2(30, 121)
	boost_bar.size = Vector2(230, 18)
	boost_bar.min_value = 0.0
	boost_bar.max_value = MAX_BOOST
	boost_bar.show_percentage = false
	var boost_background := StyleBoxFlat.new()
	boost_background.bg_color = Color(0.03, 0.14, 0.18, 0.82)
	boost_background.corner_radius_top_left = 4
	boost_background.corner_radius_top_right = 4
	boost_background.corner_radius_bottom_left = 4
	boost_background.corner_radius_bottom_right = 4
	var boost_fill := StyleBoxFlat.new()
	boost_fill.bg_color = Color("#ffb84d")
	boost_fill.corner_radius_top_left = 4
	boost_fill.corner_radius_top_right = 4
	boost_fill.corner_radius_bottom_left = 4
	boost_fill.corner_radius_bottom_right = 4
	boost_bar.add_theme_stylebox_override("background", boost_background)
	boost_bar.add_theme_stylebox_override("fill", boost_fill)
	canvas.add_child(boost_bar)

func _update_hud() -> void:
	var horizontal_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	speed_label.text = "%03d KM/H" % int(horizontal_speed * 5.0)
	var best_text := "--" if best_lap <= 0.0 else "%.1f" % best_lap
	var gate_distance := 0.0
	if not gates.is_empty():
		var gate_position: Vector3 = gates[course_index].position
		gate_distance = Vector2(player.position.x - gate_position.x, player.position.z - gate_position.z).length()
	course_label.text = "GATE %02d/%02d   DIST %02d   LAP %02d   TIME %.1f   BEST %s" % [course_index + 1, gates.size(), int(gate_distance), lap, lap_time, best_text]
	flow_label.text = "FLOW %05d   x%.1f" % [flow_score, flow_combo]
	var combo_ratio: float = clampf((flow_combo - 1.0) / 3.0, 0.0, 1.0)
	flow_label.modulate = Color("#ffd45a").lerp(Color("#ff6a3d"), combo_ratio)
	flow_label.scale = Vector2.ONE * (1.0 + sin(world_time * 12.0) * 0.025 * combo_ratio)
	boost_bar.value = boost_charge
	boost_bar.modulate = Color(1.0, lerpf(1.0, 0.62, boost_heat), lerpf(1.0, 0.46, boost_heat), 1.0)

func _reset_player() -> void:
	player.position = Vector3(0.0, water_height(0.0, 22.0), 22.0)
	velocity = Vector3.ZERO
	heading = 0.0
	height = 0.0
	vertical_velocity = 0.0
	air_time = 0.0
	drift_was_down = false
	boost_was_down = false
	drift_charge = 0.0
	camera_shake = 0.0
	camera_shake_strength = 0.0
	boost_charge = MAX_BOOST
	flow_score = 0
	flow_combo = 1.0
	flow_timer = 0.0
	drift_boost_timer = 0.0
	audio_burst = 0.0
	skip_chain = 0
	skip_chain_timer = 0.0
	event_timer = 0.0
	event_text = "CRUISE"
	rock_hit_cooldown = 0.0
	course_index = 0
	lap = 1
	lap_time = 0.0
	for pad in boost_pads:
		pad.used = false
		pad.node.visible = true
	if camera:
		camera.position = Vector3(3.2, 4.8, 32.0)
	_update_gate_indicator()

func water_height(x: float, z: float) -> float:
	return sin(x * 0.075 + world_time * 0.95) * 0.28 + cos(z * 0.11 - world_time * 1.15) * 0.18 + sin((x + z) * 0.035 - world_time * 0.55) * 0.35

func _make_hull_mesh() -> ArrayMesh:
	var bow := Vector3(0.0, 0.5, -2.8)
	var front_left := Vector3(-1.25, 0.44, -1.35)
	var front_right := Vector3(1.25, 0.44, -1.35)
	var back_left := Vector3(-1.12, 0.35, 1.95)
	var back_right := Vector3(1.12, 0.35, 1.95)
	var keel_bow := Vector3(0.0, 0.04, -2.35)
	var keel_front_left := Vector3(-0.75, 0.04, -1.2)
	var keel_front_right := Vector3(0.75, 0.04, -1.2)
	var keel_back_left := Vector3(-0.82, 0.04, 1.95)
	var keel_back_right := Vector3(0.82, 0.04, 1.95)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tri(st, bow, front_left, front_right)
	_tri(st, front_left, back_left, back_right)
	_tri(st, front_left, back_right, front_right)
	_tri(st, bow, keel_bow, keel_front_left)
	_tri(st, bow, keel_front_left, front_left)
	_tri(st, bow, front_right, keel_front_right)
	_tri(st, bow, keel_front_right, keel_bow)
	_tri(st, front_left, keel_front_left, keel_back_left)
	_tri(st, front_left, keel_back_left, back_left)
	_tri(st, front_right, back_right, keel_back_right)
	_tri(st, front_right, keel_back_right, keel_front_right)
	_tri(st, back_left, keel_back_left, keel_back_right)
	_tri(st, back_left, keel_back_right, back_right)
	st.generate_normals()
	return st.commit()

func _make_ramp_mesh() -> ArrayMesh:
	var w := 2.7
	var l := 3.75
	var h := 1.8
	var vertices := [
		Vector3(-w, 0.0, l), Vector3(w, 0.0, l), Vector3(-w, 0.0, -l), Vector3(w, 0.0, -l),
		Vector3(-w, 0.05, l), Vector3(w, 0.05, l), Vector3(-w, h, -l), Vector3(w, h, -l)
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in [
		[0, 2, 3], [0, 3, 1], [4, 6, 7], [4, 7, 5],
		[0, 4, 6], [0, 6, 2], [1, 3, 7], [1, 7, 5],
		[0, 1, 5], [0, 5, 4], [2, 6, 7], [2, 7, 3]
	]:
		st.add_vertex(vertices[face[0]])
		st.add_vertex(vertices[face[1]])
		st.add_vertex(vertices[face[2]])
	st.generate_normals()
	return st.commit()

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

func _add_rock(parent: Node3D, pos: Vector3, scale_value: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 7
	mesh.rings = 4
	var rock := MeshInstance3D.new()
	rock.mesh = mesh
	rock.position = pos
	rock.scale = scale_value
	rock.rotation = Vector3(rng.randf_range(-0.18, 0.18), rng.randf_range(0.0, TAU), rng.randf_range(-0.18, 0.18))
	rock.material_override = material
	parent.add_child(rock)
	return rock

func _add_box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, rot_x := 0.0, rot_y := 0.0, rot_z := 0.0) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.position = pos
	mesh.rotation = Vector3(rot_x, rot_y, rot_z)
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func _add_sphere(parent: Node3D, scale_value: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	mesh.position = pos
	mesh.scale = scale_value
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func _make_wake(pos: Vector3) -> MeshInstance3D:
	var wake := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	wake.mesh = sphere
	wake.position = pos
	wake.scale = Vector3(0.65, 0.08, 0.6)
	wake.material_override = _material(Color(0.55, 0.95, 0.95, 0.42), 0.08, true)
	return wake

func _make_wake_trail() -> MeshInstance3D:
	var trail := MeshInstance3D.new()
	var vertices := PackedVector3Array([
		Vector3(-0.45, 0.0, 0.0),
		Vector3(0.45, 0.0, 0.0),
		Vector3(1.45, 0.0, 4.0),
		Vector3(-1.45, 0.0, 4.0),
	])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	trail.mesh = mesh
	var trail_material := _material(Color(0.62, 0.98, 0.92, 0.34), 0.06, true, Color(0.08, 0.2, 0.18))
	trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	trail.material_override = trail_material
	return trail

func _make_boost_glow(pos: Vector3) -> MeshInstance3D:
	var glow := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	glow.mesh = sphere
	glow.position = pos
	glow.scale = Vector3(0.2, 0.2, 0.55)
	glow.material_override = _material(Color("#fff3a6"), 0.05, true, Color("#ff7b29"))
	glow.visible = false
	return glow

func _make_drift_spark(pos: Vector3) -> MeshInstance3D:
	var spark := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.18
	sphere.height = 0.36
	sphere.radial_segments = 8
	sphere.rings = 4
	spark.mesh = sphere
	spark.position = pos
	spark.scale = Vector3.ONE * 0.7
	spark.material_override = _material(Color("#ffe06a"), 0.05, true, Color("#ff7134"))
	spark.visible = false
	return spark

func _make_boat_shadow() -> MeshInstance3D:
	var shadow := MeshInstance3D.new()
	shadow.name = "BoatWaterShadow"
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.8, 1.55)
	shadow.mesh = plane
	shadow.rotation.x = -PI * 0.5
	shadow.material_override = _material(Color(0.02, 0.09, 0.11, 0.3), 1.0, true)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return shadow

func _spawn_splash() -> void:
	audio_burst = 1.0
	var splash := MeshInstance3D.new()
	splash.name = "WaterSplashRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.72
	torus.rings = 8
	torus.ring_segments = 14
	splash.mesh = torus
	add_child(splash)
	splash.global_position = Vector3(player.position.x, water_height(player.position.x, player.position.z) + 0.07, player.position.z)
	splash.scale = Vector3(1.8, 0.12, 1.0)
	splash.material_override = _material(Color(0.55, 0.95, 0.95, 0.55), 0.08, true)
	var tween := create_tween()
	tween.tween_property(splash, "scale", Vector3(4.5, 0.12, 2.8), 0.38)
	tween.tween_callback(splash.queue_free)
	var right := Vector3(cos(heading), 0.0, sin(heading))
	var forward := Vector3(sin(heading), 0.0, -cos(heading))
	var spray_material := _material(Color(0.74, 1.0, 0.93, 0.72), 0.04, true, Color(0.12, 0.32, 0.28))
	for side in [-1.0, 1.0]:
		var spray := MeshInstance3D.new()
		var spray_mesh := SphereMesh.new()
		spray_mesh.radius = 0.22
		spray_mesh.height = 0.44
		spray_mesh.radial_segments = 6
		spray_mesh.rings = 3
		spray.mesh = spray_mesh
		spray.scale = Vector3(0.7, 1.0, 0.7)
		spray.material_override = spray_material
		add_child(spray)
		spray.global_position = splash.global_position + right * side * 0.58 + forward * 0.25 + Vector3.UP * 0.18
		var spray_tween := create_tween()
		spray_tween.set_parallel(true)
		spray_tween.tween_property(spray, "position:y", spray.position.y + 0.65, 0.34)
		spray_tween.tween_property(spray, "scale", Vector3.ZERO, 0.34)
		spray_tween.set_parallel(false)
		spray_tween.tween_callback(spray.queue_free)

func _label(parent: Node, pos: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _material(color: Color, roughness: float, transparent := false, emission := Color.BLACK) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 2.5
	return material
