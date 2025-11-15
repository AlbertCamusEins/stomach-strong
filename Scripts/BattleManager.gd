# scripts/BattleManager.gd (多人战斗版)
# 战斗的“大脑”，现在可以管理多个我方单位和多个敌方单位
class_name BattleManager extends Node

# --- 枚举和信号 ---
enum State { SETUP, NEW_ROUND, ACTION, PLAYER_INPUT,PLAYER_TARGETING, WIN, LOSE }

# --- 导出变量 ---
@export var combatant_scene: PackedScene

# --- 节点引用 ---
@onready var player_spawn_points: Node2D = $"../PlayerSpawnPoints"
@onready var enemy_spawn_points: Node2D = $"../EnemySpawnPoints"
@onready var battle_ui: CanvasItem = $"/root/Battle/CanvasLayer/BattleUI"
@onready var enemy_turn_timer: Timer = $EnemyTurnTimer

# --- 战斗状态变量 ---
var player_party: Array[Combatant] = []
var enemy_party: Array[Combatant] = []
var combatants: Array[Combatant] = []
var action_queue: Array[Combatant] = []
var current_actor: Combatant
var current_state: State = State.SETUP
var player_inventory: Array # 存储本次战斗中玩家的背包
var pending_item: Item # 物品选择（待目标选择）
var defeated_combatants: Array[Combatant] = []

# 敌人掉落统计
var defeat_log: Array = []
var pending_loot: Dictionary = {}
var victory_screen_shown: bool = false

# --- [新增] 存储玩家在选择目标前的意图 ---
var pending_action_type: String # "attack", "skill", "item"
var pending_skill: Skill # 如果是技能，存储是哪个技能


# --- 战斗设置与生成 ---
func setup_battle(battle_data: Dictionary):
	var player_ids = battle_data.get("player_party_ids")
	var enemy_data = battle_data.get("enemy_party_data")
	
	# 从GameManager获取背包数据
	player_inventory = GameManager.player_current_inventory
	
	defeated_combatants.clear()
	defeat_log.clear()
	pending_loot.clear()
	victory_screen_shown = false

	_spawn_party(player_ids, true)
	_spawn_party(enemy_data, false)
	# 兜底：若玩家编队为空，使用当前玩家属性生成一个临时战斗单位，避免卡在敌方回合
	if player_party.is_empty() and GameManager.player_current_stats:
		var cd := CharacterData.new()
		cd.character_id = "player_fallback"
		cd.character_name = "Hero"
		cd.stats = GameManager.player_current_stats.duplicate(true)
		var c = combatant_scene.instantiate() as Combatant
		c.setup(cd)
		player_spawn_points.add_child(c)
		c.position = Vector2(0, 0)
		player_party.append(c)
	
	combatants = player_party + enemy_party
	
	# 连接信号
	connect_ui_signals()
	connect_additional_ui_signals()
	enemy_turn_timer.timeout.connect(_on_enemy_turn_timer_timeout)
	
	# 生成UI
	battle_ui.setup_ui(player_party, enemy_party)

	# 基于状态块位置，重新放置双方单位到各自状态块中心上方50像素
	for member in player_party:
		var pos = battle_ui.get_spawn_position_for(member)
		if pos != Vector2.ZERO:
			member.global_position = pos
	for member in enemy_party:
		var pos = battle_ui.get_spawn_position_for(member)
		if pos != Vector2.ZERO:
			member.global_position = pos
	
	change_state(State.NEW_ROUND)

func _spawn_party(party_data: Array, is_player_party: bool):
	var spawn_container = player_spawn_points if is_player_party else enemy_spawn_points
	var target_array = player_party if is_player_party else enemy_party
	
	for i in range(party_data.size()):
		var character_data: CharacterData
		if is_player_party:
			character_data = GameManager.all_characters.get(party_data[i])
		else:
			character_data = party_data[i]

		if not character_data: continue
			
		var combatant_instance = combatant_scene.instantiate() as Combatant
		combatant_instance.setup(character_data)
		spawn_container.add_child(combatant_instance)
		#combatant_instance.position = Vector2(i * 150, 0)
		target_array.append(combatant_instance)
		combatant_instance.hide()

