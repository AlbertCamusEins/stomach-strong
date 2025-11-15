extends CanvasLayer

signal request_inventory_sync

@export var recipes: Array[CraftingRecipe] = []
@export var default_placeholder: Texture2D

const HIGHLIGHT_ALPHA_IDLE := 1.0
const HIGHLIGHT_ALPHA_GHOST := 0.5
const MENU_SLOT_CRAFT_BUTTON := -1000

@onready var panel_container: PanelContainer = $PanelContainer
@onready var forge_section: HBoxContainer = $"PanelContainer/VBoxContainer/HBoxContainer"
@onready var forge_grid: GridContainer = $"PanelContainer/VBoxContainer/HBoxContainer/ForgeGrid"
@onready var portrait_panel: PanelContainer = $"PanelContainer/VBoxContainer/HBoxContainer/PortraitContainer/PortraitPanel"
@onready var craft_button: Button = $"PanelContainer/VBoxContainer/HBoxContainer/PortraitContainer/CraftButton"
@onready var inventory_section: VBoxContainer = $"PanelContainer/VBoxContainer/VBoxContainer"
@onready var inventory_grid: GridContainer = $"PanelContainer/VBoxContainer/VBoxContainer/InventoryGrid"

var inventory_buttons: Array[Button] = []
var inventory_slots: Array[InventorySlot] = []
var forge_buttons: Array[Button] = []
var forge_slots: Array[Dictionary] = []

var reserved_counts: Dictionary = {}
var crafted_counts: Dictionary = {}

var highlight_panel: Panel
var highlight_icon: TextureRect
var highlight_label: Label

var menu_slot: int = -1
var inventory_cursor: int = -1
var forge_cursor: int = -1

var is_forging: bool = false
var pending_slot: InventorySlot = null
var pending_item: Item = null
var pending_source_index: int = -1
var last_inventory_index: int = -1

func _ready() -> void:
	hide()
	process_mode = PROCESS_MODE_ALWAYS
	set_process_unhandled_input(true)
	_init_forge_buttons()
	_init_highlight_panel()
	craft_button.pressed.connect(_on_craft_button_pressed)

func open_menu() -> void:
	if visible:
		return
	show()
	get_tree().paused = true
	_reset_menu_state()
	_refresh_forge_display()
	_refresh_inventory_display()
	_focus_inventory(0)

func close_menu() -> void:
	hide()
	get_tree().paused = false
	_cancel_pending_selection()
	_clear_forge_slots(true)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_crafting_menu"):
		if visible:
			close_menu()
		else:
			open_menu()
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	if event.is_action_pressed("exit") or event.is_action_pressed("ui_cancel"):
		if _try_handle_cancel():
			return
		close_menu()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept"):
		_handle_accept()
		return
	if event.is_action_pressed("ui_left"):
		_move_selection(Vector2.LEFT)
	elif event.is_action_pressed("ui_right"):
		_move_selection(Vector2.RIGHT)
	elif event.is_action_pressed("ui_up"):
		_move_selection(Vector2.UP)
	elif event.is_action_pressed("ui_down"):
		_move_selection(Vector2.DOWN)

func _init_forge_buttons() -> void:
	forge_buttons.clear()
	for child in forge_grid.get_children():
		if child is Button:
			var index: int = forge_buttons.size()
			var button := child as Button
			button.text = ""
			button.icon = null
			button.pressed.connect(func(): _on_forge_slot_pressed(index))
			forge_buttons.append(button)
	forge_slots.resize(forge_buttons.size())
	for i in forge_slots.size():
		forge_slots[i] = {}

func _init_highlight_panel() -> void:
	highlight_panel = Panel.new()
	highlight_panel.visible = false
	highlight_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	highlight_panel.z_index = 99
	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	highlight_panel.add_child(center)
	highlight_icon = TextureRect.new()
	highlight_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	highlight_icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	highlight_icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	highlight_icon.visible = false
	center.add_child(highlight_icon)
	highlight_label = Label.new()
	highlight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	highlight_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	highlight_label.visible = false
	center.add_child(highlight_label)
	inventory_section.add_child(highlight_panel)

func _reset_menu_state() -> void:
	is_forging = false
	pending_slot = null
	pending_item = null
	pending_source_index = -1
	menu_slot = -1
	inventory_cursor = -1
	forge_cursor = -1
	last_inventory_index = -1
	highlight_panel.visible = false
	highlight_icon.visible = false
	highlight_label.visible = false

