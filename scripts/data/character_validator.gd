class_name CharacterValidator
extends RefCounted
## Checks one character and reports problems in plain words. The automatic character test
## and the character tool both use it.

static func problems(entry: CharacterDef) -> Array[String]:
	var found: Array[String] = []
	_check_identity(entry, found)
	if entry.body_size.x <= 0.0 or entry.body_size.y <= 0.0:
		found.append("몸 크기는 0보다 커야 합니다.")
	for slot: CharacterDef.Slot in [CharacterDef.Slot.SIDE, CharacterDef.Slot.UP, CharacterDef.Slot.DOWN]:
		if entry.attack(slot) == null:
			found.append("기본 공격 %s 칸이 비어 있습니다." % CharacterDef.Slot.keys()[slot])
	for resource in entry.reachable_resources():
		if resource is AttackData:
			_check_move(resource, found)
		elif resource is ProjectileData:
			_check_projectile(resource, found)
		elif resource is CharacterKit or resource is ProjectileBehavior:
			_check_stateless(resource, found)
	return found

static func _check_identity(entry: CharacterDef, found: Array[String]) -> void:
	var id_rule := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	if id_rule.search(String(entry.id)) == null:
		found.append("id '%s'는 소문자 영어·숫자·밑줄만 쓸 수 있습니다." % entry.id)
	if entry.id == ContentCatalog.RANDOM:
		found.append("id로 random은 쓸 수 없습니다.")
	if entry.display_name.strip_edges().is_empty():
		found.append("표시 이름이 비어 있습니다.")
	if not CharacterArt.has_art(entry.id):
		found.append("대기방 그림 assets/characters/%s.png 가 없습니다." % entry.id)

static func _check_move(move: AttackData, found: Array[String]) -> void:
	if move.startup_frames < 0 or move.recovery_frames < 0:
		found.append("%s: 선딜과 후딜은 0 이상이어야 합니다." % _name_of(move))
	if move.active_frames < 1:
		found.append("%s: 지속 프레임은 1 이상이어야 합니다." % _name_of(move))
	for spawn in move.spawns:
		if spawn == null or spawn.projectile == null:
			found.append("%s: 발사 설정에 투사체가 비어 있습니다." % _name_of(move))
		elif spawn.frame < 0 or spawn.frame >= move.total_frames():
			found.append("%s: 발사 프레임 %d이 기술 길이 %d 프레임 안에 없어 발사되지 않습니다." % [_name_of(move), spawn.frame, move.total_frames()])

static func _check_projectile(projectile: ProjectileData, found: Array[String]) -> void:
	if projectile.size.x <= 0.0 or projectile.size.y <= 0.0:
		found.append("%s: 투사체 크기는 0보다 커야 합니다." % _name_of(projectile))

## Kits and behaviors are shared by every fighter or projectile using them, so anything that
## changes must live in kit_state or Projectile.vars. A plain member would break rollback.
static func _check_stateless(resource: Resource, found: Array[String]) -> void:
	for property in CharacterDef.script_properties(resource):
		var usage := int(property.usage)
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not usage & PROPERTY_USAGE_EDITOR:
			found.append("%s: 변수 '%s'는 @export가 아닙니다. 경기 중 바뀌는 값은 kit_state나 shot.vars에 두어야 합니다." % [_name_of(resource), property.name])

static func _name_of(resource: Resource) -> String:
	if not resource.resource_path.is_empty():
		return resource.resource_path.get_file()
	var script: Script = resource.get_script()
	return script.get_global_name() if not String(script.get_global_name()).is_empty() else script.resource_path.get_file()