# --- 状态机核心 (已重构) ---
func change_state(new_state: State):
	current_state = new_state
	match current_state:
		State.NEW_ROUND:
			battle_ui.log_message("新回合开始")
			# [核心修改] 为所有单位重置回合状态
			for unit in combatants:
				unit.start_turn()
			
			build_action_queue()
			change_state(State.ACTION)
			
		State.ACTION:
			if action_queue.is_empty():
				change_state(State.NEW_ROUND)
				return
			
			current_actor = action_queue.pop_front()
			
			# 如果当前行动者已经阵亡，则跳过
			if current_actor.stats.current_health <= 0:
				change_state(State.ACTION)
				return

			# [核心修改] 判断行动者属于哪个队伍
			if current_actor in player_party:
				change_state(State.PLAYER_INPUT)
			elif current_actor in enemy_party:
				battle_ui.log_message("%s的回合。" % current_actor.name)
				enemy_turn_timer.start()
			
		State.PLAYER_INPUT:
			battle_ui.log_message("轮到 %s 行动。" % current_actor.name)
			battle_ui.show_action_menu(true) # TODO: 需要显示是为哪个角色显示菜单
		
		# [新增] 进入目标选择状态
		State.PLAYER_TARGETING:
			battle_ui.log_message("选择一个目标...")
			# UI部分已经在 BattleUI.gd 中处理
			
		State.WIN:
			if victory_screen_shown:
				return
			victory_screen_shown = true
			enemy_turn_timer.stop()
			action_queue.clear()
			battle_ui.log_message("你赢了！")
			battle_ui.show_victory_screen(pending_loot)
			if not battle_ui.has_victory_panel():
				GameManager.end_battle()
			return

		State.LOSE:
			battle_ui.log_message("你被打败了...")
			GameManager.end_battle()

func build_action_queue():
	action_queue = combatants.duplicate()
	action_queue.sort_custom(func(a, b): return a.final_speed > b.final_speed)

# --- 敌人AI (已重构) ---
func _on_enemy_turn_timer_timeout():
	var attacker = current_actor
	# [核心修改] AI随机选择一个我方存活单位作为目标
	var target = _get_random_living_player()
	if not target: return # 如果没有我方单位了，可能已经失败
	
	var damage_percentage = 1.0
	if target.is_defending:
		damage_percentage = 0.5
	
	var damage_amount = attacker.stats.attack
	target.stats.take_damage(damage_amount, damage_percentage)
	# 伤害已结算，刷新UI以显示最新数值
	battle_ui.update_all_statuses()
	
	var damage_dealt = int((damage_amount - target.stats.defense) * damage_percentage)
	if damage_dealt < 1: damage_dealt = 1
	
	battle_ui.log_message("%s 攻击了 %s, 造成了 %d 点伤害。" % [attacker.name, target.name, damage_dealt])
	
	check_for_win_lose()

# --- 胜负与辅助函数 (已重构) ---
func check_for_win_lose():
	# TODO: 更新多人UI
	# battle_ui.update_status_multi(player_party, enemy_party)

	if _is_party_defeated(enemy_party):
		change_state(State.WIN)
	elif _is_party_defeated(player_party):
		change_state(State.LOSE)
	else:
		# 如果战斗未结束，则继续处理行动队列
		change_state(State.ACTION)

func _is_party_defeated(party: Array[Combatant]) -> bool:
	for member in party:
		if member.stats.current_health > 0:
			return false # 只要有一个人还活着，队伍就没输
	return true

func _get_all_living_enemies() -> Array[Combatant]:
	var living_enemies: Array[Combatant] = []
	for enemy in enemy_party:
		if enemy.stats.current_health > 0:
			living_enemies.append(enemy)
	return living_enemies

func _get_first_living_enemy() -> Combatant:
	for enemy in enemy_party:
		if enemy.stats.current_health > 0:
			return enemy
	return null

func _get_random_living_player() -> Combatant:
	var living_players: Array[Combatant] = []
	for player in player_party:
		if player.stats.current_health > 0:
			living_players.append(player)
	
	if not living_players.is_empty():
		return living_players.pick_random()
	return null

