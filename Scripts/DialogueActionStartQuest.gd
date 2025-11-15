# scripts/DialogueActionStartQuest.gd
@tool
class_name DialogueActionStartQuest
extends DialogueAction

@export var quest: Quest

func execute(context: Dictionary) -> void:
	if not quest:
		return
	GameManager.start_quest(quest)
