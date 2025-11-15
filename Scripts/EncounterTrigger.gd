@tool
class_name EncounterTrigger
extends RefCounted

signal battle_triggered(encounter: Encounter, enemy: CharacterBody2D, player: Node)

var battle_area: Area2D
var behavior_profile: EnemyBehaviorProfile
var owner_entity: CharacterBody2D

var _disabled: bool = false

func setup(area: Area2D, profile: EnemyBehaviorProfile, entity: CharacterBody2D) -> void:
	battle_area = area
	behavior_profile = profile
	owner_entity = entity
	_bind_area()

func is_ready() -> bool:
	return battle_area != null and behavior_profile != null and behavior_profile.triggers_battle_on_contact

func mark_battle_resolved() -> void:
	if not behavior_profile:
		return
	if behavior_profile.remove_after_battle:
		if owner_entity:
			owner_entity.queue_free()
		return
	var delay = max(behavior_profile.battle_reenable_delay, 0.0)
	if delay <= 0.0:
		_enable_trigger()
	else:
		_schedule_reenable(delay)

func _bind_area() -> void:
	if not battle_area:
		return
	if battle_area.body_entered.is_connected(_on_battle_body_entered):
		return
	battle_area.body_entered.connect(_on_battle_body_entered)

func _on_battle_body_entered(body: Node) -> void:
	if _disabled:
		return
	if not is_ready():
		return
	if not body or not body.has_method("is_in_group") or not body.is_in_group("Player"):
		return
	_trigger_battle(body)

func _trigger_battle(player: Node) -> void:
	_disabled = true
	_set_monitoring(false)
	battle_triggered.emit(behavior_profile.encounter_resource, owner_entity, player)

func _enable_trigger() -> void:
	_disabled = false
	_set_monitoring(true)

func _schedule_reenable(delay: float) -> void:
	if not owner_entity:
		return
	var tree := owner_entity.get_tree()
	if not tree:
		return
	var timer = tree.create_timer(delay)
	timer.timeout.connect(_enable_trigger)

func _set_monitoring(enabled: bool) -> void:
	if battle_area:
		battle_area.set_deferred("monitoring", enabled)