func _get_all_living_players() -> Array[Combatant]:
	var living_players: Array[Combatant] = []
	for player in player_party:
		if player.stats.current_health > 0:
			living_players.append(player)
	return living_players

# --- 信号连接 ---
func connect_ui_signals():
	# 将UI发出的信号连接到这个脚本中的处理函数上
	battle_ui.attack_pressed.connect(_on_player_attack)
	battle_ui.defend_button_pressed.connect(_on_player_defend)
		# [新增] 连接目标选择UI的信号
	battle_ui.target_selected.connect(_on_target_selected)
	battle_ui.targeting_cancelled.connect(_on_targeting_cancelled)

# --- 玩家行动处理 (已重构) ---
func _on_player_attack():
	if current_state != State.PLAYER_INPUT: return
	
	pending_action_type = "attack"
	# 获取所有活着的敌人作为可选目标
	var targets = _get_all_living_enemies()
	battle_ui.start_targeting(targets)
	change_state(State.PLAYER_TARGETING)

func _on_player_defend():
	if current_state != State.PLAYER_INPUT: return
	
	var defender = current_actor
	defender.is_defending = true
	battle_ui.log_message("%s 采取了防御姿态！" % defender.name)
	check_for_win_lose()

# 单独补充被临时屏蔽的技能/物品相关信号连接
func connect_additional_ui_signals():
	battle_ui.item_pressed.connect(_on_player_item)
	battle_ui.skill_pressed.connect(_on_player_skill)
	battle_ui.food_item_selected.connect(_on_player_choose_item)
	battle_ui.skill_selected.connect(_on_skill_chosen)
	battle_ui.weapon_selected.connect(_on_player_choose_weapon)
	# 战斗胜利界面信号
	if not battle_ui.victory_loot_clicked.is_connected(_on_victory_loot_clicked):
		battle_ui.victory_loot_clicked.connect(_on_victory_loot_clicked)
	if not battle_ui.victory_confirmed.is_connected(_on_victory_confirmed):
		battle_ui.victory_confirmed.connect(_on_victory_confirmed)

# 打开物品菜单
func _on_player_item():
	if current_state != State.PLAYER_INPUT: return
	# 收集可用的消耗品和武器（去重显示）
	var food_slots: Array[InventorySlot] = []
	var weapon_slots: Array[InventorySlot] = []
	for slot in player_inventory:
		if not slot or not slot.item:
			continue
		if slot.quantity <= 0:
			continue
		var item = slot.item
		if item.consumable_props:
			food_slots.append(slot)
			continue
		if item.equipment_props and item.equipment_props.slot == EquipmentComponent.EquipmentSlot.WEAPON and item.equipment_props.hot_swappable:
			# 只显示可热切换的武器
			weapon_slots.append(slot)
	var equipped_weapon = _get_equipped_weapon(current_actor)
	battle_ui.open_item_menu(food_slots, weapon_slots, equipped_weapon)

# 物品两阶段：先选物品，再选友方目标
func _on_player_choose_item(food_item: Item):
	if current_state != State.PLAYER_INPUT: return
	if not food_item or not food_item.consumable_props:
		return
	pending_action_type = "item"
	pending_item = food_item
	var targets = _get_all_living_players()
	if targets.is_empty():
		battle_ui.log_message("没有可选友方目标")
		return
	battle_ui.start_targeting(targets)
	change_state(State.PLAYER_TARGETING)

# 打开技能菜单
func _on_player_skill():
	if current_state != State.PLAYER_INPUT: return
	var skills: Array[Skill] = current_actor.stats.skills
	battle_ui.open_skill_menu(skills)



