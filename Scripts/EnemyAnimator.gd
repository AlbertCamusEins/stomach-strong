@tool
class_name EnemyAnimator
extends RefCounted

signal animation_changed(animation_name: StringName)

var animated_sprite: AnimatedSprite2D
var animator_profile: EnemyAnimatorProfile

var _current_animation: StringName

func setup(sprite: AnimatedSprite2D, profile: EnemyAnimatorProfile) -> void:
	animated_sprite = sprite
	animator_profile = profile
	if animated_sprite and animator_profile and animator_profile.world_sprite_frames:
		animated_sprite.sprite_frames = animator_profile.world_sprite_frames
	var default_anim = _resolve_world_animation(&"idle")
	_play_animation(default_anim)

func on_state_changed(state: StringName) -> void:
	var target_animation = _resolve_world_animation(state)
	_play_animation(target_animation)

func _resolve_world_animation(state: StringName) -> StringName:
	if animator_profile:
		return animator_profile.get_world_animation_for_state(state)
	return state if state != StringName() else &"idle"

func _play_animation(animation_name: StringName) -> void:
	if not animated_sprite:
		return
	if _current_animation == animation_name:
		return
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(animation_name):
		animated_sprite.play(animation_name)
	else:
		animated_sprite.play()
	_current_animation = animation_name
	animation_changed.emit(animation_name)
