extends Node

# 统一处理背包与装备逻辑，供任意 UI / 系统调用

func count_item(item_to_find: Item) -> int:
	if not item_to_find:
		return 0
	var count := 0
	var target_name := item_to_find.item_name
	for slot in GameManager.player_current_inventory:
		if not slot or not slot.item:
			continue
		if slot.item.item_name == target_name:
			count += slot.quantity
	return count

func add_item(item_to_add: Item, quantity: int) -> void:
	if not item_to_add or quantity <= 0:
		return

	if not item_to_add.stackable:
		for i in quantity:
			var slot := InventorySlot.new()
			slot.item = item_to_add.duplicate()
			slot.quantity = 1
			GameManager.player_current_inventory.append(slot)
		_update_collect_progress(item_to_add)
		return

	var remaining_quantity := quantity

	for slot in GameManager.player_current_inventory:
		if remaining_quantity <= 0:
			break
		if not slot or not slot.item:
			continue
		if slot.item.item_name != item_to_add.item_name:
			continue
		if slot.quantity >= slot.item.max_stack_size:
			continue
		var can_add = slot.item.max_stack_size - slot.quantity
		var amount_to_add = min(remaining_quantity, can_add)
		slot.quantity += amount_to_add
		remaining_quantity -= amount_to_add

	while remaining_quantity > 0:
		var new_slot := InventorySlot.new()
		new_slot.item = item_to_add.duplicate()
		var amount = min(remaining_quantity, item_to_add.max_stack_size)
		new_slot.quantity = amount
		remaining_quantity -= amount
		GameManager.player_current_inventory.append(new_slot)

	_update_collect_progress(item_to_add)

func remove_item(item_to_remove: Item, quantity: int) -> void:
	if not item_to_remove or quantity <= 0:
		return

	var remaining_to_remove := quantity
	for i in range(GameManager.player_current_inventory.size() - 1, -1, -1):
		if remaining_to_remove <= 0:
			break
		var slot = GameManager.player_current_inventory[i]
		if not slot or not slot.item:
			continue
		if slot.item.item_name != item_to_remove.item_name:
			continue

		var amount_to_remove = min(remaining_to_remove, slot.quantity)
		slot.quantity -= amount_to_remove
		remaining_to_remove -= amount_to_remove
		if slot.quantity <= 0:
			GameManager.player_current_inventory.remove_at(i)

	_update_collect_progress(item_to_remove)

func equip_item(item_to_equip: Item) -> void:
	equip_item_for_character(GameManager._get_current_player_id(), item_to_equip)

func equip_item_for_character(character_id: String, item_to_equip: Item) -> void:
	if character_id.is_empty() or not item_to_equip or not item_to_equip.equipment_props:
		return

	var equipment = GameManager.get_character_equipment(character_id)
	var slot_enum = item_to_equip.equipment_props.slot

	if equipment.has(slot_enum):
		unequip_item_for_character(character_id, slot_enum)

	remove_item(item_to_equip, 1)
	equipment[slot_enum] = item_to_equip

	GameManager._sync_character_equipped_slots(character_id, equipment)
	GameManager.calculate_total_stats(character_id)

func unequip_item(slot_enum: EquipmentComponent.EquipmentSlot) -> void:
	unequip_item_for_character(GameManager._get_current_player_id(), slot_enum)

func unequip_item_for_character(character_id: String, slot_enum: EquipmentComponent.EquipmentSlot) -> void:
	if character_id.is_empty():
		return

	var equipment = GameManager.get_character_equipment(character_id, false)
	if not equipment or not equipment.has(slot_enum):
		return

	var item_to_unequip = equipment[slot_enum]
	equipment.erase(slot_enum)
	if item_to_unequip:
		add_item(item_to_unequip, 1)

	GameManager._sync_character_equipped_slots(character_id, equipment)
	GameManager.calculate_total_stats(character_id)

func _update_collect_progress(item: Item) -> void:
	if not item:
		return
	var total := count_item(item)
	GameManager.update_quest_progress(QuestObjective.ObjectiveType.COLLECT, item, total)