func _refresh_inventory_display() -> void:
	inventory_buttons.clear()
	inventory_slots.clear()
	for child in inventory_grid.get_children():
		child.queue_free()
	var still_valid_reservations: Dictionary = {}
	for slot_index in GameManager.player_current_inventory.size():
		var slot: InventorySlot = GameManager.player_current_inventory[slot_index]
		if not slot or not slot.item:
			continue
		inventory_slots.append(slot)
		var button := Button.new()
		var reserved_amount: int = reserved_counts.get(slot, 0)
		var available: int = max(0, slot.quantity - reserved_amount)
		button.text = "%s x%d" % [slot.item.item_name, available]
		button.icon = slot.item.icon
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = slot.item.description
		button.disabled = available <= 0 and not (is_forging and pending_slot == slot)
		button.pressed.connect(func(): _on_inventory_slot_pressed(slot_index))
		button.mouse_entered.connect(func(): _focus_inventory(slot_index))
		button.modulate = Color(1, 1, 1, 0.5) if (reserved_amount > 0 or (is_forging and slot == pending_slot)) else Color(1, 1, 1, 1)
		inventory_grid.add_child(button)
		inventory_buttons.append(button)
		if reserved_amount > 0:
			still_valid_reservations[slot] = reserved_amount
	reserved_counts = still_valid_reservations
	if pending_slot and not reserved_counts.has(pending_slot):
		if not GameManager.player_current_inventory.has(pending_slot):
			_cancel_pending_selection()

func _refresh_forge_display() -> void:
	_update_forge_display()

func _update_forge_display() -> void:
	for index in forge_slots.size():
		_update_forge_button(index)

func _update_forge_button(index: int) -> void:
	var button: Button = forge_buttons[index]
	var data: Dictionary = forge_slots[index]
	if data and data.has("item"):
		var item: Item = data["item"]
		button.icon = item.icon
		#button.text = item.item_name
	else:
		button.icon = null
		button.text = ""

func _focus_inventory(index: int) -> void:
	if inventory_buttons.is_empty():
		return
	var clamped_index: int = clamp(index, 0, inventory_buttons.size() - 1)
	inventory_cursor = clamped_index
	last_inventory_index = clamped_index
	menu_slot = clamped_index
	_update_highlight(false)

func _focus_forge(index: int) -> void:
	if forge_buttons.is_empty():
		return
	var clamped_index: int = clamp(index, 0, forge_buttons.size() - 1)
	forge_cursor = clamped_index
	menu_slot = -1 - clamped_index
	_update_highlight(true)

func _focus_craft_button() -> void:
	menu_slot = MENU_SLOT_CRAFT_BUTTON
	_update_highlight(false)

func _update_highlight(force_forge: bool) -> void:
	var button: Button = null
	if menu_slot == MENU_SLOT_CRAFT_BUTTON:
		craft_button.button_pressed = true
		var craft_parent := craft_button.get_parent()
		var target_control: Control = craft_parent if craft_parent is Control else craft_button
		_reparent_highlight(target_control)
		highlight_panel.visible = true
		highlight_panel.global_position = craft_button.global_position
		highlight_panel.size = craft_button.size
		highlight_icon.visible = false
		highlight_label.visible = false
		return
	craft_button.button_pressed = false
	var targeting_forge: bool = force_forge or menu_slot < 0
	if targeting_forge:
		var idx: int = _menu_slot_to_forge_index(menu_slot)
		if idx < 0 or idx >= forge_buttons.size():
			highlight_panel.visible = false
			return
		_reparent_highlight(forge_section)
		button = forge_buttons[idx]
	else:
		if menu_slot < 0 or menu_slot >= inventory_buttons.size():
			highlight_panel.visible = false
			return
		_reparent_highlight(inventory_section)
		button = inventory_buttons[menu_slot]
	if button == null:
		highlight_panel.visible = false
		return
	highlight_panel.visible = true
	highlight_panel.global_position = button.global_position
	highlight_panel.size = button.size
	button.button_pressed = true
	if is_forging and pending_item:
		highlight_icon.texture = pending_item.icon
		highlight_icon.modulate = Color(1, 1, 1, HIGHLIGHT_ALPHA_GHOST)
		highlight_icon.visible = true
		highlight_label.text = pending_item.item_name
		highlight_label.modulate = Color(1, 1, 1, HIGHLIGHT_ALPHA_GHOST)
		highlight_label.visible = true
	else:
		highlight_icon.visible = false
		highlight_label.visible = false

func _reparent_highlight(target: Control) -> void:
	if not target:
		return
	if highlight_panel.get_parent() == target:
		return
	var parent: Node = highlight_panel.get_parent()
	if parent:
		parent.remove_child(highlight_panel)
	target.add_child(highlight_panel)

