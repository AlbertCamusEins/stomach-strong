# scripts/GameManager.gd
# 升级版：负责管理持久化的玩家数据和游戏流程。
extends Node

# --- 场景路径 ---
const WORLD_MAP_SCENE = "res://Scenes/WorldMap.tscn"
const BATTLE_SCENE = "res://Scenes/battle.tscn"
const SAVE_FILE_PATH = "user://savegame.tres"
const PERSISTENT_SCENES = [WORLD_MAP_SCENE]

# --- 资源引用 (用于初始化) ---
# 在 Godot 编辑器的 Autoload 设置中，为 GameManager 添加这些属性。
@export var player_stats_resource: CharacterStats
@export var initial_player_data: CharacterData
@export var initial_party: Array[CharacterData]
@export var initial_player_inventory: Array[InventorySlot]
@export var initial_recipes: Array[Recipe]
@export var initial_techniques: Array[CookingTechnique]
@export var quickbar_slots: Array

# --- 实时游戏数据 ---
# 这两个变量将贯穿整个游戏，保存玩家的当前状态。
var player_current_stats: CharacterStats
var current_player_data: CharacterData
# [核心修改] 背包现在是一个字典数组，每个字典代表一个物品槽
# 格式: [ { "item": Item, "quantity": int }, ... ]
var player_current_inventory: Array[InventorySlot] = []
var equipment_by_character: Dictionary = {}
var player_current_equipment: Dictionary:
	get:
		var id = _get_current_player_id()
		if id.is_empty():
			return {}
		return equipment_by_character.get(id, {})
var player_known_recipes: Array[Recipe]
var player_known_techniques: Array[CookingTechnique]

var current_scene: Node = null
var current_scene_path: String = ""
var persistent_scene_cache: Dictionary = {}
var player_node: Node = null

# --- [新增] 队伍管理变量 (添加到“实时游戏数据”部分) ---
# 存储玩家拥有的所有角色
var all_characters: Dictionary = {} # Key: character_id, Value: CharacterData
# 存储当前战斗编队的 character_id
var combat_party: Array[String] = []
# 存储当前后勤编队的 character_id
var reserve_party: Array[String] = []

signal quest_progress_updated # 任务进度更新

# 属性计算函数
func calculate_total_stats(character_id: String = ""):
	var target_id = character_id
	if target_id.is_empty():
		target_id = _get_current_player_id()
	if target_id.is_empty():
		return
	var equipment = get_character_equipment(target_id, false)
	if player_current_stats and target_id == _get_current_player_id():
		player_current_stats.update_equipment_bonuses(equipment)
	if all_characters.has(target_id):
		var character_data: CharacterData = all_characters[target_id]
		if character_data and character_data.stats:
			character_data.stats.update_equipment_bonuses(equipment)


# --- [核心新增] 任务进度追踪 ---
func update_quest_progress(objective_type: QuestObjective.ObjectiveType, target, amount: int = 1):
	var needs_ui_refresh = false
	
	# 遍历所有正在进行的任务
	for quest in active_quests.values():
		# 遍历任务中的每一个目标
		for objective in quest.objectives:
			# 如果目标已经完成，就跳过
			if objective.is_complete: continue
			
			# 检查目标类型是否匹配
			if objective.type == objective_type:
				var target_matches = false
				# 根据不同类型，检查目标对象是否匹配
				match objective_type:
					QuestObjective.ObjectiveType.COLLECT:
						# 比较物品资源的路径，这是最可靠的方法
						if target is Item and target.item_name == objective.item_to_collect.item_name:
							target_matches = true
					QuestObjective.ObjectiveType.DEFEAT:
						if target is CharacterStats and target.resource_path == objective.enemy_to_defeat.resource_path:
							target_matches = true
					QuestObjective.ObjectiveType.TALK_TO:
						# 这里我们假设 target 是一个 NPC 的 ID (String)
						if typeof(target) == TYPE_STRING and target == objective.npc_id_to_talk:
							target_matches = true
				
				if target_matches:
					# 更新进度
					objective.current_progress = amount
					# 检查目标是否完成
					objective.check_completion()
					print("任务'%s'进度更新: %s (%d)" % [quest.quest_name, objective.description, objective.current_progress])
					needs_ui_refresh = true
	
	# 如果有任何任务的进度发生了变化，就通知UI刷新
	if needs_ui_refresh:
		emit_signal("quest_progress_updated")

# --- [新增] 任务管理变量 ---
# Key: quest_id (String), Value: Quest (Resource)
var active_quests: Dictionary = {}
# 存储已完成任务的 quest_id
var completed_quests: Array[String] = []
var dialogue_flags: Dictionary = {}

