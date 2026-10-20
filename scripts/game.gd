extends Node3D

const PORT := 9080
const MAX_PLAYERS := 32
const UPDATE_INTERVAL := 0.05
const MOVE_SPEED := 7.0
const JUMP_SPEED := 8.0
const GRAVITY := 22.0
const ARENA_LIMIT := 24.0
var server_players: Dictionary = {}
var player_visuals: Dictionary = {}
var network_started := false
var simulation_timer := 0.0
var send_timer := 0.0
var local_input := Vector2.ZERO
var local_jump := false
var virtual_input: Dictionary = {
	"left": false,
	"right": false,
	"forward": false,
	"back": false,
	"jump": false,
}

var camera: Camera3D
var menu: PanelContainer
var address_input: LineEdit
var status_label: Label
var mobile_controls: Control
var api_request: HTTPRequest
var api_url := ""
var match_id := ""


func _ready() -> void:
	_create_world()
	_create_camera()
	_create_hud()
	_connect_network_signals()

	api_url = OS.get_environment("ARENA_API_URL").strip_edges()
	if api_url.is_empty():
		api_url = "http://127.0.0.1:8000"

	var user_args := OS.get_cmdline_user_args()
	if user_args.has("--server"):
		_start_server(true)
	elif user_args.has("--host"):
		_start_server(false)


func _process(delta: float) -> void:
	_update_local_input()
	_update_camera(delta)

	if not network_started:
		return

	if multiplayer.is_server():
		_update_server_players(delta)
		simulation_timer += delta
		if simulation_timer >= UPDATE_INTERVAL:
			simulation_timer = 0.0
			_broadcast_world()
	elif multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		send_timer += delta
		if send_timer >= UPDATE_INTERVAL:
			send_timer = 0.0
			submit_input.rpc_id(1, local_input, local_jump)


func _create_world() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.82, 0.92)
	world_environment.environment = environment
	add_child(world_environment)

	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sunlight.light_energy = 1.15
	add_child(sunlight)

	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(60.0, 60.0)
	ground.mesh = ground_mesh
	ground.position.y = -0.52
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.24, 0.52, 0.31)
	ground.material_override = ground_material
	add_child(ground)

	var floor_body := StaticBody3D.new()
	floor_body.position.y = -0.5
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(60.0, 1.0, 60.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	add_child(floor_body)

	for index in range(10):
		var angle := TAU * float(index) / 10.0
		var obstacle := MeshInstance3D.new()
		var pillar := CylinderMesh.new()
		pillar.top_radius = 0.7
		pillar.bottom_radius = 1.0
		pillar.height = 2.2
		obstacle.mesh = pillar
		obstacle.position = Vector3(cos(angle) * 17.0, 1.1, sin(angle) * 17.0)
		var pillar_material := StandardMaterial3D.new()
		pillar_material.albedo_color = Color(0.72, 0.55, 0.32)
		obstacle.material_override = pillar_material
		add_child(obstacle)


func _create_camera() -> void:
	camera = Camera3D.new()
	camera.current = true
	camera.position = Vector3(0.0, 15.0, 21.0)
	camera.fov = 62.0
	add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)


func _create_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	menu = PanelContainer.new()
	menu.position = Vector2(18.0, 18.0)
	menu.custom_minimum_size = Vector2(330.0, 0.0)
	layer.add_child(menu)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	menu.add_child(content)

	var title := Label.new()
	title.text = "ISLAND ARENA"
	title.add_theme_font_size_override("font_size", 22)
	content.add_child(title)

	var instructions := Label.new()
	instructions.text = "Explore the island with other players."
	content.add_child(instructions)

	address_input = LineEdit.new()
	address_input.placeholder_text = "ws://server-address:9080"
	address_input.text = "ws://127.0.0.1:9080"
	content.add_child(address_input)

	var actions := HBoxContainer.new()
	content.add_child(actions)

	var host_button := Button.new()
	host_button.text = "Host"
	host_button.pressed.connect(_on_host_pressed)
	actions.add_child(host_button)

	var join_button := Button.new()
	join_button.text = "Join"
	join_button.pressed.connect(_on_join_pressed)
	actions.add_child(join_button)

	status_label = Label.new()
	status_label.text = "Host a game or enter a server address."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(status_label)

	api_request = HTTPRequest.new()
	api_request.timeout = 5.0
	api_request.request_completed.connect(_on_api_request_completed)
	add_child(api_request)

	mobile_controls = _create_mobile_controls(layer)
	mobile_controls.visible = OS.has_feature("mobile") or get_viewport().get_visible_rect().size.x < 900.0


