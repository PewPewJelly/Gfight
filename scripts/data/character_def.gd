class_name CharacterDef
extends Resource
## One selectable character (catalog entry). Art lives at res://assets/characters/<id>.svg,
## tuning at res://resources/characters/<id>.tres, design at GDD/characters/<id>.md.

## Move slots shared by basic attacks and skills (GDD/characters/character-template.md §6).
## UP is ground up and neutral merged; SIDE is the same on the ground and in the air.
enum Slot { SIDE, UP, DOWN, AIR_UP, AIR_DOWN }

@export var id: StringName = &""
@export var display_name: String = ""
## Empty uses res://resources/movement_settings.tres.
@export var movement: MovementSettings

@export_group("Attacks")
@export var side_attack: AttackData
@export var up_attack: AttackData
@export var down_attack: AttackData
## Empty reuses up_attack.
@export var air_up_attack: AttackData
## Empty reuses down_attack.
@export var air_down_attack: AttackData

@export_group("Skills")
## An empty slot means that input does nothing. Empty air slots reuse the ground skill.
@export var side_skill: SkillData
@export var up_skill: SkillData
@export var down_skill: SkillData
@export var air_up_skill: SkillData
@export var air_down_skill: SkillData

func attack(slot: Slot) -> AttackData:
	match slot:
		Slot.SIDE:
			return side_attack
		Slot.UP:
			return up_attack
		Slot.DOWN:
			return down_attack
		Slot.AIR_UP:
			return air_up_attack if air_up_attack != null else up_attack
		Slot.AIR_DOWN:
			return air_down_attack if air_down_attack != null else down_attack
	return null

func skill(slot: Slot) -> SkillData:
	match slot:
		Slot.SIDE:
			return side_skill
		Slot.UP:
			return up_skill
		Slot.DOWN:
			return down_skill
		Slot.AIR_UP:
			return air_up_skill if air_up_skill != null else up_skill
		Slot.AIR_DOWN:
			return air_down_skill if air_down_skill != null else down_skill
	return null
