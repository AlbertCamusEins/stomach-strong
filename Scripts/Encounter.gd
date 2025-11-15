# scripts/Encounter.gd
# 定义一场战斗中会遇到的所有敌人
@tool
class_name Encounter extends Resource

# 导出一个 EnemyData 数组，你可以在编辑器里拖拽多个敌人进来
@export var enemies: Array[CharacterData]