func _create_mobile_controls(layer: CanvasLayer) -> Control:
	var controls := Control.new()
	controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(controls)

	var directions := GridContainer.new()
	directions.columns = 3
	directions.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	directions.position = Vector2(18.0, -150.0)
	directions.size = Vector2(174.0, 126.0)
	controls.add_child(directions)

	var blank := Control.new()
	blank.custom_minimum_size = Vector2(52.0, 52.0)
	directions.add_child(blank)
	_add_touch_button(directions, "Up", "forward")
	blank = Control.new()
	blank.custom_minimum_size = Vector2(52.0, 52.0)
	directions.add_child(blank)
	_add_touch_button(directions, "Left", "left")
	_add_touch_button(directions, "Down", "back")
	_add_touch_button(directions, "Right", "right")

	var jump_button := Button.new()
	jump_button.text = "Jump"
	jump_button.custom_minimum_size = Vector2(84.0, 84.0)
	jump_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	jump_button.position = Vector2(-112.0, -122.0)
	jump_button.button_down.connect(_set_virtual_input.bind("jump", true))
	jump_button.button_up.connect(_set_virtual_input.bind("jump", false))
	controls.add_child(jump_button)
	return controls


func _add_touch_button(parent: GridContainer, text: String, action: String) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(52.0, 52.0)
	button.button_down.connect(_set_virtual_input.bind(action, true))
	button.button_up.connect(_set_virtual_input.bind(action, false))
	parent.add_child(button)


func _set_virtual_input(action: String, is_pressed: bool) -> void:
	virtual_input[action] = is_pressed


func _connect_network_signals() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_host_pressed() -> void:
	_start_server(false)


func _start_server(headless: bool) -> void:
	var peer := WebSocketMultiplayerPeer.new()
	var result := peer.create_server(PORT, "0.0.0.0")
	if result != OK:
		_set_status("Could not start the game server (error %d)." % result)
		return

	multiplayer.multiplayer_peer = peer
	network_started = true
	server_players.clear()
	player_visuals.clear()
	if not headless:
		_add_server_player(1)
	_set_status("Server listening on port %d. API match record is being created." % PORT)
	_create_match_record()


func _on_join_pressed() -> void:
	var server_url := address_input.text.strip_edges()
	if server_url.is_empty():
		_set_status("Enter a WebSocket server address.")
		return
	if not server_url.begins_with("ws://") and not server_url.begins_with("wss://"):
		server_url = "ws://" + server_url

	var peer := WebSocketMultiplayerPeer.new()
	var result := peer.create_client(server_url)
	if result != OK:
		_set_status("Could not connect to the server (error %d)." % result)
		return

	multiplayer.multiplayer_peer = peer
	network_started = true
	_set_status("Connecting to %s..." % server_url)


func _add_server_player(peer_id: int) -> void:
	server_players[peer_id] = {
		"position": _spawn_position(peer_id),
		"velocity": Vector3.ZERO,
		"input": Vector2.ZERO,
		"jump": false,
	}


