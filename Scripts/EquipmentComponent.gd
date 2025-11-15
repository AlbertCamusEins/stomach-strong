@tool
class_name EquipmentComponent extends Resource

enum EquipmentSlot {
	WEAPON,     # 武器
	HELMET,     # 头部
	CHEST,      # 身体
	LEGS,       # 腿部
	ACCESSORY   # 饰品
}
enum  Sharpness {
	SHARP, #利器
	BLUNT  #钝器
}
@export var hot_swappable: bool = true
@export var slot: EquipmentSlot
@export var weapon_type: Sharpness

@export_group("Stat Bonuses")
@export var max_health: int
@export var max_satiety: int
@export var max_mana: int
@export var attack: int
@export var defense: int
@export var base_speed: int

@export_group("Special Effect")
@export var food_effect: String
@export var skill_power: int
