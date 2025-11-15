extends Node

const SLOT_COUNT := 10
const WORLD_ITEM_SCENE := preload("res://Scenes/WorldItem.tscn")
const DROP_OFFSET := Vector2(0, 0)

signal quickbar_updated(slots: Array)          # 任意槽位变化时触发
signal slot_changed(index: int, slot: Dictionary)
signal item_consumed(index: int, item: Item)
signal item_equipped(index: int, item: Item)
signal item_unequipped(index: int, item: Item)
signal item_dropped(index: int, item: Item)
signal trap_requested(item: Item, context: Dictionary)

var slots: Array[Dictionary] = []

func _ready() -> void:
	slots.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		slots[i] = _empty_slot()

	if GameManager.quickbar_slots and GameManager.quickbar_slots is Array:
		load_from_data(GameManager.quickbar_slots)

	_refresh_quantities(false)

func add_from_inventory(item: Item, quantity: int = -1) -> bool:
	if not item:
		return false
	var amount := quantity if quantity >= 0 else InventoryManager.count_item(item)
	if amount <= 0:
		return false

	var index := _find_slot_by_item(item)
	if index == -1:
		index = _find_empty_slot()
	if index == -1:
		return false

	_set_slot(index, item, amount)
	return true

func assign_to_slot(index: int, item: Item, quantity: int = -1) -> void:
	if not _is_valid_index(index) or not item:
		return
	var amount := quantity if quantity >= 0 else InventoryManager.count_item(item)
	_set_slot(index, item, amount)

func remove_slot(index: int) -> void:
	if not _is_valid_index(index):
		return
	_clear_slot(index, true)

func handle_action(action: ItemActionMenu.Action, item: Item, context: Dictionary) -> void:
	var slot_index :int = context.get("slot_index", -1)
	match action:
		ItemActionMenu.Action.CONSUME:
			print("item consumed")
			_consume_item(slot_index, item)
		ItemActionMenu.Action.EQUIP:
			print("item equipped")
			_equip_item(slot_index, item)
		ItemActionMenu.Action.UNEQUIP:
			_unequip_item(slot_index, item)
		ItemActionMenu.Action.DROP:
			print("item dropped")
			_drop_item(slot_index, item)
		ItemActionMenu.Action.PLACE_TRAP:
			trap_requested.emit(item, context)
		_:
			pass

func notify_inventory_changed() -> void:
	_refresh_quantities()

func serialize() -> Array:
	var data: Array = []
	for slot in slots:
		if slot["item"]:
			data.append({
				"item": slot["item"],
				"quantity": slot["quantity"]
			})
		else:
			data.append({})
	return data

func load_from_data(data: Array) -> void:
	for i in SLOT_COUNT:
		if i >= data.size():
			slots[i] = _empty_slot()
			continue
		var entry = data[i]
		if entry is InventorySlot:
			slots[i] = {
				"item": entry.item,
				"quantity": entry.quantity
			}
		elif entry is Dictionary and entry.has("item"):
			slots[i] = {
				"item": entry.get("item"),
				"quantity": entry.get("quantity", 0)
			}
		elif entry is Item:
			slots[i] = {"item": entry, "quantity": InventoryManager.count_item(entry)}
		else:
			slots[i] = _empty_slot()
	_refresh_quantities(false)

func get_slots_snapshot() -> Array:
	return slots.duplicate(true)

func _consume_item(slot_index: int, item: Item) -> void:
	if not item or not item.consumable_props:
		return
	var character := GameManager.current_player_data
	if not character or not character.stats:
		return

	var stats := character.stats
	var props := item.consumable_props

	if props.health_change != 0:
		if props.health_change > 0:
			stats.heal(props.health_change)
		else:
			stats.take_damage(-props.health_change, 1.0)
	if props.mana_change != 0:
		stats.change_mana(props.mana_change)
	if props.satiety_change != 0:
		stats.change_satiety(props.satiety_change)

	if props.add_max_health != 0:
		stats.base_max_health += props.add_max_health
	if props.add_max_satiety != 0:
		stats.base_max_satiety += props.add_max_satiety
	if props.add_max_mana != 0:
		stats.base_max_mana += props.add_max_mana
	if props.add_attack != 0:
		stats.base_attack += props.add_attack
	if props.add_defense != 0:
		stats.base_defense += props.add_defense
	if props.add_base_speed != 0:
		stats.base_speed += props.add_base_speed

	GameManager.calculate_total_stats(character.character_id)
	stats.current_health = clampi(stats.current_health, 0, stats.max_health)
	stats.current_mana = clampi(stats.current_mana, 0, stats.max_mana)
	stats.current_satiety = clampi(stats.current_satiety, 0, stats.max_satiety)

	InventoryManager.remove_item(item, 1)
	item_consumed.emit(slot_index, item)
	_after_inventory_mutation(slot_index)

