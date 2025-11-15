# scripts/StatusScreen.gd
# 控制状态、装备和背包界面的显示与数据刷新
class_name StatusScreen extends CanvasLayer

# --- 节点引用 ---
@onready var main_panel: PanelContainer = $MainPanel
@onready var stats_grid: GridContainer = $MainPanel/MarginContainer/HBoxContainer/LeftColumn/StatsPanel/VBoxContainer/StatsGrid
@onready var equipment_grid: GridContainer = $MainPanel/MarginContainer/HBoxContainer/LeftColumn/EquipmentPanel/VBoxContainer/EquipmentGrid
@onready var inventory_grid: GridContainer = $MainPanel/MarginContainer/HBoxContainer/RightColumn/InventoryGrid

func _ready():
	# 游戏开始时默认隐藏
	hide()

# Godot 内置函数，用于处理未被其他节点消耗的输入事件
func _unhandled_input(event: InputEvent):
	# 检查玩家是否按下了我们定义的 "toggle_inventory" 键
	if event.is_action_pressed("exit"):
		if visible:
			hide()
			get_tree().paused = false
	if event.is_action_pressed("toggle_inventory"):
		# 如果界面可见，就隐藏它；如果隐藏，就显示它
		if visible:
			hide()
			get_tree().paused = false
		else:
			show()
			get_tree().paused = true
			# 每次显示时都刷新数据
			refresh_data()

# --- 核心交互逻辑 ---

func _on_inventory_item_clicked(item: Item):
	if item.equipment_props:
		# 如果点击的是装备，就调用 GameManager 的装备函数
		InventoryManager.equip_item(item)
		# 刷新整个界面
		refresh_data()
	elif item.consumable_props:
		# (未来) 可以在这里实现非战斗状态吃东西的功能
		print("你点击了食物: ", item.item_name)

func _on_equipment_slot_clicked(slot: EquipmentComponent.EquipmentSlot):
	# 调用 GameManager 的卸下装备函数
	InventoryManager.unequip_item(slot)
	# 刷新整个界面
	refresh_data()

# --- 核心刷新函数 ---
func refresh_data():
	# 从 GameManager 获取最新的玩家数据
	var stats = GameManager.player_current_stats
	var equipment = GameManager.player_current_equipment
	var inventory = GameManager.player_current_inventory
	
	# 调用各自的更新函数
	update_stats(stats)
	update_equipment(equipment)
	update_inventory(inventory)

# --- 数据更新辅助函数 ---

func update_stats(stats: CharacterStats):
	# 1. 清空旧的属性条目
	for child in stats_grid.get_children():
		child.queue_free()
	
	# 2. 动态创建并添加新的属性条目
	add_stat_entry("最大生命", stats.max_health,stats.equipment_bonuses.max_health)
	add_stat_entry("当前生命", stats.current_health,0)
	add_stat_entry("最大饱食度", stats.max_satiety,stats.equipment_bonuses.max_satiety)
	add_stat_entry("当前饱食度", stats.current_satiety,0)
	add_stat_entry("最大魔力", stats.max_mana,stats.equipment_bonuses.max_mana)
	add_stat_entry("当前魔力", stats.current_mana,0)
	add_stat_entry("攻击力", stats.attack,stats.equipment_bonuses.attack)
	add_stat_entry("防御力", stats.defense,stats.equipment_bonuses.defense)
	add_stat_entry("基础速度", stats.base_speed,stats.equipment_bonuses.base_speed)

func update_equipment(equipment: Dictionary):
	# 1. 清空旧的UI元素
	for child in equipment_grid.get_children():
		child.queue_free()
	
	# 2. 遍历所有可能的装备槽位，动态创建UI
	for slot_enum_value in EquipmentComponent.EquipmentSlot.values():
		var slot_name = EquipmentComponent.EquipmentSlot.keys()[slot_enum_value]
		var equipment_item = equipment.get(slot_enum_value)
		
		var name_label = Label.new()
		name_label.text = slot_name
		
		var slot_panel = PanelContainer.new()
		slot_panel.custom_minimum_size = Vector2(100, 30)
		
		# BUG 修复：将添加按钮和连接信号的逻辑移到这里
		# 这样每次创建新的装备槽时，都会为它赋予“点击卸下”的功能。
		var button = Button.new()
		button.flat = true # 让按钮透明
		button.mouse_filter = Control.MOUSE_FILTER_PASS # 让按钮可以被点击，但鼠标事件能穿透它
		button.pressed.connect(_on_equipment_slot_clicked.bind(slot_enum_value))
		slot_panel.add_child(button)
		
		if equipment_item:
			var item_label = Label.new()
			item_label.text = equipment_item.item_name
			item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			item_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			# 将 item_label 添加到 panel，而不是 button，确保它在按钮之上
			slot_panel.add_child(item_label)
		
		equipment_grid.add_child(name_label)
		equipment_grid.add_child(slot_panel)

func update_inventory(inventory: Array):
	for child in inventory_grid.get_children():
		child.queue_free()
		
	for slot in inventory:
		var item = slot.item
		var quantity = slot.quantity
		var button = Button.new()
		button.text = "%s x%d" % [item.item_name, quantity]
		
		# 在这里连接按钮信号，实现点击装备或使用道具的功能
		button.pressed.connect(_on_inventory_item_clicked.bind(item))
		inventory_grid.add_child(button)

# --- UI 创建辅助函数 ---

func add_stat_entry(stat_name: String, total_value: int, bonus_value: int):
	var name_label = Label.new()
	name_label.text = stat_name
	
	var value_label = Label.new()
	
	if bonus_value > 0:
		var base_value = total_value - bonus_value
		value_label.text = "%d (%d + %d)" % [total_value, base_value, bonus_value]
		value_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		value_label.text = str(total_value)
	
	stats_grid.add_child(name_label)
	stats_grid.add_child(value_label)

func add_equipment_entry(slot_name: String, equipment_item: Item):
	var name_label = Label.new()
	name_label.text = slot_name
	
	var slot_panel = PanelContainer.new()
	# 给装备槽一个最小尺寸，防止它太小
	slot_panel.custom_minimum_size = Vector2(100, 30)
	
	if equipment_item:
		var item_label = Label.new()
		item_label.text = equipment_item.item_name
		item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot_panel.add_child(item_label)
	
	equipment_grid.add_child(name_label)
	equipment_grid.add_child(slot_panel)
