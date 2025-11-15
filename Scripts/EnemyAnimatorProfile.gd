@tool
class_name EnemyAnimatorProfile
extends Resource

## Container for all animation resources and state-to-animation bindings
## that an enemy requires both in the overworld and in battle scenes.

@export_group("World Rendering")
@export var world_sprite_frames: SpriteFrames
@export var world_default_animation: StringName = &"idle"
@export var world_state_animations: Dictionary = {
	&"sleeping": &"idle",
	&"waking_up": &"birth",
	&"wandering": &"walk",
	&"fleeing": &"run"
}
@export var world_faces_movement_direction: bool = true

@export_group("Battle Rendering")
@export var battle_sprite_frames: SpriteFrames
@export var battle_default_animation: StringName = &"idle"
@export var battle_state_animations: Dictionary = {}

@export_group("Portraits")
@export var portrait: Texture2D
@export var portrait_variant: Texture2D

func get_world_animation_for_state(state: StringName) -> StringName:
	if state in world_state_animations:
		return world_state_animations[state]
	return world_default_animation

func get_battle_animation_for_state(state: StringName) -> StringName:
	if state in battle_state_animations:
		return battle_state_animations[state]
	return battle_default_animation