# 新的技能选择入口：只设置待执行技能并根据目标类型进入选择或立即生效
func _on_skill_chosen(skill: Skill):
	if current_state != State.PLAYER_INPUT: return
	if not skill:
		return
	if not _can_pay_skill_cost(current_actor, skill):
		battle_ui.log_message("资源不足，无法使用 %s" % skill.skill_name)
		return
	
	pending_action_type = "skill"
	pending_skill = skill
	match skill.target_type:
		Skill.TargetType.SELF:
			_pay_skill_cost(current_actor, skill)
			_apply_skill_effect(current_actor, current_actor, skill)
			battle_ui.update_all_statuses()
			battle_ui.log_message("%s 对自己使用了技能 %s" % [current_actor.name, skill.skill_name])
			pending_action_type = ""
			pending_skill = null
			check_for_win_lose()
			return
		Skill.TargetType.ENEMY_SINGLE:
			var enemies = _get_all_living_enemies()
			if enemies.is_empty():
				battle_ui.log_message("没有可选敌方目标")
				return
			battle_ui.start_targeting(enemies)
			change_state(State.PLAYER_TARGETING)
		Skill.TargetType.ALLY_SINGLE:
			var allies = _get_all_living_players()
			if allies.is_empty():
				battle_ui.log_message("没有可选友方目标")
				return
			battle_ui.start_targeting(allies)
			change_state(State.PLAYER_TARGETING)
		_:
			return

# 技能消耗检查/结算
func _on_victory_loot_clicked(item: Item) -> void:
	if not item:
		return
	var key := _identify_loot_key(item)
	if key.is_empty():
		key = str(item)
	if not pending_loot.has(key):
		return
	var entry: Dictionary = pending_loot[key]
	var quantity: int = int(entry.get("quantity", 0))
	if quantity <= 0:
		return
	var loot_item: Item = entry.get("item")
	if loot_item:
		GameManager.add_item(loot_item, quantity)
	entry["quantity"] = 0
	entry["claimed"] = true
	pending_loot[key] = entry
	battle_ui.update_victory_loot_quantity(key, 0)

func _on_victory_confirmed() -> void:
	for key in pending_loot.keys():
		var entry: Dictionary = pending_loot[key]
		var quantity: int = int(entry.get("quantity", 0))
		if quantity <= 0:
			continue
		var loot_item: Item = entry.get("item")
		if loot_item:
			GameManager.add_item(loot_item, quantity)
		entry["quantity"] = 0
		entry["claimed"] = true
		pending_loot[key] = entry
		battle_ui.update_victory_loot_quantity(key, 0)
	battle_ui.hide_victory_screen()
	pending_loot.clear()
	GameManager.end_battle()

# 技能消耗检查/结算辅助函数
func _can_pay_skill_cost(user: Combatant, skill: Skill) -> bool:
	match skill.cost_type:
		Skill.CostType.MANA:
			return user.stats.current_mana >= skill.cost
		Skill.CostType.SATIETY:
			return user.stats.current_satiety >= skill.cost
		_:
			return true

func _pay_skill_cost(user: Combatant, skill: Skill) -> void:
	match skill.cost_type:
		Skill.CostType.MANA:
			user.stats.change_mana(-skill.cost)
		Skill.CostType.SATIETY:
			user.stats.change_satiety(-skill.cost)
		_:
			pass

# 技能效果应用：对敌即伤害，对友/自身按正power治疗
func _apply_skill_effect(user: Combatant, target: Combatant, skill: Skill) -> void:
	if skill.target_type == Skill.TargetType.ENEMY_SINGLE:
		var base = user.stats.attack
		var damage_amount = base + skill.power
		target.stats.take_damage(damage_amount, 1.0)
		_maybe_register_enemy_defeat(target)
	else:
		if skill.power > 0:
			target.stats.heal(skill.power)
		elif skill.power < 0:
			target.stats.take_damage(-skill.power, 1.0)
			_maybe_register_enemy_defeat(target)


func _maybe_register_enemy_defeat(target: Combatant) -> void:
	if not target:
		return
	if not target.stats:
		return
	if target.stats.current_health > 0:
		return
	_register_enemy_defeat(target)