func _on_inventory_slot_pressed(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= GameManager.player_current_inventory.size():
		return
	var slot: InventorySlot = GameManager.player_current_inventory[slot_index]
	if not slot or not slot.item:
		return
	var available: int = _get_available_quantity(slot)
	if available <= 0 and not (is_forging and pending_slot == slot):
		return
	pending_slot = slot
	pending_item = slot.item
	pending_source_index = slot_index
	is_forging = true
	last_inventory_index = slot_index
	var dest_index: int = _find_next_empty_forge_slot()
	if dest_index == -1:
		dest_index = 0
	_focus_forge(dest_index)
	_refresh_inventory_display()

func _on_forge_slot_pressed(index: int) -> void:
	if index < 0 or index >= forge_slots.size():
		return
	if is_forging and pending_item:
		_commit_pending_to_slot(index)
	else:
		_focus_forge(index)

func _commit_pending_to_slot(index: int) -> void:
	if not pending_slot or not pending_item:
		return
	var available: int = _get_available_quantity(pending_slot)
	if available <= 0:
		_cancel_pending_selection()
		return
	if forge_slots[index] and not forge_slots[index].is_empty():
		_return_forge_slot(index, false)
	var entry: Dictionary = {
		"item": pending_item,
		"source_slot": pending_slot,
		"source_index": pending_source_index
	}
	forge_slots[index] = entry
	var reserved_amount: int = reserved_counts.get(pending_slot, 0)
	reserved_counts[pending_slot] = reserved_amount + 1
	_update_forge_button(index)
	_refresh_inventory_display()
	var next_index: int = _find_next_empty_forge_slot()
	if next_index == -1 or _get_available_quantity(pending_slot) <= 0:
		is_forging = false
		pending_item = null
		pending_slot = null
		pending_source_index = -1
		_focus_forge(index)
	else:
		_focus_forge(next_index)

func _return_forge_slot(index: int, refresh_inventory: bool = true) -> void:
	var data: Dictionary = forge_slots[index]
	if data.is_empty():
		return
	var slot: InventorySlot = data["source_slot"]
	var reserved_amount: int = reserved_counts.get(slot, 0)
	reserved_counts[slot] = max(0, reserved_amount - 1)
	if reserved_counts[slot] == 0:
		reserved_counts.erase(slot)
	forge_slots[index] = {}
	_update_forge_button(index)
	if refresh_inventory:
		_refresh_inventory_display()

func _clear_forge_slots(refresh_inventory: bool) -> void:
	for i in forge_slots.size():
		if forge_slots[i] and not forge_slots[i].is_empty():
			_return_forge_slot(i, false)
		forge_slots[i] = {}
	_update_forge_display()
	if refresh_inventory:
		_refresh_inventory_display()

func _find_next_empty_forge_slot() -> int:
	for i in forge_slots.size():
		if forge_slots[i].is_empty():
			return i
	return -1

func _get_available_quantity(slot: InventorySlot) -> int:
	if slot == null:
		return 0
	var reserved_amount: int = reserved_counts.get(slot, 0)
	return max(0, slot.quantity - reserved_amount)

func _handle_accept() -> void:
	if menu_slot == MENU_SLOT_CRAFT_BUTTON:
		_on_craft_button_pressed()
		return
	if menu_slot >= 0:
		_on_inventory_slot_pressed(menu_slot)
	else:
		var index: int = _menu_slot_to_forge_index(menu_slot)
		if index >= 0:
			if is_forging and pending_item:
				_commit_pending_to_slot(index)
			elif forge_slots[index] and not forge_slots[index].is_empty():
				_return_forge_slot(index)

func _try_handle_cancel() -> bool:
	if is_forging:
		_cancel_pending_selection()
		return true
	if menu_slot < 0:
		var index: int = _menu_slot_to_forge_index(menu_slot)
		if index >= 0 and forge_slots[index] and not forge_slots[index].is_empty():
			_return_forge_slot(index)
			return true
	return false

func _cancel_pending_selection() -> void:
	is_forging = false
	pending_slot = null
	pending_item = null
	pending_source_index = -1
	highlight_icon.visible = false
	highlight_label.visible = false
	if last_inventory_index >= 0:
		_focus_inventory(last_inventory_index)
	_refresh_inventory_display()

func _move_selection(direction: Vector2) -> void:
	if menu_slot == MENU_SLOT_CRAFT_BUTTON:
		match direction:
			Vector2.UP, Vector2.LEFT:
				if forge_buttons.is_empty():
					_focus_inventory(max(last_inventory_index, 0))
				else:
					_focus_forge(max(forge_cursor, 0))
			Vector2.DOWN:
				_focus_inventory(max(last_inventory_index, 0))
			_:
				pass
		return
	if menu_slot < 0:
		_move_forge_cursor(direction)
	else:
		if direction == Vector2.UP:
			if forge_buttons.is_empty():
				return
			_focus_forge(max(forge_cursor, 0))
			return
		_move_inventory_cursor(direction)

func _move_inventory_cursor(direction: Vector2) -> void:
	if inventory_buttons.is_empty():
		return
	var columns: int = max(1, inventory_grid.columns)
	if inventory_cursor < 0:
		inventory_cursor = 0
	match direction:
		Vector2.LEFT:
			inventory_cursor = max(0, inventory_cursor - 1)
		Vector2.RIGHT:
			inventory_cursor = min(inventory_buttons.size() - 1, inventory_cursor + 1)
		Vector2.UP:
			inventory_cursor = max(0, inventory_cursor - columns)
		Vector2.DOWN:
			inventory_cursor = min(inventory_buttons.size() - 1, inventory_cursor + columns)
	last_inventory_index = inventory_cursor
	_focus_inventory(inventory_cursor)

func _move_forge_cursor(direction: Vector2) -> void:
	if forge_buttons.is_empty():
		return
	if forge_cursor < 0:
		forge_cursor = 0
	var columns: int = max(1, forge_grid.columns)
	match direction:
		Vector2.LEFT:
			forge_cursor = max(0, forge_cursor - 1)
		Vector2.RIGHT:
			if (forge_cursor % columns) == columns - 1 or forge_cursor == forge_buttons.size() - 1:
				_focus_craft_button()
				return
			forge_cursor = min(forge_buttons.size() - 1, forge_cursor + 1)
		Vector2.UP:
			forge_cursor = max(0, forge_cursor - columns)
		Vector2.DOWN:
			var next_index: int = forge_cursor + columns
			if next_index >= forge_buttons.size():
				_focus_craft_button()
				return
			forge_cursor = next_index
	_focus_forge(forge_cursor)

func _menu_slot_to_forge_index(value: int) -> int:
	if value == MENU_SLOT_CRAFT_BUTTON:
		return -1
	return abs(value) - 1

func _on_craft_button_pressed() -> void:
	var recipe: CraftingRecipe = _match_current_recipe()
	if recipe:
		_consume_materials()
		_grant_output(recipe)
		_clear_forge_slots(true)
	else:
		_clear_forge_slots(true)

func _match_current_recipe() -> CraftingRecipe:
	var occupied_slots: Array[int] = []
	var current_map: Dictionary = {}
	for i in forge_slots.size():
		var data: Dictionary = forge_slots[i]
		if data and data.has("item"):
			occupied_slots.append(i)
			current_map[i] = data["item"]
	for recipe in recipes:
		if not recipe:
			continue
		var pattern: Array[IngredientSlot] = recipe.pattern
		if pattern.size() != occupied_slots.size():
			continue
		var matches: bool = true
		for requirement in pattern:
			if requirement == null:
				matches = false
				break
			var slot_index: int = requirement.slot_index
			var required_item: Item = requirement.item
			if slot_index < 0 or not current_map.has(slot_index):
				matches = false
				break
			var current_item: Item = current_map[slot_index]
			if not current_item or not required_item or current_item.item_name != required_item.item_name:
				matches = false
				break
		if matches:
			return recipe
	return null

func _consume_materials() -> void:
	for i in forge_slots.size():
		var data: Dictionary = forge_slots[i]
		if not data or not data.has("item"):
			continue
		var item: Item = data["item"]
		var slot: InventorySlot = data["source_slot"]
		var reserved_amount: int = reserved_counts.get(slot, 0)
		reserved_counts[slot] = max(0, reserved_amount - 1)
		if reserved_counts[slot] == 0:
			reserved_counts.erase(slot)
		GameManager.remove_item(item, 1)
	QuickbarManager.notify_inventory_changed()
	emit_signal("request_inventory_sync")
	_refresh_inventory_display()

func _grant_output(recipe: CraftingRecipe) -> void:
	if not recipe:
		_update_portrait(null)
		return
	var output_item: Item = recipe.output_item
	if output_item:
		var quantity: int = max(1, recipe.output_quantity)
		GameManager.add_item(output_item, quantity)
		QuickbarManager.notify_inventory_changed()
		emit_signal("request_inventory_sync")
		_update_portrait(output_item)
	else:
		_update_portrait(null)

func _update_portrait(item: Item) -> void:
	_clear_portrait_contents()
	var texture_rect := TextureRect.new()
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texture_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if item:
		var key: String = item.item_name
		var craft_times: int = crafted_counts.get(key, 0) + 1
		crafted_counts[key] = craft_times
		if craft_times >= 2 and item.icon:
			texture_rect.texture = item.icon
		else:
			texture_rect.texture = default_placeholder
	else:
		texture_rect.texture = default_placeholder
	portrait_panel.add_child(texture_rect)

func _clear_portrait_contents() -> void:
	for child in portrait_panel.get_children():
		child.queue_free()
