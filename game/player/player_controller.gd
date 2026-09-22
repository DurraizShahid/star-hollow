# player_controller.gd
class_name PlayerController
extends CharacterBody2D

const MOVE_SPEED := 90.0
const BODY_RADIUS := 5.0
const BODY_HEIGHT := 14.0

var game_state: GameState
var camera: Camera2D

func _ready() -> void:
	camera = get_node_or_null("Camera2D") as Camera2D
	_ensure_collision()
	queue_redraw()

func _physics_process(_delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): dir.y -= 1.0
	if dir.length_squared() > 0.0:
		dir = dir.normalized()
	velocity = dir * MOVE_SPEED if not _ui_blocks_movement() else Vector2.ZERO
	move_and_slide()
	if game_state != null:
		game_state.update_environment(global_position)

func _unhandled_input(event: InputEvent) -> void:
	if game_state == null or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_X or key.keycode == KEY_X:
		if game_state.is_probe_open:
			if game_state.sample_popup != null:
				game_state.sample_popup.hide_probe()
			return
		if game_state.is_catalogue_open or game_state.is_debug:
			return
		var result := game_state.take_sample(global_position)
		if not result.is_empty() and game_state.sample_popup != null:
			game_state.sample_popup.show_result(result)
		get_viewport().set_input_as_handled()

func _ui_blocks_movement() -> bool:
	return game_state != null and (game_state.is_probe_open or game_state.is_catalogue_open)

func _ensure_collision() -> void:
	if get_node_or_null("CollisionShape2D") != null:
		return
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	var capsule := CapsuleShape2D.new()
	capsule.radius = BODY_RADIUS
	capsule.height = BODY_HEIGHT
	collision.shape = capsule
	add_child(collision)

func _draw() -> void:
	# A literal procedural pill/capsule: no player sprite asset.
	var body_color := Color(0.92, 0.94, 0.96)
	var outline := Color(0.10, 0.12, 0.15)
	var half_straight := (BODY_HEIGHT - BODY_RADIUS * 2.0) * 0.5
	draw_rect(Rect2(-BODY_RADIUS, -half_straight, BODY_RADIUS * 2.0, half_straight * 2.0), body_color)
	draw_circle(Vector2(0.0, -half_straight), BODY_RADIUS, body_color)
	draw_circle(Vector2(0.0, half_straight), BODY_RADIUS, body_color)
	draw_arc(Vector2(0.0, -half_straight), BODY_RADIUS, PI, TAU, 18, outline, 1.2)
	draw_arc(Vector2(0.0, half_straight), BODY_RADIUS, 0.0, PI, 18, outline, 1.2)
	draw_line(Vector2(-BODY_RADIUS, -half_straight), Vector2(-BODY_RADIUS, half_straight), outline, 1.2)
	draw_line(Vector2(BODY_RADIUS, -half_straight), Vector2(BODY_RADIUS, half_straight), outline, 1.2)