func _register_enemy_defeat(target: Combatant) -> void:
	if not target:
		return
	if not enemy_party.has(target):
		return
	if defeated_combatants.has(target):
		return
	defeated_combatants.append(target)
	if target.character_data:
		defeat_log.append(target.character_data)
	var loot_slots = _get_loot_slots_from_character(target.character_data)
	for slot in loot_slots:
		if slot is InventorySlot and slot.item:
			var item_key = _identify_loot_key(slot.item)
			if item_key.is_empty():
				item_key = str(slot.item)
			if not pending_loot.has(item_key):
				pending_loot[item_key] = {"item": slot.item.duplicate(true), "quantity": 0, "claimed": false}
			var loot_entry: Dictionary = pending_loot[item_key]
			loot_entry["quantity"] = int(loot_entry.get("quantity", 0)) + slot.quantity
			loot_entry["claimed"] = false
			pending_loot[item_key] = loot_entry

func _get_loot_slots_from_character(data: CharacterData) -> Array:
	if not data:
		return []
	var property_list = data.get_property_list()
	for property in property_list:
		if property.get("name", "") == "loot_drops":
			var loot_value = data.get("loot_drops")
			if typeof(loot_value) == TYPE_ARRAY:
				return loot_value
			break
	return []


func _identify_loot_key(item: Item) -> String:
	if not item:
		return ""
	if item.item_name and not item.item_name.is_empty():
		return item.item_name
	if not item.resource_path.is_empty():
		return item.resource_path
	return ""



# [新增] 核心的目标确认处理函数

func _on_target_selected(target: Combatant):
	if current_state != State.PLAYER_TARGETING: return
	
	# 物品目标选择优先处理，避免落入原有攻击分支
	if pending_action_type == "item":
		var attacker = current_actor
		if pending_item and pending_item.consumable_props:
			var props = pending_item.consumable_props
			if props.health_change != 0:
				if props.health_change > 0:
					target.stats.heal(props.health_change)
				else:
					target.stats.take_damage(-props.health_change, 1.0)
					_maybe_register_enemy_defeat(target)
			if props.mana_change != 0:
				target.stats.change_mana(props.mana_change)
			if props.satiety_change != 0:
				target.stats.change_satiety(props.satiety_change)
			battle_ui.update_all_statuses()
			battle_ui.log_message("%s 对 %s 使用了 %s" % [attacker.name, target.name, pending_item.item_name])
			GameManager.remove_item(pending_item,1)
		else:
			battle_ui.log_message("物品无效或不可使用")
		pending_action_type = ""
		pending_item = null
		check_for_win_lose()
		return
	
	# 技能目标选择：优先于普通攻击处理
	if pending_action_type == "skill":
		var attacker = current_actor
		if not _can_pay_skill_cost(attacker, pending_skill):
			battle_ui.log_message("资源不足，无法使用 %s" % pending_skill.skill_name)
		else:
			_pay_skill_cost(attacker, pending_skill)
			_apply_skill_effect(attacker, target, pending_skill)
			battle_ui.update_all_statuses()
			battle_ui.log_message("%s 对 %s 使用了技能 %s" % [attacker.name, target.name, pending_skill.skill_name])
		pending_action_type = ""
		pending_skill = null
		check_for_win_lose()
		return

	var attacker = current_actor
	
	# 根据之前存储的意图，执行相应的动作
	match pending_action_type:
		"attack":
			var damage_percentage = 1.0
			if target.is_defending:
				damage_percentage = 0.5
			
			var damage_amount = attacker.stats.attack
			target.stats.take_damage(damage_amount, damage_percentage)
			_maybe_register_enemy_defeat(target)
			# 伤害已结算，刷新UI以显示最新数值
			battle_ui.update_all_statuses()
			
			var damage_dealt = int((damage_amount - target.stats.defense) * damage_percentage)
			if damage_dealt < 1: damage_dealt = 1
			
			battle_ui.log_message("%s 攻击了 %s, 造成了 %d 点伤害。" % [attacker.name, target.name, damage_dealt])
	
	# 清空意图
	pending_action_type = ""
	# 行动结束后，检查胜负
	check_for_win_lose()

# [新增] 当玩家取消目标选择时

func _on_targeting_cancelled():
	if current_state != State.PLAYER_TARGETING: return
	# 让玩家可以重新选择行动
	change_state(State.PLAYER_INPUT)

# 在物品菜单中选择具体消耗品（对当前角色立即生效）（已弃用）