func _equip_item(slot_index: int, item: Item) -> void:
	if not item or not item.equipment_props:
		return
	InventoryManager.equip_item(item)
	item_equipped.emit(slot_index, item)
	_after_inventory_mutation(slot_index)

func _unequip_item(slot_index: int, item: Item) -> void:
	if not item or not item.equipment_props:
		return
	var character := GameManager.current_player_data
	if not character:
		return
	InventoryManager.unequip_item_for_character(character.character_id, item.equipment_props.slot)
	item_unequipped.emit(slot_index, item)
	_after_inventory_mutation(slot_index)

func _drop_item(slot_index: int, item: Item) -> void:
	if not item:
		return
	var drop_parent := _find_world_item_parent()
	if not drop_parent:
		push_warning("QuickbarManager: Unable to locate drop parent in current scene.")
		return

	var world_item := WORLD_ITEM_SCENE.instantiate() as WorldItem
	world_item.item = item.duplicate(true)
	drop_parent.add_child(world_item)
	world_item.global_position = _resolve_drop_position(drop_parent)

	InventoryManager.remove_item(item, 1)
	item_dropped.emit(slot_index, item)
	_after_inventory_mutation(slot_index)

func _find_world_item_parent() -> Node:
	if not is_instance_valid(GameManager.current_scene):
		return null
	var parent := GameManager.current_scene.get_node_or_null("Ysort/WorldItem")
	if parent:
		return parent
	return GameManager.current_scene

func _resolve_drop_position(parent: Node) -> Vector2:
	var tree := parent.get_tree()
	if tree:
		var player_nodes := tree.get_nodes_in_group("Player")
		for candidate in player_nodes:
			if candidate is CharacterBody2D:
				return candidate.global_position + DROP_OFFSET
		for candidate in player_nodes:
			if candidate is Node2D:
				return (candidate as Node2D).global_position + DROP_OFFSET
	if parent is Node2D:
		return (parent as Node2D).global_position
	return Vector2.ZERO

func _after_inventory_mutation(slot_index: int) -> void:
	_refresh_quantities(false)
	if _is_valid_index(slot_index):
		slot_changed.emit(slot_index, slots[slot_index])
	quickbar_updated.emit(get_slots_snapshot())

func _refresh_quantities(broadcast: bool = true) -> void:
	var changed := false
	for i in SLOT_COUNT:
		var slot := slots[i]
		if not slot["item"]:
			continue
		var count := InventoryManager.count_item(slot["item"])
		if count <= 0:
			slots[i] = _empty_slot()
			slot_changed.emit(i, slots[i])
			changed = true
		elif slot["quantity"] != count:
			slot["quantity"] = count
			slots[i] = slot
			slot_changed.emit(i, slot)
			changed = true
	if broadcast and changed:
		quickbar_updated.emit(get_slots_snapshot())

func _set_slot(index: int, item: Item, quantity: int) -> void:
	var slot := {
		"item": item,
		"quantity": max(0, quantity)
	}
	slots[index] = slot
	slot_changed.emit(index, slot)
	quickbar_updated.emit(get_slots_snapshot())

func _clear_slot(index: int, broadcast: bool) -> void:
	slots[index] = _empty_slot()
	if broadcast:
		slot_changed.emit(index, slots[index])
		quickbar_updated.emit(get_slots_snapshot())

func _empty_slot() -> Dictionary:
	return {"item": null, "quantity": 0}

func _find_slot_by_item(item: Item) -> int:
	if not item:
		return -1
	for i in SLOT_COUNT:
		var slot := slots[i]
		if slot["item"] and slot["item"].item_name == item.item_name:
			return i
	return -1

func _find_empty_slot() -> int:
	for i in SLOT_COUNT:
		if slots[i]["item"] == null:
			return i
	return -1

func _is_valid_index(index: int) -> bool:
	return index >= 0 and index < SLOT_COUNT