# --- [新增] 任务管理核心函数 ---

# 开始一个新任务
func start_quest(quest_resource: Quest):
	if not quest_resource: return
	
	var quest_id = quest_resource.quest_id
	# 检查任务是否已经开始或已经完成
	if active_quests.has(quest_id) or completed_quests.has(quest_id):
		print("任务 '%s' 已经开始或已完成，无法重复接取。" % quest_id)
		return
		
	# 复制一份任务资源，以防修改影响原始文件
	var new_quest = quest_resource.duplicate(true)
	new_quest.current_state = Quest.QuestState.IN_PROGRESS
	
	# 初始化任务目标的进度
	for objective in new_quest.objectives:
		objective.is_complete = false
		objective.current_progress = 0
	
	active_quests[quest_id] = new_quest
	print("已接取任务: %s" % new_quest.quest_name)
	# 任务接取后，立即检查一次当前背包是否满足条件
	for slot in player_current_inventory:
		if slot and slot.item:
			update_quest_progress(
				QuestObjective.ObjectiveType.COLLECT,
				slot.item,
				InventoryManager.count_item(slot.item)
			)

# 检查某个任务的状态
func get_quest_state(quest_id: String) -> Quest.QuestState:
	if completed_quests.has(quest_id):
		return Quest.QuestState.COMPLETED
	if active_quests.has(quest_id):
		return Quest.QuestState.IN_PROGRESS
	return Quest.QuestState.NOT_STARTED

func set_dialogue_flag(flag_name: String, value: bool = true) -> void:
	if flag_name.is_empty():
		return
	dialogue_flags[flag_name] = value

func get_dialogue_flag(flag_name: String) -> bool:
	if flag_name.is_empty():
		return false
	return dialogue_flags.get(flag_name, false)

func clear_dialogue_flag(flag_name: String) -> void:
	if dialogue_flags.has(flag_name):
		dialogue_flags.erase(flag_name)


# --- 存档读档 ---
func save_game():
	var save_data = SaveData.new()

	save_data.player_stats = player_current_stats
	save_data.player_inventory = player_current_inventory
	var current_equipment = get_character_equipment(_get_current_player_id(), false)
	if current_equipment:
		save_data.player_equipment = current_equipment.duplicate()
	else:
		save_data.player_equipment = {}

	var equipment_snapshot: Dictionary = {}
	for char_id in equipment_by_character.keys():
		var equipment: Dictionary = equipment_by_character[char_id]
		equipment_snapshot[char_id] = _clone_equipment_dict(equipment)
		_sync_character_equipped_slots(char_id, equipment)
	save_data.equipment_by_character = equipment_snapshot

	save_data.player_known_recipes = player_known_recipes
	save_data.player_known_techniques = player_known_techniques

	save_data.all_characters = all_characters
	save_data.combat_party = combat_party
	save_data.reserve_party = reserve_party

	save_data.active_quests = active_quests
	save_data.completed_quests = completed_quests
	save_data.dialogue_flags = dialogue_flags

	var error = ResourceSaver.save(save_data, SAVE_FILE_PATH)
	if error == OK:
		print("游戏保存成功！路径 ", SAVE_FILE_PATH)
	else:
		push_error("游戏保存失败！错误代码 %s" % error)


