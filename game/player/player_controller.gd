# player_controller.gd
# -----------------------------------------------------------------------------
# WASD top-down movement. Camera follows player. Probe X to take sample.
# This script IS the player (extends CharacterBody2D).
# -----------------------------------------------------------------------------
class_name PlayerController
extends CharacterBody2D

const MOVE_SPEED := 80.0
const PROBE_OFFSET := 20.0

var game_state: GameState
var camera: Camera2D
var probe_area: Area2D

func _physics_process(_delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("ui_right"):
		dir.x += 1
	if Input.is_action_pressed("ui_left"):
		dir.x -= 1
	if Input.is_action_pressed("ui_down"):
		dir.y += 1
	if Input.is_action_pressed("ui_up"):
		dir.y -= 1
	if dir.length() > 0.0:
		dir = dir.normalized()
	velocity = dir * MOVE_SPEED
	move_and_slide()
	camera.global_position = global_position

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not game_state.is_catalogue_open and not game_state.is_debug:
		var result := game_state.take_sample(global_position)
		if not result.is_empty() and result.get("discovery", {}).get("new", []).size() > 0:
			print("NEW DISCOVERY: %s" % result["discovery"]["new"])

func _ready() -> void:
	camera = $Camera2D as Camera2D
	probe_area = $ProbeArea as Area2D
	probe_area.position = Vector2(0, -PROBE_OFFSET)
	probe_area.monitoring = true
	probe_area.body_entered.connect(func(_b): pass)