func _on_player_use_food(food_item: Item):
	if current_state != State.PLAYER_INPUT: return
	if not food_item or not food_item.consumable_props:
		return
	var props = food_item.consumable_props
	if props.health_change != 0:
		if props.health_change > 0:
			current_actor.stats.heal(props.health_change)
		else:
			current_actor.stats.take_damage(-props.health_change, 1.0)
	if props.mana_change != 0:
		current_actor.stats.change_mana(props.mana_change)
	if props.satiety_change != 0:
		current_actor.stats.change_satiety(props.satiety_change)
	battle_ui.update_all_statuses()
	battle_ui.log_message("%s 使用了 %s" % [current_actor.name, food_item.item_name])
	# 扣除物品数量 -> GameManager.remove_item(food_item, 1)
	GameManager.remove_item(food_item, 1)
	check_for_win_lose()

# 在技能菜单中选择具体技能
func _on_player_use_skill(skill: Skill):
	if current_state != State.PLAYER_INPUT: return
	var attacker = current_actor
	var target = _get_first_living_enemy()
	if not target:
		battle_ui.log_message("没有可选目标")
		return
	var dmg = attacker.stats.attack
	target.stats.take_damage(dmg, 1.0)
	_maybe_register_enemy_defeat(target)
	battle_ui.update_all_statuses()
	battle_ui.log_message("%s 使用技能 %s 攻击 %s！" % [attacker.name, skill.skill_name, target.name])
	check_for_win_lose()

func _on_player_choose_weapon(weapon: Item):
	if current_state != State.PLAYER_INPUT:
		return
	if not weapon or not weapon.equipment_props:
		return
	var props := weapon.equipment_props
	if props.slot != EquipmentComponent.EquipmentSlot.WEAPON:
		return
	if not props.hot_swappable:
		battle_ui.log_message("%s 无法在战斗中更换。" % weapon.item_name)
		return

	if not current_actor or not current_actor.character_data:
		battle_ui.log_message("无法切换武器：缺少角色数据")
		return

	var character_data: CharacterData = current_actor.character_data
	var current_weapon := _get_equipped_weapon(current_actor)
	if current_weapon == weapon:
		battle_ui.log_message("%s 已装备 %s" % [current_actor.name, weapon.item_name])
		return

	var char_id := String(character_data.character_id)
	var used_game_manager := false
	if not char_id.is_empty() and GameManager.all_characters.has(char_id):
		GameManager.equip_item_for_character(char_id, weapon)
		used_game_manager = true
	else:
		_swap_weapon_for_combatant_only(character_data, weapon)

	var equipment: Dictionary = GameManager.get_character_equipment(char_id, false) if used_game_manager else character_data.equipped_slots
	if character_data.stats:
		character_data.stats.update_equipment_bonuses(equipment)
	current_actor.stats.update_equipment_bonuses(equipment)
	battle_ui.update_all_statuses()
	battle_ui.log_message("%s 切换为 %s" % [current_actor.name, weapon.item_name])
	player_inventory = GameManager.player_current_inventory

func _get_equipped_weapon(combatant: Combatant) -> Item:
	if not combatant or not combatant.character_data:
		return null
	var equipment: Dictionary = combatant.character_data.equipped_slots if combatant.character_data.equipped_slots else {}
	if equipment.has(EquipmentComponent.EquipmentSlot.WEAPON):
		var weapon = equipment[EquipmentComponent.EquipmentSlot.WEAPON]
		if weapon is Item:
			return weapon
	return null

func _swap_weapon_for_combatant_only(character_data: CharacterData, new_weapon: Item) -> void:
	if not character_data or not new_weapon:
		return
	var slot_enum = EquipmentComponent.EquipmentSlot.WEAPON
	var equipment: Dictionary = character_data.equipped_slots if character_data.equipped_slots else {}
	var previous_weapon: Item = null
	if equipment.has(slot_enum):
		previous_weapon = equipment[slot_enum]
	GameManager.remove_item(new_weapon, 1)
	equipment[slot_enum] = new_weapon
	if previous_weapon:
		GameManager.add_item(previous_weapon, 1)
	character_data.equipped_slots = equipment
