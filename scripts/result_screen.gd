class_name ResultScreen
extends Control
## S4 result: winner line, one column per slot (rank, kills, dealt percent, confirm state)
## and the Enter hint. Rebuilt from Session.match_result() whenever Session changes.

var _title: Label
var _columns: HBoxContainer
var _hint: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dimmer := ColorRect.new()
	dimmer.color = Color(UiStyle.BACKGROUND, 0.92)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dimmer)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 28)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(column)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 44)
	column.add_child(_title)
	_columns = HBoxContainer.new()
	_columns.alignment = BoxContainer.ALIGNMENT_CENTER
	_columns.add_theme_constant_override("separation", 18)
	column.add_child(_columns)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 20)
	column.add_child(_hint)
	visible = false

func refresh() -> void:
	var arena := Session.arena
	var result := Session.match_result()
	if result == null:
		return
	var fighters := {}
	for fighter in arena.fighters:
		fighters[fighter.player_id] = fighter
	if result.winner_id > 0:
		var winner: Fighter = fighters[result.winner_id]
		_title.text = UiStyle.DUMMY_WINS if winner.is_dummy else UiStyle.WINS % winner.player_slot
		_title.add_theme_color_override("font_color", winner.tint)
	else:
		_title.text = UiStyle.DRAW
		_title.add_theme_color_override("font_color", UiStyle.TEXT)
	for child in _columns.get_children():
		_columns.remove_child(child)
		child.queue_free()
	var confirmed_count := 0
	for entry in result.entries:
		var done: bool = Session.confirmed.get(entry.peer_id, false)
		if entry.present and done and not entry.is_dummy:
			confirmed_count += 1
		_columns.add_child(_column_for(fighters[entry.peer_id], entry, result.winner_id, done))
	var total := Session.room.players.size()
	if Session.is_offline():
		# Offline play has one keyboard: a single Enter returns everyone.
		total = 1
		confirmed_count = 0
	_hint.text = UiStyle.CONFIRM_HINT % [mini(confirmed_count, total), total]

func _column_for(fighter: Fighter, entry: MatchResultEntry, winner_id: int, done: bool) -> PanelContainer:
	var mine := fighter.is_local
	var first := entry.rank == 1
	var border := UiStyle.TEXT_DIM
	var width := 1
	if first:
		# A draw shares 1st place with one neutral border and no crown.
		border = fighter.tint if winner_id > 0 else UiStyle.TEXT
		width = 3
	elif mine:
		border = UiStyle.ACCENT
		width = 3
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(220, 0)
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, border, width, 12))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	if entry.is_dummy:
		_add(column, UiStyle.DUMMY, 22, UiStyle.TEXT)
		_add(column, "■", 18, fighter.tint)
	else:
		_add(column, "P%d%s" % [entry.slot, " " + UiStyle.ME_TAG if mine else ""], 22, UiStyle.TEXT)
		_add(column, "■ %s" % UiStyle.SLOT_COLOR_NAMES[(entry.slot - 1) % UiStyle.SLOT_COLOR_NAMES.size()], 18, fighter.tint)
	_add(column, (UiStyle.CROWN if first and winner_id > 0 else "") + UiStyle.RANK % entry.rank, 26, UiStyle.TEXT)
	column.add_child(HSeparator.new())
	_add_stat(column, UiStyle.KILLS, "%d" % entry.kills)
	_add_stat(column, UiStyle.DEALT, "%d%%" % roundi(entry.dealt_percent))
	column.add_child(HSeparator.new())
	if entry.is_dummy:
		_add(column, "", 18, UiStyle.TEXT_DIM)
	elif not entry.present:
		_add(column, UiStyle.LEFT_RESULT, 18, UiStyle.TEXT_DIM)
	elif done:
		_add(column, UiStyle.CONFIRMED, 18, UiStyle.READY)
	else:
		_add(column, UiStyle.STATE_WAITING, 18, UiStyle.TEXT_DIM)
	return panel

func _add(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _add_stat(parent: Node, name_text: String, value: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var name_label := _add(row, name_text, 17, UiStyle.TEXT_DIM)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label := _add(row, value, 18, UiStyle.TEXT)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
