@tool
class_name EnemyEntity
extends CharacterBody2D

@export_group("Configuration")
@export var enemy_data: EnemyData
@export var override_behavior_profile: EnemyBehaviorProfile
@export var override_animator_profile: EnemyAnimatorProfile

@export_group("Scene Hooks")
@export var animated_sprite_path: NodePath = NodePath("AnimatedSprite2D")
@export var wake_area_path: NodePath = NodePath("BirthTriggerArea")
@export var fear_area_path: NodePath = NodePath("FearArea")
@export var battle_area_path: NodePath = NodePath("BattleTriggerArea")

var perception: EnemyPerception
var animator: EnemyAnimator
var ai_controller: EnemyAIController
var encounter_trigger: EncounterTrigger

var _behavior_profile: EnemyBehaviorProfile
var _animator_profile: EnemyAnimatorProfile

func _ready() -> void:
	_behavior_profile = override_behavior_profile
	if not _behavior_profile and enemy_data:
		_behavior_profile = enemy_data.behavior_profile
	if not _behavior_profile:
		_behavior_profile = EnemyBehaviorProfile.new()

	_animator_profile = override_animator_profile
	if not _animator_profile and enemy_data:
		_animator_profile = enemy_data.animator_profile

	var animated_sprite = _get_node_or_null(animated_sprite_path, AnimatedSprite2D)
	var wake_area = _get_node_or_null(wake_area_path, Area2D)
	var fear_area = _get_node_or_null(fear_area_path, Area2D)
	var battle_area = _get_node_or_null(battle_area_path, Area2D)

	perception = EnemyPerception.new()
	perception.setup(wake_area, fear_area, battle_area)

	animator = EnemyAnimator.new()
	animator.setup(animated_sprite, _animator_profile)

	ai_controller = EnemyAIController.new()
	ai_controller.setup(self, _behavior_profile, perception)
	ai_controller.state_changed.connect(_on_ai_state_changed)

	if animated_sprite:
		animated_sprite.animation_finished.connect(_on_animation_finished)
	if animator:
		ai_controller.state_changed.connect(_forward_state_to_animator)

	if battle_area and _behavior_profile.triggers_battle_on_contact:
		encounter_trigger = EncounterTrigger.new()
		encounter_trigger.setup(battle_area, _behavior_profile, self)
		if encounter_trigger.is_ready():
			encounter_trigger.battle_triggered.connect(_on_battle_triggered)

func _physics_process(delta: float) -> void:
	# 如果在编辑器模式下运行，就直接返回，不执行任何游戏逻辑
	if Engine.is_editor_hint():
		return

	if ai_controller:
		ai_controller.update(delta)
	velocity = ai_controller.get_velocity() if ai_controller else Vector2.ZERO
	move_and_slide()

func _forward_state_to_animator(_previous: StringName, new_state: StringName) -> void:
	if animator:
		animator.on_state_changed(new_state)

func _on_ai_state_changed(_previous: StringName, new_state: StringName) -> void:
	if new_state == EnemyAIController.STATE_SLEEPING:
		velocity = Vector2.ZERO

func _on_animation_finished() -> void:
	if not ai_controller or not animator or not animator.animated_sprite:
		return
	ai_controller.notify_state_completed(animator.animated_sprite.animation)

func _on_battle_triggered(encounter: Encounter, _enemy: CharacterBody2D, _player: Node) -> void:
	if encounter:
		if typeof(GameManager) != TYPE_NIL and GameManager.has_method("start_battle"):
			GameManager.start_battle(encounter)
	if encounter_trigger:
		encounter_trigger.mark_battle_resolved()

func _get_node_or_null(path: NodePath, type_hint = null):
	if path.is_empty():
		return null
	var node = get_node_or_null(path)
	if node and typeof(type_hint) != TYPE_NIL:
		if not is_instance_of(node, type_hint):
			return null
	return node
