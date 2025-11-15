@tool
class_name EnemyBehaviorProfile
extends Resource

## Declarative configuration for high-level enemy behaviour.
## The controller script reads these values to decide which
## movement states to enable and how to parameterise them.

@export_group("State Toggles")
@export var uses_sleep_cycle: bool = false
@export var uses_wander_ai: bool = true
@export var can_flee_from_player: bool = true
@export var triggers_battle_on_contact: bool = true

@export_group("Wander Settings")
@export_range(0.0, 500.0, 0.1, "or_greater", "suffix:px/s")
var wander_speed: float = 40.0

@export_range(0.0, 2000.0, 0.1, "or_greater", "suffix:px")
var wander_radius: float = 120.0

@export_range(0.1, 100.0, 0.1, "or_greater", "suffix:px")
var wander_target_tolerance: float = 6.0

@export_range(0.1, 10.0, 0.1, "or_greater", "suffix:s")
var wander_retarget_interval: float = 1.5

@export_group("Flee Settings")
@export_range(0.0, 800.0, 0.1, "or_greater", "suffix:px/s")
var flee_speed: float = 120.0

@export_range(0.0, 2.0, 0.01, "or_greater")
var flee_side_step_factor: float = 0.45

@export_range(0.0, 10.0, 0.1, "or_greater", "suffix:s")
var flee_cooldown: float = 3.0

@export_group("Sleep Settings")
@export_range(0.0, 10.0, 0.1, "or_greater", "suffix:s")
var wake_up_animation_time: float = 1.0

@export_range(0.0, 10.0, 0.1, "or_greater", "suffix:s")
var fall_asleep_delay: float = 2.0

@export_group("Encounter Settings")
@export var encounter_resource: Encounter
@export var remove_after_battle: bool = true

@export_range(0.0, 10.0, 0.1, "suffix:s")
var battle_reenable_delay: float = 0.0