func load_game():
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		print("没有找到存档文件")
		return false

	var loaded_data = ResourceLoader.load(SAVE_FILE_PATH)
	if loaded_data is SaveData:
		player_current_stats = loaded_data.player_stats
		player_current_inventory.clear()
		for entry in loaded_data.player_inventory:
			if entry is InventorySlot:
				player_current_inventory.append(entry)
			elif entry is Item:
				var slot = InventorySlot.new()
				slot.item = entry
				slot.quantity = 1
				player_current_inventory.append(slot)

		equipment_by_character.clear()
		if loaded_data.equipment_by_character:
			for char_id in loaded_data.equipment_by_character.keys():
				var equipment_entry = loaded_data.equipment_by_character[char_id]
				if typeof(char_id) == TYPE_STRING and typeof(equipment_entry) == TYPE_DICTIONARY:
					equipment_by_character[char_id] = _clone_equipment_dict(equipment_entry)

		player_known_recipes.clear()
		for recipe in loaded_data.player_known_recipes:
			if recipe is Recipe:
				player_known_recipes.append(recipe)

		player_known_techniques.clear()
		for tech in loaded_data.player_known_techniques:
			if tech is CookingTechnique:
				player_known_techniques.append(tech)

		active_quests = loaded_data.active_quests if loaded_data.active_quests else {}
		completed_quests.clear()
		if loaded_data.completed_quests:
			for quest_id in loaded_data.completed_quests:
				if typeof(quest_id) == TYPE_STRING:
					completed_quests.append(quest_id)

		dialogue_flags = loaded_data.dialogue_flags if loaded_data.dialogue_flags else {}

		all_characters.clear()
		if loaded_data.all_characters:
			for char_id in loaded_data.all_characters.keys():
				var character_data = loaded_data.all_characters[char_id]
				if character_data is CharacterData:
					all_characters[char_id] = character_data
					if not equipment_by_character.has(char_id):
						equipment_by_character[char_id] = _clone_equipment_dict(character_data.equipped_slots)

		combat_party = loaded_data.combat_party.duplicate() if loaded_data.combat_party else []
		reserve_party = loaded_data.reserve_party.duplicate() if loaded_data.reserve_party else []

		var leader_id = ""
		if not combat_party.is_empty():
			leader_id = combat_party[0]
		elif current_player_data and not String(current_player_data.character_id).is_empty():
			leader_id = current_player_data.character_id
		elif not all_characters.is_empty():
			for char_id in all_characters.keys():
				leader_id = char_id
				break

		if not leader_id.is_empty() and all_characters.has(leader_id):
			current_player_data = all_characters[leader_id]

		if leader_id.is_empty():
			leader_id = _get_current_player_id()

		if leader_id.is_empty():
			for char_id in equipment_by_character.keys():
				leader_id = char_id
				if all_characters.has(char_id):
					current_player_data = all_characters[char_id]
				break

		if not leader_id.is_empty() and not equipment_by_character.has(leader_id) and loaded_data.player_equipment:
			equipment_by_character[leader_id] = _clone_equipment_dict(loaded_data.player_equipment)

		for char_id in equipment_by_character.keys():
			_sync_character_equipped_slots(char_id, equipment_by_character[char_id])
			calculate_total_stats(char_id)

		calculate_total_stats()
		print("游戏加载成功！")
		return true
	else:
		push_error("加载失败：存档文件已损坏或格式不正确！")
		return false


func has_save_file() -> bool:
	return FileAccess.file_exists(SAVE_FILE_PATH)

# --- 装备逻辑核心函数 ---

func _get_current_player_id() -> String:
	if current_player_data and not String(current_player_data.character_id).is_empty():
		return current_player_data.character_id
	return ""

