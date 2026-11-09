@tool
class_name CharacterDef
extends Resource
## One selectable character (catalog entry). Art lives at res://assets/characters/<id>.png or
## .svg, tuning at res://resources/characters/<id>.tres, design at Docs/gdd/characters/<id>.md.

## Move slots shared by basic attacks and skills (Docs/gdd/characters/character-template.md §6).
## UP is ground up and neutral merged; SIDE is the same on the ground and in the air.
enum Slot { SIDE, UP, DOWN, AIR_UP, AIR_DOWN }

const SLOT_NAMES: Array[String] = ["옆", "위·중립", "아래", "공중 위", "공중 아래"]
const SLOT_FIELD_STEMS: Array[String] = ["side", "up", "down", "air_up", "air_down"]

## Names shown by the character tools (TuningForm).
const LABELS := {
	"display_name": ["표시 이름", "대기방 선택칸과 프로필에 보이는 이름"],
	"@Body and look": "몸과 그림",
	"body_size": ["몸 크기", "폭과 높이. 이동 충돌, 맞는 범위, 근접 판정의 시작점이 된다"],
	"match_sprite": ["경기 그림", "PNG. 아래쪽 가장자리가 발에 맞는다. 비우면 슬롯 색 상자"],
	"sprite_height": ["그림 높이", "0이면 몸 높이에 맞춘다"],
	"sprite_offset": ["그림 위치 보정", "발 위치에서 옮길 거리. 위는 y 음수"],
	"sprite_faces_left": ["왼쪽을 보는 그림", "PNG 자체가 왼쪽을 보고 있으면 켠다"],
	"@Kit": "고유 기믹",
	"kit": ["고유 기믹", "scripts/characters/ 의 스크립트. 없으면 데이터로만 동작한다"],
}

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
@export_range(0.0, 400.0, 1.0, "or_greater", "suffix:px") var sprite_height: float = 0.0
## Shifts the art from the feet (x follows facing, up is negative y).
@export var sprite_offset: Vector2 = Vector2.ZERO
## Turn on when the PNG itself looks to the left.
@export var sprite_faces_left: bool = false

@export_group("Kit")
## Character-specific mechanics. Empty means the character is made of data only.
@export var kit: CharacterKit

## Name of the exported field that holds the move in this slot.
static func slot_field(slot: Slot, is_skill: bool) -> StringName:
	return StringName("%s_%s" % [SLOT_FIELD_STEMS[slot], "skill" if is_skill else "attack"])

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
	for property in script_properties(resource):
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			_collect_resources(resource.get(property.name), found)

## What a resource's script declares, base class first. Asks the script because in the editor
## a loaded resource whose script is not @tool (kits and behaviors) reports a reduced list.
static func script_properties(resource: Resource) -> Array[Dictionary]:
	var script: Script = resource.get_script()
	return script.get_script_property_list()

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
