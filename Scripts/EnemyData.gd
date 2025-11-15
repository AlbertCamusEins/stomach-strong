@tool
class_name EnemyData extends Resource

@export_group("Identity")
@export var enemy_id: String
@export var enemy_name: String

@export_group("Behavior")
@export var behavior_profile: EnemyBehaviorProfile
@export var stats: EnemyStats

@export_group("Presentation")
@export var animator_profile: EnemyAnimatorProfile

@export_group("Legacy Presentation (Deprecated)")
@export var portrait: Texture2D
@export var battle_animation: SpriteFrames
@export var world_animation: SpriteFrames

@export_group("Equipment & Loot")
@export var equipped_slots: Dictionary = {}
@export var loot_drops: Array[InventorySlot] = []
