class_name ContentCatalog
extends Resource
## Characters and maps offered in the lobby (Docs/02 §2.5). Adding an entry here adds a
## selection tile automatically; `random` is offered once a list has two or more entries.

const RANDOM: StringName = &"random"
@export var characters: Array[CharacterDef] = []
@export var maps: Array[MapDef] = []

func character_choices() -> Array[StringName]:
	var choices: Array[StringName] = []
	for entry in characters:
		choices.append(entry.id)
	if characters.size() >= 2:
		choices.append(RANDOM)
	return choices

func map_choices() -> Array[StringName]:
	var choices: Array[StringName] = []
	for entry in maps:
		choices.append(entry.id)
	if maps.size() >= 2:
		choices.append(RANDOM)
	return choices

func is_valid_character(pick: StringName) -> bool:
	return character_choices().has(pick)

func is_valid_map(pick: StringName) -> bool:
	return map_choices().has(pick)

func default_character() -> StringName:
	return characters[0].id if not characters.is_empty() else &""

func default_map() -> StringName:
	return maps[0].id if not maps.is_empty() else &""

func character(id: StringName) -> CharacterDef:
	for entry in characters:
		if entry.id == id:
			return entry
	return null

func map(id: StringName) -> MapDef:
	for entry in maps:
		if entry.id == id:
			return entry
	return null

func character_name(id: StringName) -> String:
	var entry := character(id)
	return entry.display_name if entry != null else (UiStyle.RANDOM_NAME if id == RANDOM else String(id))

func map_name(id: StringName) -> String:
	var entry := map(id)
	return entry.display_name if entry != null else (UiStyle.RANDOM_NAME if id == RANDOM else String(id))

## Returns a known character id, warning and falling back to the first entry otherwise.
func checked_character(pick: StringName) -> StringName:
	if is_valid_character(pick):
		return pick
	push_warning("Unknown character id: %s" % pick)
	return default_character()

func checked_map(pick: StringName) -> StringName:
	if is_valid_map(pick):
		return pick
	push_warning("Unknown map id: %s" % pick)
	return default_map()
