# scripts/CharacterStats.gd
# A resource to hold all stats for a character or an enemy.
@tool
class_name EnemyStats extends Resource

# --- 基础属性 (Base Stats) ---
# 这些是角色自身、不受装备影响的属性。
@export_group("Base Stats")
@export var base_max_health: int = 100
@export var base_max_satiety: int = 100
@export var base_max_mana: int = 50
@export var base_attack: int = 10
@export var base_defense: int = 5
@export var base_speed: int = 10

# --- 实时状态 (Current Stats) ---
@export_group("Current Stats", "current_")
@export var current_health: int
@export var current_satiety: int
@export var current_mana: int

# --- 装备加成 (Equipment Bonuses) ---
# 这个字典将存储所有已穿戴装备提供的属性加成总和。
var equipment_bonuses: Dictionary

# --- 总属性 (Total Stats) ---
# 我们使用 getter 函数，让这些属性“动态计算”出来。
@export_group("Total Stats (Read-Only)")
@export var max_health: int:
	get:
		# 终极修复：在访问字典前，先检查它是否存在。
		if equipment_bonuses:
			return base_max_health + equipment_bonuses.max_health
		return base_max_health # 如果不存在，则只返回基础值。
@export var max_satiety: int:
	get:
		if equipment_bonuses:
			return base_max_satiety + equipment_bonuses.max_satiety
		return base_max_satiety
@export var max_mana: int:
	get:
		if equipment_bonuses:
			return base_max_mana + equipment_bonuses.max_mana
		return base_max_mana
@export var attack: int:
	get:
		if equipment_bonuses:
			return base_attack + equipment_bonuses.attack
		return base_attack
@export var defense: int:
	get:
		if equipment_bonuses:
			return base_defense + equipment_bonuses.defense
		return base_defense
@export var speed: int:
	get:
		if equipment_bonuses:
			return base_speed + equipment_bonuses.base_speed
		return base_speed

@export_group("Skills")
@export var skills: Array[Skill]

# --- 函数 ---
func _init():
	# 在这里初始化字典，确保它在对象创建时就存在。
	equipment_bonuses = {
		"max_health": 0, "max_satiety": 0, "max_mana": 0,
		"attack": 0, "defense": 0, "base_speed": 0
	}
	# 初始化时，当前值等于基础最大值
	current_health = base_max_health
	current_satiety = base_max_satiety
	current_mana = base_max_mana

# 新增：更新装备加成的函数
func update_equipment_bonuses(equipment_dict: Dictionary):
	# 1. 先重置所有加成
	for key in equipment_bonuses:
		equipment_bonuses[key] = 0
	
	# 2. 遍历所有已穿戴的装备，累加它们的属性
	for item in equipment_dict.values():
		if item and item.equipment_props:
			var props = item.equipment_props
			equipment_bonuses.max_health += props.max_health
			equipment_bonuses.max_satiety += props.max_satiety
			equipment_bonuses.max_mana += props.max_mana
			equipment_bonuses.attack += props.attack
			equipment_bonuses.defense += props.defense
			equipment_bonuses.base_speed += props.base_speed
	
	# 3. 确保当前值不会超过新的最大值
	current_health = clamp(current_health, 0, max_health)
	current_satiety = clamp(current_satiety, 0, max_satiety)
	current_mana = clamp(current_mana, 0, max_mana)

# --- (take_damage, heal 等函数保持不变) ---
func take_damage(damage_amount: int, damage_percentage: float):
	var final_damage = (damage_amount - defense) * damage_percentage
	if final_damage < 1:
		final_damage = 1
	current_health -= final_damage
	current_health = clamp(current_health, 0, max_health)

func heal(heal_amount: int):
	current_health += heal_amount
	current_health = clamp(current_health, 0, max_health)

func change_satiety(amount: int):
	current_satiety += amount
	current_satiety = clamp(current_satiety, 0, max_satiety)

func change_mana(amount: int):
	current_mana += amount
	current_mana = clamp(current_mana, 0, max_mana)
