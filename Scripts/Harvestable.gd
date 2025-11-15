class_name Harvestable extends Area2D

@export var harvestable_item: HarvestableItem
@export var can_harvest: bool

@onready var prompt_label: Label = $Label
@onready var sprite = $Sprite2D


var current_harvests: int

func _ready() -> void:
	current_harvests = harvestable_item.max_harvests
	prompt_label.hide()
	prompt_label.text = harvestable_item.harvestable_name
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	sprite.texture = harvestable_item.texture
	sprite.hframes = harvestable_item.max_harvests + 1
	sprite.frame = 0

func _on_body_entered(body):
	if body is CharacterBody2D:
		prompt_label.show()

func _on_body_exited(body):
	if body is CharacterBody2D:
		prompt_label.hide()

func _unhandled_input(event: InputEvent) -> void:
	if not prompt_label.visible:
		return
	if event.is_action_pressed("ui_accepted"):
		if current_harvests > 0:
			print("采集资源： " + harvestable_item.item_to_harvest.item_name)
			InventoryManager.add_item(harvestable_item.item_to_harvest, harvestable_item.amount_per_harvest)
			current_harvests -= 1
			print(current_harvests)
			sprite.frame = harvestable_item.max_harvests - current_harvests
		elif current_harvests == 0:
			print("没了，你还在采什么")
			prompt_label.hide()
			set_process_unhandled_input(false)
