@tool
class_name EnemyPerception
extends RefCounted

signal wake_body_entered(body: Node)
signal wake_body_exited(body: Node)
signal fear_body_entered(body: Node)
signal fear_body_exited(body: Node)
signal battle_body_entered(body: Node)

var wake_area: Area2D
var fear_area: Area2D
var battle_area: Area2D

func setup(p_wake_area: Area2D, p_fear_area: Area2D, p_battle_area: Area2D) -> void:
	_clear_connections()
	wake_area = p_wake_area
	fear_area = p_fear_area
	battle_area = p_battle_area
	_connect_area(wake_area, Callable(self, "_on_wake_entered"), Callable(self, "_on_wake_exited"))
	_connect_area(fear_area, Callable(self, "_on_fear_entered"), Callable(self, "_on_fear_exited"))
	_connect_area(battle_area, Callable(self, "_on_battle_entered"))

func _clear_connections() -> void:
	if wake_area:
		var wake_enter_callable = Callable(self, "_on_wake_entered")
		var wake_exit_callable = Callable(self, "_on_wake_exited")
		if wake_area.body_entered.is_connected(wake_enter_callable):
			wake_area.body_entered.disconnect(wake_enter_callable)
		if wake_area.body_exited.is_connected(wake_exit_callable):
			wake_area.body_exited.disconnect(wake_exit_callable)
	if fear_area:
		var fear_enter_callable = Callable(self, "_on_fear_entered")
		var fear_exit_callable = Callable(self, "_on_fear_exited")
		if fear_area.body_entered.is_connected(fear_enter_callable):
			fear_area.body_entered.disconnect(fear_enter_callable)
		if fear_area.body_exited.is_connected(fear_exit_callable):
			fear_area.body_exited.disconnect(fear_exit_callable)
	if battle_area:
		var battle_enter_callable = Callable(self, "_on_battle_entered")
		if battle_area.body_entered.is_connected(battle_enter_callable):
			battle_area.body_entered.disconnect(battle_enter_callable)

func _connect_area(area: Area2D, enter_callable: Callable, exit_callable: Callable = Callable()) -> void:
	if not area:
		return
	if enter_callable.is_valid() and not area.body_entered.is_connected(enter_callable):
		area.body_entered.connect(enter_callable)
	if exit_callable.is_valid() and not area.body_exited.is_connected(exit_callable):
		area.body_exited.connect(exit_callable)

func _on_wake_entered(body: Node) -> void:
	wake_body_entered.emit(body)

func _on_wake_exited(body: Node) -> void:
	wake_body_exited.emit(body)

func _on_fear_entered(body: Node) -> void:
	fear_body_entered.emit(body)

func _on_fear_exited(body: Node) -> void:
	fear_body_exited.emit(body)

func _on_battle_entered(body: Node) -> void:
	battle_body_entered.emit(body)
