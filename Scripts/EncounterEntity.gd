# scripts/EncounterEntity.gd
# 代表一个可以在大地图上移动，并在玩家靠近时触发战斗的敌人实体
class_name EncounterEntity extends CharacterBody2D

# --- 导出变量 ---
# 这个实体代表哪一场战斗
@export var encounter: Encounter
# 移动速度
@export var speed: float = 50.0
# 游荡半径
@export var wander_radius: float = 100.0

# --- 节点引用 ---
@onready var battle_trigger_area: Area2D = $Area2D

# --- AI 状态变量 ---
var start_position: Vector2
var wander_target: Vector2

# 是否销毁
var remove_after_battle: bool = false

func _ready():
	# 记录初始位置，用于计算游荡范围
	start_position = global_position
	# 连接子区域的信号到本脚本的处理函数上
	battle_trigger_area.body_entered.connect(_on_battle_trigger_area_body_entered)
	# 开始第一次游荡
	_pick_new_wander_target()

func _enter_tree() -> void:
	if remove_after_battle:
		call_deferred("queue_free")

func _physics_process(delta):
	# 如果到达了目标点，就选择下一个目标点
	if global_position.distance_to(wander_target) < 5.0:
		_pick_new_wander_target()
	
	# 朝目标点移动
	var direction = (wander_target - global_position).normalized()
	velocity = direction * speed
	move_and_slide()

# --- 核心逻辑 ---
func _on_battle_trigger_area_body_entered(body):
	# 确保是玩家触发的
	if body == self:
		return
	if body.is_in_group("Player"):
		if remove_after_battle:
			return
		remove_after_battle = true
		battle_trigger_area.set_deferred("monitoring",false)
		print("玩家靠近敌人 %s, 准备开始战斗！" % self.name)
		# 命令GameManager开始战斗
		GameManager.start_battle(encounter)

# --- AI 辅助函数 ---
func _pick_new_wander_target():
	# 在初始位置为圆心，wander_radius为半径的圆内随机选择一个新目标点
	var random_direction = Vector2.from_angle(randf_range(0, TAU))
	var random_distance = randf_range(0, wander_radius)
	wander_target = start_position + random_direction * random_distance
