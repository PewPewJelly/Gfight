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

@export_group("Body and look")
## Width and height in px: collision, the area that gets hit, and where melee hit areas start.
@export var body_size: Vector2 = Vector2(36, 52)
## PNG drawn during matches, its bottom edge at the feet. Empty draws the slot-colored box.
@export var match_sprite: Texture2D
## Drawn height in px. 0 matches the body height.
@export var sprite_height: float = 0.0
## Shifts the art from the feet (x follows facing, up is negative y).
@export var sprite_offset: Vector2 = Vector2.ZERO
## Turn on when the PNG itself looks to the left.
@export var sprite_faces_left: bool = false

@export_group("Kit")
## Character-specific mechanics. Empty means the character is made of data only.
@export var kit: CharacterKit

## Every script-backed resource reachable from this character, in declaration order.
## Snapshots refer to moves and projectiles by their position in lists built from this.
func reachable_resources() -> Array[Resource]:
	var found: Array[Resource] = []
	_collect_resources(self, found)
	return found

static func _collect_resources(value: Variant, found: Array[Resource]) -> void:
	if value is Array:
		for item: Variant in value:
			_collect_resources(item, found)
		return
	if not value is Resource:
		return
	var resource: Resource = value
	if resource.get_script() == null or found.has(resource):
		return
	found.append(resource)
	for property: Dictionary in resource.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			_collect_resources(resource.get(property.name), found)

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
