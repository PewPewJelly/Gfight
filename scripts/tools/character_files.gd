@tool
class_name CharacterFiles
extends RefCounted
## Creates, copies, and saves character files for the character workshop and the character lab.

const CATALOG_PATH := "res://resources/content_catalog.tres"
const TEMPLATE_PATH := "res://Docs/gdd/characters/character-template.md"
const LAB_SCENE := "res://scenes/tools/character_lab.tscn"
const LAB_TARGET_FILE := "user://character_lab_target.txt"
## The comparison character: the tools never overwrite it, and the tests rely on its values.
const BASELINE_ID: StringName = &"test_fighter"

## Tests point these at user:// so they never touch the project.
static var characters_folder := "res://resources/characters"
static var design_folder := "res://Docs/gdd/characters"

static func is_baseline(entry: CharacterDef) -> bool:
	return entry.id == BASELINE_ID

## Why this id cannot be used, or "" when it can.
static func id_problem(id: String, catalog: ContentCatalog) -> String:
	if RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(id) == null:
		return "id는 영어 소문자로 시작하고 소문자·숫자·밑줄만 쓸 수 있습니다."
	if StringName(id) == ContentCatalog.RANDOM:
		return "random은 쓸 수 없는 id입니다."
	if catalog.character(StringName(id)) != null or FileAccess.file_exists(_character_path(id)):
		return "같은 id의 캐릭터가 이미 있습니다."
	return ""

## A fully independent copy, so editing it never changes the original. Slots that shared
## one move still share one move in the copy. Pictures stay shared.
static func copy_of(source: Resource) -> Resource:
	return _copied(source, {})

static func _copied(value: Variant, copies: Dictionary) -> Variant:
	if value is Array:
		var items: Array = value.duplicate()
		for index in range(items.size()):
			items[index] = _copied(items[index], copies)
		return items
	if not value is Resource or value.get_script() == null:
		return value
	if copies.has(value):
		return copies[value]
	var original: Resource = value
	var copy: Resource = original.duplicate(false)
	copies[original] = copy
	for property in CharacterDef.script_properties(original):
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			copy.set(property.name, _copied(original.get(property.name), copies))
	return copy

## Makes a new character from `source`: its own file, a catalog entry, and a design document.
## Returns null if the files cannot be written.
static func create(id: String, display_name: String, source: CharacterDef, catalog: ContentCatalog) -> CharacterDef:
	var entry: CharacterDef = copy_of(source)
	entry.id = StringName(id)
	entry.display_name = display_name
	DirAccess.make_dir_recursive_absolute(characters_folder)
	entry.take_over_path(_character_path(id))
	if ResourceSaver.save(entry) != OK:
		return null
	catalog.characters.append(entry)
	if not catalog.resource_path.is_empty() and ResourceSaver.save(catalog) != OK:
		return null
	write_design_document(id, display_name)
	return entry

## Saves the character and every separate file it refers to. The baseline is never written.
static func save(entry: CharacterDef) -> Error:
	if is_baseline(entry):
		return ERR_UNAUTHORIZED
	for resource in entry.reachable_resources():
		if resource != entry and _has_own_file(resource):
			var error := ResourceSaver.save(resource)
			if error != OK:
				return error
	return ResourceSaver.save(entry)

static func _has_own_file(resource: Resource) -> bool:
	return not resource.resource_path.is_empty() and not resource.resource_path.contains("::")

static func _character_path(id: String) -> String:
	return "%s/%s.tres" % [characters_folder, id]

## Starts Docs/gdd/characters/<id>.md from the template. An existing document is left alone.
static func write_design_document(id: String, display_name: String) -> void:
	var path := "%s/%s.md" % [design_folder, id]
	if FileAccess.file_exists(path):
		return
	var text := FileAccess.get_file_as_string(TEMPLATE_PATH)
	text = text.replace("# 캐릭터 기획서 양식", "# 캐릭터 기획서: %s" % display_name)
	text = text.replace("| 캐릭터 id | `??` |", "| 캐릭터 id | `%s` |" % id)
	text = text.replace("| 표시 이름 | ?? |", "| 표시 이름 | %s |" % display_name)
	text = text.replace("v0.1 (YYYY-MM-DD)", "v0.1 (%s)" % Time.get_date_string_from_system())
	DirAccess.make_dir_recursive_absolute(design_folder)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write %s" % path)
		return
	file.store_string(text)

## What to paste into an AI assistant to get a new mechanic for this character.
static func ai_request(entry: CharacterDef) -> String:
	return "\n".join(PackedStringArray([
		"GFight 캐릭터 `%s`(%s)의 고유 기믹을 구현해 주세요." % [entry.id, entry.display_name],
		"",
		"먼저 읽을 것:",
		"- Docs/gdd/characters/kit-rules.md (반드시 지킬 규칙)",
		"- Docs/gdd/characters/%s.md (기획서)" % entry.id,
		"- resources/characters/%s.tres (현재 캐릭터 값)" % entry.id,
		"",
		"구현 위치: 고유 기믹은 scripts/characters/%s_kit.gd, 새 투사체 동작은 scripts/projectiles/." % entry.id,
		"조절하고 싶은 수치는 전부 @export_range로 선언하고 const LABELS에 한글 이름을 적어 주세요. 작업실과 연습실에 슬라이더로 자동 표시됩니다.",
		"끝나면 tests/character_contract_test.gd가 통과하는지 확인해 주세요.",
		"",
		"원하는 기믹:",
		"(여기에 적어 주세요)",
	]))