func _spawn_position(peer_id: int) -> Vector3:
	return Vector3(float((peer_id % 5) - 2) * 2.0, 0.0, float(int(peer_id / 5)) * 2.0)


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if server_players.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id, true)
		return
	_add_server_player(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		server_players.erase(peer_id)
		if player_visuals.has(peer_id):
			player_visuals[peer_id].queue_free()
			player_visuals.erase(peer_id)


func _on_connected_to_server() -> void:
	_set_status("Connected. Use WASD / arrow keys and Space to jump.")


func _on_connection_failed() -> void:
	_set_status("Connection failed. Check the address, server, and firewall.")


func _on_server_disconnected() -> void:
	menu.visible = true
	_set_status("The server disconnected.")
	for visual in player_visuals.values():
		visual.queue_free()
	player_visuals.clear()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_input(direction: Vector2, wants_to_jump: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not server_players.has(sender_id):
		return
	var state: Dictionary = server_players[sender_id]
	state["input"] = direction.limit_length(1.0)
	state["jump"] = wants_to_jump


func _update_local_input() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit:
		local_input = Vector2.ZERO
		local_jump = false
		return

	var horizontal := int(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT) or virtual_input["right"]) \
		- int(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT) or virtual_input["left"])
	var vertical := int(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or virtual_input["back"]) \
		- int(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) or virtual_input["forward"])
	local_input = Vector2(horizontal, vertical).limit_length(1.0)
	local_jump = Input.is_key_pressed(KEY_SPACE) or virtual_input["jump"]


func _update_server_players(delta: float) -> void:
	for peer_id in server_players:
		var state: Dictionary = server_players[peer_id]
		if peer_id == 1:
			state["input"] = local_input
			state["jump"] = local_jump

		var position: Vector3 = state["position"]
		var velocity: Vector3 = state["velocity"]
		var direction: Vector2 = state["input"]
		velocity.x = direction.x * MOVE_SPEED
		velocity.z = direction.y * MOVE_SPEED
		if position.y <= 0.001 and state["jump"]:
			velocity.y = JUMP_SPEED
		velocity.y -= GRAVITY * delta
		position += velocity * delta

		if position.y < 0.0:
			position.y = 0.0
			velocity.y = 0.0
		position.x = clampf(position.x, -ARENA_LIMIT, ARENA_LIMIT)
		position.z = clampf(position.z, -ARENA_LIMIT, ARENA_LIMIT)

		state["position"] = position
		state["velocity"] = velocity


func _broadcast_world() -> void:
	var snapshot: Dictionary = {}
	for peer_id in server_players:
		snapshot[peer_id] = server_players[peer_id]["position"]
	broadcast_world.rpc(snapshot)


@rpc("authority", "call_local", "unreliable_ordered")
func broadcast_world(snapshot: Dictionary) -> void:
	for peer_id in snapshot:
		var visual: ArenaPlayerVisual
		if not player_visuals.has(peer_id):
			visual = ArenaPlayerVisual.new()
			visual.name = "Player_%d" % peer_id
			visual.peer_id = peer_id
			add_child(visual)
			player_visuals[peer_id] = visual
		else:
			visual = player_visuals[peer_id]
		visual.set_target(snapshot[peer_id], UPDATE_INTERVAL)

	for peer_id in player_visuals.keys():
		if not snapshot.has(peer_id):
			player_visuals[peer_id].queue_free()
			player_visuals.erase(peer_id)


func _update_camera(delta: float) -> void:
	if camera == null:
		return
	var target := Vector3.ZERO
	var local_peer_id := multiplayer.get_unique_id()
	if player_visuals.has(local_peer_id):
		target = player_visuals[local_peer_id].position
	var desired_position := target + Vector3(0.0, 14.0, 19.0)
	camera.global_position = camera.global_position.lerp(desired_position, min(1.0, delta * 4.0))
	camera.look_at(target + Vector3(0.0, 1.0, 0.0), Vector3.UP)


func _create_match_record() -> void:
	var payload := JSON.stringify({
		"map_name": "island",
		"max_players": MAX_PLAYERS,
	})
	var headers := PackedStringArray(["Content-Type: application/json"])
	var result := api_request.request(
		api_url + "/v1/matches",
		headers,
		HTTPClient.METHOD_POST,
		payload
	)
	if result != OK:
		_set_status("Game is running, but the match API request could not start.")


func _on_api_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_set_status("Game is running; match storage is unavailable (HTTP %d)." % response_code)
		return

	var response = JSON.parse_string(body.get_string_from_utf8())
	if response is Dictionary and response.has("id"):
		match_id = str(response["id"])
		_set_status("Server ready. Match %s saved." % match_id)
	else:
		_set_status("Game is running, but the match API returned an invalid response.")


func _set_status(message: String) -> void:
	if status_label != null:
		status_label.text = message
