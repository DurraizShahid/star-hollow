# probe.gd
# -----------------------------------------------------------------------------
# Area2D at the player position. Emits a sample pulse when the player
# presses accept (X key handled by PlayerController).
# -----------------------------------------------------------------------------
class_name Probe
extends Area2D

var game_state: GameState

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	pass

func pulse() -> Dictionary:
	if game_state == null:
		return {}
	return game_state.take_sample(global_position)
