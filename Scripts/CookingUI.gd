# scripts/CookingUI.gd
extends CanvasLayer

# --- 节点引用 ---
@onready var recipe_list_container = $MainPanel/MarginContainer/HBoxContainer/RecipeListPanel
@onready var recipe_name_label = $MainPanel/MarginContainer/HBoxContainer/DetailPanel/RecipeName
@onready var recipe_description_label = $MainPanel/MarginContainer/HBoxContainer/DetailPanel/RecipeDescription
@onready var ingredients_grid = $MainPanel/MarginContainer/HBoxContainer/DetailPanel/RequirementsPanel/VBoxContainer/IngredientsGrid
@onready var technique_label = $MainPanel/MarginContainer/HBoxContainer/DetailPanel/RequirementsPanel/VBoxContainer/TechniqueLabel
@onready var cookware_label = $MainPanel/MarginContainer/HBoxContainer/DetailPanel/RequirementsPanel/VBoxContainer/CookwareLabel
@onready var output_label = $MainPanel/MarginContainer/HBoxContainer/DetailPanel/OutputPanel/HBoxContainer/OutputLabel
@onready var cook_button = $MainPanel/MarginContainer/HBoxContainer/DetailPanel/CookButton
@onready var close_button = $MainPanel/MarginContainer/HBoxContainer/DetailPanel/CloseButton
@onready var requirements_panel = $MainPanel/MarginContainer/HBoxContainer/DetailPanel/RequirementsPanel

var current_spot_cookware: CookwareComponent # 存储当前炊点提供的厨具
var selected_recipe: Recipe # 存储当前选中的菜谱

func _ready():
	# 确保UI在游戏开始时是隐藏的
	hide()
	# 连接按钮信号
	cook_button.pressed.connect(_on_cook_button_pressed)
	close_button.pressed.connect(_on_close_button_pressed)
	# 让UI可以在游戏暂停时继续处理输入
	process_mode = Node.PROCESS_MODE_ALWAYS

func open_cooking_menu(spot_cookware: CookwareComponent):
	# 外部调用此函数来打开界面
	current_spot_cookware = spot_cookware
	get_tree().paused = true
	populate_recipe_list()
	clear_details()
	show()

func _on_close_button_pressed():
	get_tree().paused = false
	hide()

func populate_recipe_list():
	# 清空旧列表
	for child in recipe_list_container.get_children():
		child.queue_free()
	
	# 根据玩家已知的菜谱创建新按钮
	for recipe in GameManager.player_known_recipes:
		var button = Button.new()
		button.text = recipe.recipe_name
		# 使用 lambda 函数连接信号，这样可以方便地传递 recipe 参数
		button.pressed.connect(func(): _on_recipe_selected(recipe))
		recipe_list_container.add_child(button)

func _on_recipe_selected(recipe: Recipe):
	selected_recipe = recipe
	update_recipe_details()

func update_recipe_details():
	if not selected_recipe:
		clear_details()
		return
		
	# 更新基础信息
	ingredients_grid.get_parent().show()
	recipe_name_label.text = selected_recipe.recipe_name
	recipe_description_label.text = selected_recipe.description
	output_label.text = "%s x%d" % [selected_recipe.output_item.item_name, selected_recipe.output_quantity]
	
	# 检查所有条件
	var can_cook = true
	
	# 1. 检查并显示食材
	for child in ingredients_grid.get_children():
		child.queue_free()
	
	for req in selected_recipe.ingredients:
		var player_count = InventoryManager.count_item(req.item)
		var has_enough = player_count >= req.quantity
		
		var name_label = Label.new()
		name_label.text = req.item.item_name
		
		var count_label = Label.new()
		count_label.text = "%d / %d" % [player_count, req.quantity]
		count_label.modulate = Color.GREEN if has_enough else Color.RED
		
		ingredients_grid.add_child(name_label)
		ingredients_grid.add_child(count_label)
		
		if not has_enough: can_cook = false
	
	# 2. 检查厨艺
	var has_technique = false
	if selected_recipe.required_technique:
		technique_label.text = selected_recipe.required_technique.technique_name
		has_technique = GameManager.player_known_techniques.has(selected_recipe.required_technique)
		technique_label.modulate = Color.GREEN if has_technique else Color.RED
	else:
		technique_label.text = "[无需特殊厨艺]"
		has_technique = true

	if not has_technique: can_cook = false

	# 3. 检查厨具
	var has_cookware = false
	var required_cookware_name = ""
	if selected_recipe.required_cookware:
		required_cookware_name = selected_recipe.required_cookware.item_name
		if current_spot_cookware and current_spot_cookware.item_name == required_cookware_name:
			has_cookware = true
		else:
			for slot in GameManager.player_current_inventory:
				var item = slot.item
				if item.cookware_props and item.item_name == required_cookware_name:
					has_cookware = true
					break
	else:
		required_cookware_name = "[无需特殊厨具]"
		has_cookware = true

	cookware_label.text = required_cookware_name
	cookware_label.modulate = Color.GREEN if has_cookware else Color.RED
	if not has_cookware: can_cook = false
	
	cook_button.disabled = not can_cook

func clear_details():
	# 清空右侧详情面板
	recipe_name_label.text = "请选择一个菜谱"
	recipe_description_label.text = ""
	ingredients_grid.get_parent().hide() # 暂时隐藏
	technique_label.text = ""
	cookware_label.text = ""

func _on_cook_button_pressed():
	if not selected_recipe or cook_button.disabled:
		return
		
	# 消耗食材
	for req in selected_recipe.ingredients:
		InventoryManager.remove_item(req.item, req.quantity)
		
	# 添加产出
	InventoryManager.add_item(selected_recipe.output_item, selected_recipe.output_quantity)
	
	print("制作成功: %s x%d" % [selected_recipe.output_item.item_name, selected_recipe.output_quantity])
	
	# 刷新UI，这样玩家可以立刻看到材料数量的变化，并决定是否能再做一份
	update_recipe_details()
