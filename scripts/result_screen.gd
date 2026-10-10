class_name ResultScreen
extends Control
## S4 result: winner line, one column per slot (rank, kills, dealt percent, confirm state)
## and the Enter hint. Rebuilt from Session.arena whenever Session changes.

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
	if not is_instance_valid(arena):
		return
	if arena.winner_id > 0:
		var winner_slot := 0
		for fighter in arena.fighters:
			if fighter.player_id == arena.winner_id:
				winner_slot = fighter.player_slot
		_title.text = UiStyle.WINS % winner_slot
		_title.add_theme_color_override("font_color", UiStyle.slot_color(winner_slot))
	else:
		_title.text = UiStyle.DRAW
		_title.add_theme_color_override("font_color", UiStyle.TEXT)
	var entries: Array[Dictionary] = []
	for fighter in arena.fighters:
		entries.append({"id": fighter.player_id, "out": fighter.eliminated_frame})
	var ranks := FightArena.compute_ranks(entries)
	for child in _columns.get_children():
		_columns.remove_child(child)
		child.queue_free()
	var confirmed_count := 0
	for fighter in arena.fighters:
		var present := Session.local_mode or Session.roster.has(fighter.player_id)
		var done: bool = Session.confirmed.get(fighter.player_id, false)
		if present and done:
			confirmed_count += 1
		_columns.add_child(_column_for(fighter, int(ranks[fighter.player_id]), arena.winner_id, present, done))
	var total := Session.roster.size()
	if Session.local_mode:
		# Local play has one keyboard: a single Enter returns both players.
		total = 1
		confirmed_count = 0
	_hint.text = UiStyle.CONFIRM_HINT % [mini(confirmed_count, total), total]

func _column_for(fighter: Fighter, rank: int, winner_id: int, present: bool, done: bool) -> PanelContainer:
	var mine := fighter.is_local
	var first := rank == 1
	var border := UiStyle.TEXT_DIM
	var width := 1
	if first:
		# A draw shares 1st place with one neutral border and no crown.
		border = UiStyle.slot_color(fighter.player_slot) if winner_id > 0 else UiStyle.TEXT
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
	_add(column, "P%d%s" % [fighter.player_slot, " " + UiStyle.ME_TAG if mine else ""], 22, UiStyle.TEXT)
	_add(column, "■ %s" % UiStyle.SLOT_COLOR_NAMES[(fighter.player_slot - 1) % UiStyle.SLOT_COLOR_NAMES.size()], 18, UiStyle.slot_color(fighter.player_slot))
	_add(column, (UiStyle.CROWN if first and winner_id > 0 else "") + UiStyle.RANK % rank, 26, UiStyle.TEXT)
	column.add_child(HSeparator.new())
	_add_stat(column, UiStyle.KILLS, "%d" % fighter.kills)
	_add_stat(column, UiStyle.DEALT, "%d%%" % roundi(fighter.dealt_percent))
	column.add_child(HSeparator.new())
	if not present:
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
