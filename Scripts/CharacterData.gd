# scripts/CharacterData.gd
# 代表一个独一无二的、可加入队伍的角色实体
@tool
class_name CharacterData extends Resource

# 角色的唯一ID，用于在存档和代码中稳定地识别他/她
@export var character_id: String

# 角色的名字
@export var character_name: String

# 角色在界面中使用的立绘
@export var portrait: Texture2D

# 角色的战斗动画
@export var battle_animation: SpriteFrames

# 这个角色当前的所有属性状态
# 每个角色都拥有自己独立的 CharacterStats 实例
@export var stats: CharacterStats

# 角色的穿戴情况（装备槽 -> Item）
@export var equipped_slots: Dictionary = {}

# 角色的掉落物
@export var loot_drops: Array[InventorySlot] = []