func _clone_equipment_dict(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if not source:
		return result
	for key in source.keys():
		var item = source[key]
		if item is Item:
			result[key] = item
	return result

func get_character_equipment(character_id: String, create_if_missing: bool = true) -> Dictionary:
	if character_id.is_empty():
		return {}
	if not equipment_by_character.has(character_id) and create_if_missing:
		equipment_by_character[character_id] = {}
	return equipment_by_character.get(character_id, {})

func _sync_character_equipped_slots(character_id: String, equipment: Dictionary) -> void:
	if not all_characters.has(character_id):
		return
	var character_data: CharacterData = all_characters[character_id]
	if character_data:
		character_data.equipped_slots = _clone_equipment_dict(equipment)

func _register_character_equipment(character_data: CharacterData) -> void:
	if not character_data:
		return
	var character_id = String(character_data.character_id)
	if character_id.is_empty():
		return
	var snapshot = _clone_equipment_dict(character_data.equipped_slots)
	equipment_by_character[character_id] = snapshot
	_sync_character_equipped_slots(character_id, snapshot)
	calculate_total_stats(character_id)


# --- [新增] 队伍管理核心函数 ---

func add_player_data_to_all_characters(character_data: CharacterData):
	if not character_data.character_id or character_data.character_id.is_empty():
		push_error("该角色id无效")
		return

	if all_characters.has(character_data.character_id):
		push_warning("该角色id已存在")
		return

	all_characters[character_data.character_id] = character_data
	_register_character_equipment(character_data)
	print("将角色%s加入队伍" % character_data.character_name)


func add_character_to_roster(character: CharacterData):
	if not all_characters.has(character.character_id):
		all_characters[character.character_id] = character
		_register_character_equipment(character)
		reserve_party.append(character.character_id)


func move_character_to_combat(character_id: String):
	"""将角色从后勤移动到战斗编队"""
	if reserve_party.has(character_id):
		reserve_party.erase(character_id)
		combat_party.append(character_id)

func move_character_to_reserve(character_id: String):
	"""将角色从战斗移动到后勤编队"""
	if combat_party.has(character_id):
		combat_party.erase(character_id)
		reserve_party.append(character_id)

# --- 游戏流程函数 ---

func new_game():
	player_current_stats = player_stats_resource.duplicate(true)
	current_player_data = initial_player_data.duplicate(true)
	player_current_inventory.clear()
	for slot_data in initial_player_inventory:
		if slot_data and slot_data.item:
			InventoryManager.add_item(slot_data.item, slot_data.quantity)
	equipment_by_character.clear()

	player_known_recipes.clear()
	for recipe in initial_recipes:
		if recipe is Recipe:
			player_known_recipes.append(recipe)

	player_known_techniques.clear()
	for tech in initial_techniques:
		if tech is CookingTechnique:
			player_known_techniques.append(tech)

	active_quests.clear()
	completed_quests.clear()

	all_characters.clear()
	combat_party.clear()
	reserve_party.clear()

	if initial_party and initial_party.size() > 0:
		var first_valid: CharacterData = null
		for cd in initial_party:
			if cd and not String(cd.character_id).is_empty():
				var dup: CharacterData = cd.duplicate(true)
				all_characters[dup.character_id] = dup
				if first_valid == null:
					first_valid = dup
				if not combat_party.has(dup.character_id):
					combat_party.append(dup.character_id)
				_register_character_equipment(dup)
		if first_valid:
			current_player_data = first_valid
		else:
			add_player_data_to_all_characters(current_player_data)
			combat_party.append(current_player_data.character_id)
	else:
		add_player_data_to_all_characters(current_player_data)
		combat_party.append(current_player_data.character_id)

	calculate_total_stats()
	switch_to_scene(WORLD_MAP_SCENE)


func continue_game():
	if load_game():
		switch_to_scene(WORLD_MAP_SCENE)
	else:
		# 如果加载失败，可以选择退回主菜单或开始新游戏
		new_game()

func _ready():
	# 游戏启动时，只执行一次：复制初始数据作为玩家的实时数据。
	# duplicate(true) 会进行“深拷贝”，确保所有子资源也被复制。
	player_current_stats = player_stats_resource.duplicate(true)
	player_current_inventory = initial_player_inventory.duplicate(true)
	
	var root = get_tree().get_root()
	current_scene = root.get_child(root.get_child_count() - 1)

# --- 核心功能：切换场景 ---
func switch_to_scene(scene_path: String, battle_data: Dictionary = {}):
	current_scene_path = scene_path
	call_deferred("_deferred_switch_scene", scene_path, battle_data)

func _deferred_switch_scene(scene_path: String, battle_data: Dictionary):
	var root := get_tree().get_root()

	# 1. 如果当前场景需要保留，就缓存并先从场景树移除
	if is_instance_valid(current_scene):
		if PERSISTENT_SCENES.has(current_scene.scene_file_path):
			current_scene.visible = false
			current_scene.set_process(false)
			if current_scene.get_parent():
				current_scene.get_parent().remove_child(current_scene)
			persistent_scene_cache[current_scene.scene_file_path] = current_scene
		else:
			current_scene.queue_free()

	# 2. 复用已缓存的场景，否则重新实例化
	if persistent_scene_cache.has(scene_path):
		current_scene = persistent_scene_cache[scene_path]
		persistent_scene_cache.erase(scene_path)
	else:
		var next_scene_res := load(scene_path)
		current_scene = next_scene_res.instantiate()

	root.add_child(current_scene)
	current_scene.visible = true
	current_scene.set_process(true)

	# 3. 如有战斗数据，继续按原逻辑处理
	if scene_path == BATTLE_SCENE:
		current_scene.get_node("BattleManager").setup_battle(battle_data)


# --- 游戏流程函数 ---
# 开始和结束战斗（多人对战版）
func start_battle(encounter: Encounter):
	if not encounter or encounter.enemies.is_empty():
		print("错误：尝试开始一场没有敌人的战斗！")
		return
		
	save_game()
	
	# [核心修改] 我们现在传递两个关键信息：
	# 1. 我方战斗编队的所有角色ID
	# 2. 敌方队伍的所有角色数据
	var battle_data = {
		"player_party_ids": combat_party,
		"enemy_party_data": encounter.enemies
	}
	switch_to_scene(BATTLE_SCENE, battle_data)

func end_battle():
	print("战斗结束！返回大地图...")
	switch_to_scene(WORLD_MAP_SCENE)
	save_game() #战斗结束后存档
