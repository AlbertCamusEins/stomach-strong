# scripts/DialogueActionAdvanceObjective.gd
@tool
class_name DialogueActionAdvanceObjective
extends DialogueAction

@export var quest_id: String
@export var objective_index: int = 0
@export var progress: int = 1
@export var mark_complete: bool = false

func execute(context: Dictionary) -> void:
	if quest_id.is_empty():
		return
	var gm = GameManager
	if gm == null:
		return
	var quest = gm.active_quests.get(quest_id)
	if quest == null:
		return
	if objective_index < 0 or objective_index >= quest.objectives.size():
		return
	var objective: QuestObjective = quest.objectives[objective_index]
	if mark_complete:
		objective.current_progress = objective.collect_quantity if objective.type == QuestObjective.ObjectiveType.COLLECT else progress
		objective.is_complete = true
	else:
		objective.current_progress = max(objective.current_progress, progress)
	objective.check_completion()
	if quest.check_completion():
		quest.current_state = Quest.QuestState.COMPLETED
		if not gm.completed_quests.has(quest_id):
			gm.completed_quests.append(quest_id)
		gm.active_quests.erase(quest_id)
		for item in quest.item_rewards.keys():
			InventoryManager.add_item(item, quest.item_rewards[item])
			
