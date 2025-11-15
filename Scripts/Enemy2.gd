extends EnemyEntity

@export_group("Legacy Behaviour")
@export var legacy_uses_sleep_cycle: bool = true
@export var wander_speed: float = 10.0
@export var flee_speed: float = 25.0
@export var wander_radius: float = 100.0
@export var side_step_factor: float = 0.5
@export var wake_up_animation_time: float = 1.0
@export var fall_asleep_delay: float = 2.0
@export var flee_cooldown: float = 0.0

var _legacy_behavior_profile := EnemyBehaviorProfile.new()
var _legacy_animator_profile := EnemyAnimatorProfile.new()

func _ready() -> void:
	if override_behavior_profile == null:
		_populate_legacy_behavior()
		override_behavior_profile = _legacy_behavior_profile
	elif override_behavior_profile == _legacy_behavior_profile:
		_populate_legacy_behavior()

	if override_animator_profile == null:
		_populate_legacy_animator()
		override_animator_profile = _legacy_animator_profile
	elif override_animator_profile == _legacy_animator_profile:
		_populate_legacy_animator()

	super._ready()

func _populate_legacy_behavior() -> void:
	_legacy_behavior_profile.uses_sleep_cycle = legacy_uses_sleep_cycle
	_legacy_behavior_profile.uses_wander_ai = true
	_legacy_behavior_profile.can_flee_from_player = true
	_legacy_behavior_profile.triggers_battle_on_contact = false
	_legacy_behavior_profile.wander_speed = wander_speed
	_legacy_behavior_profile.wander_radius = wander_radius
	_legacy_behavior_profile.wander_target_tolerance = 5.0
	_legacy_behavior_profile.wander_retarget_interval = 0.0
	_legacy_behavior_profile.flee_speed = flee_speed
	_legacy_behavior_profile.flee_side_step_factor = side_step_factor
	_legacy_behavior_profile.flee_cooldown = flee_cooldown
	_legacy_behavior_profile.wake_up_animation_time = wake_up_animation_time
	_legacy_behavior_profile.fall_asleep_delay = fall_asleep_delay

func _populate_legacy_animator() -> void:
	_legacy_animator_profile.world_default_animation = &"birth"
	_legacy_animator_profile.world_state_animations = {
		&"sleeping": &"birth",
		&"waking_up": &"birth",
		&"wandering": &"walk",
		&"fleeing": &"walk"
	}
	_legacy_animator_profile.world_faces_movement_direction = false
