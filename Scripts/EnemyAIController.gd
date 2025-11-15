@tool
class_name EnemyAIController
extends RefCounted

signal state_changed(previous_state: StringName, new_state: StringName)
signal player_target_changed(player: Node)

const STATE_SLEEPING: StringName = &"sleeping"
const STATE_WAKING_UP: StringName = &"waking_up"
const STATE_WANDERING: StringName = &"wandering"
const STATE_FLEEING: StringName = &"fleeing"

var entity: CharacterBody2D
var behavior_profile: EnemyBehaviorProfile
var perception: EnemyPerception

var current_state: StringName = STATE_SLEEPING
var start_position: Vector2
var wander_target: Vector2

var state_timer: float = 0.0
var wander_retarget_timer: float = 0.0
var flee_cooldown_timer: float = 0.0
var fall_asleep_timer: float = -1.0

var player_ref: CharacterBody2D
var current_velocity: Vector2 = Vector2.ZERO

func setup(p_entity: CharacterBody2D, p_behavior: EnemyBehaviorProfile, p_perception: EnemyPerception) -> void:
	entity = p_entity
	behavior_profile = p_behavior if p_behavior else EnemyBehaviorProfile.new()
	perception = p_perception

	start_position = entity.global_position
	_select_initial_state()
	_bind_perception()

func update(delta: float) -> void:
	_process_timers(delta)

	match current_state:
		STATE_SLEEPING:
			current_velocity = Vector2.ZERO
		STATE_WAKING_UP:
			current_velocity = Vector2.ZERO
			state_timer -= delta
			if state_timer <= 0.0:
				_transition_to(STATE_WANDERING)
		STATE_WANDERING:
			_update_wander(delta)
		STATE_FLEEING:
			_update_flee(delta)

func get_velocity() -> Vector2:
	return current_velocity

func notify_state_completed(state_name: StringName) -> void:
	if state_name == STATE_WAKING_UP and current_state == STATE_WAKING_UP:
		_transition_to(STATE_WANDERING)

func _select_initial_state() -> void:
	if behavior_profile.uses_sleep_cycle:
		_set_state(STATE_SLEEPING)
	else:
		_set_state(STATE_WANDERING)

func _bind_perception() -> void:
	if not perception:
		return
	perception.wake_body_entered.connect(_on_wake_body_entered)
	perception.wake_body_exited.connect(_on_wake_body_exited)
	perception.fear_body_entered.connect(_on_fear_body_entered)
	perception.fear_body_exited.connect(_on_fear_body_exited)
	perception.battle_body_entered.connect(_on_battle_body_entered)

func _process_timers(delta: float) -> void:
	if wander_retarget_timer > 0.0:
		wander_retarget_timer -= delta
	if flee_cooldown_timer > 0.0:
		flee_cooldown_timer -= delta
	if fall_asleep_timer >= 0.0:
		fall_asleep_timer -= delta
		if fall_asleep_timer <= 0.0 and behavior_profile.uses_sleep_cycle and current_state != STATE_SLEEPING:
			_transition_to(STATE_SLEEPING)

func _update_wander(delta: float) -> void:
	if not behavior_profile.uses_wander_ai:
		current_velocity = Vector2.ZERO
		return

	if wander_target == Vector2.ZERO:
		_pick_new_wander_target()

	var distance = entity.global_position.distance_to(wander_target)
	if distance <= behavior_profile.wander_target_tolerance:
		_pick_new_wander_target()

	if behavior_profile.wander_retarget_interval > 0.0 and wander_retarget_timer <= 0.0:
		_pick_new_wander_target()

	var direction = entity.global_position.direction_to(wander_target)
	current_velocity = direction * behavior_profile.wander_speed

func _update_flee(delta: float) -> void:
	if not behavior_profile.can_flee_from_player:
		_transition_to(STATE_WANDERING)
		return

	if not _is_valid_player(player_ref):
		if flee_cooldown_timer <= 0.0:
			_transition_to(STATE_WANDERING)
		return

	var away_direction = player_ref.global_position.direction_to(entity.global_position)
	var side_direction = away_direction.orthogonal() * behavior_profile.flee_side_step_factor
	var flee_direction = (away_direction + side_direction).normalized()
	current_velocity = flee_direction * behavior_profile.flee_speed

func _pick_new_wander_target() -> void:
	var random_direction = Vector2.from_angle(randf_range(0.0, TAU))
	var random_distance = randf_range(0.0, behavior_profile.wander_radius)
	wander_target = start_position + random_direction * random_distance
	wander_retarget_timer = behavior_profile.wander_retarget_interval

func _transition_to(new_state: StringName) -> void:
	if current_state == new_state:
		return
	var previous_state = current_state
	current_state = new_state
	state_changed.emit(previous_state, current_state)
	if current_state == STATE_WAKING_UP:
		state_timer = max(behavior_profile.wake_up_animation_time, 0.0)
	if current_state == STATE_WANDERING:
		if behavior_profile.uses_wander_ai:
			_pick_new_wander_target()
		current_velocity = Vector2.ZERO
	if current_state == STATE_SLEEPING:
		current_velocity = Vector2.ZERO
	if current_state == STATE_FLEEING:
		_pick_new_wander_target()
			

func _set_state(new_state: StringName) -> void:
	current_state = new_state
	state_changed.emit(StringName(), current_state)
	if current_state == STATE_WANDERING and behavior_profile.uses_wander_ai:
		_pick_new_wander_target()

func _on_wake_body_entered(body: Node) -> void:
	if not _is_player(body):
		return
	player_ref = body
	player_target_changed.emit(body)
	if behavior_profile.uses_sleep_cycle and current_state == STATE_SLEEPING:
		_transition_to(STATE_WAKING_UP)
	elif current_state == STATE_WANDERING and behavior_profile.can_flee_from_player:
		_transition_to(STATE_FLEEING)

func _on_wake_body_exited(body: Node) -> void:
	if not _is_player(body):
		return
	if body == player_ref:
		player_ref = null
		player_target_changed.emit(null)
	if behavior_profile.uses_sleep_cycle:
		fall_asleep_timer = behavior_profile.fall_asleep_delay

func _on_fear_body_entered(body: Node) -> void:
	if not _is_player(body):
		return
	player_ref = body
	player_target_changed.emit(body)
	if behavior_profile.can_flee_from_player and current_state in [STATE_WANDERING, STATE_SLEEPING]:
		_transition_to(STATE_FLEEING)

func _on_fear_body_exited(body: Node) -> void:
	if not _is_player(body):
		return
	if body == player_ref:
		player_ref = null
		player_target_changed.emit(null)
	flee_cooldown_timer = behavior_profile.flee_cooldown
	if behavior_profile.can_flee_from_player and flee_cooldown_timer > 0:
		return
	_transition_to(STATE_WANDERING)

func _on_battle_body_entered(body: Node) -> void:
	if not _is_player(body):
		return
	# Leave the actual battle triggering to a dedicated EncounterTrigger component.
	pass

func _is_player(body: Node) -> bool:
	return body and body.has_method("is_in_group") and body.is_in_group("Player")

func _player_is_moving(body: Node) -> bool:
	if body == null:
		return false
	if body is CharacterBody2D:
		return (body as CharacterBody2D).velocity.length() > 0.01
	if body is Node3D:
		return false
	return false

func _is_valid_player(player: Node) -> bool:
	return player and is_instance_valid(player)
