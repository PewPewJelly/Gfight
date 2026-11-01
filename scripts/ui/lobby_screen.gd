class_name LobbyScreen
extends Control
## SYS-02 대기방 (Docs/02). Handlers change the four state axes and call Session;
## _refresh_view() is the only place that changes what is shown.

signal exit_requested(result: LobbyExitResult)

## Screen flow (overlays and transitions). One at a time.
enum FlowState {
	BROWSING,     # default; tabs usable
	CHAT_INPUT,   # typing my speech bubble (online only)
	INFO_OPEN,    # room address popover open (online only)
	MENU_OPEN,    # another player's ⋯ menu open (host only)
	MODAL_OPEN,   # modal open (kind in modal_kind)
	STARTING,     # start requested, waiting for the match
	CLOSING,      # host closing the room (Session.Phase.CLOSING, 0.2 s)
	LEAVING,      # switching screens; all input ignored
}
enum Tab { ROOM, CHARACTER, SETTINGS }
enum SettingsView { ROOM, PERSONAL, MAP }
enum ReadyButtonState { IDLE, READY, START, START_DISABLED }
enum ModalKind { NONE, EXIT, KICK, PROFILE }
## Values match PlayerList.ACTION_*.
enum PlayerAction { PROFILE, MUTE, KICK }

const BUBBLE_SECONDS: float = 3.0
const CHAT_REOPEN_GUARD_MSEC: int = 300
const COPY_FEEDBACK_SECONDS: float = 1.6
const WHEEL_STEP_PX: float = 40.0
const TOAST_SECONDS: float = 3.0
const CHARACTER_COLUMNS_MAX: int = 3
const CHARACTER_TILE_HEIGHT: float = 300.0
const CHARACTER_SHIFTS: Array[float] = [0.0, -0.38, 0.1]
const MAP_TILE_HEIGHT: float = 316.0
const ROOM_NAME_MAX_WIDTH: float = 320.0
const ROOM_NAME_FONT: int = 38
const NICKNAME_MAX_WIDTH: float = 360.0
const NICKNAME_FONT: int = 88
const HOST_STAR_GAP: float = 8.0
const STRIPE_SPACING: float = 28.0
const STRIPE_WIDTH: float = 2.0
const STRIPE_COLOR := Color(1, 1, 1, 0.045)
const PORTRAIT_SHADOW_COLOR := Color(0, 0, 0, 0.15)
const MY_CARD_START := Vector2(-20, 0)
const MY_CARD_CURVE: Array[Vector2] = [Vector2(572, 48), Vector2(592, 50), Vector2(592, 70)]
const MY_CARD_BOTTOM: float = 226.0
const MY_CARD_BORDER: float = 5.0
const MY_CARD_SHADOW_OFFSET := Vector2(10, -10)
const MY_CARD_SHADOW_COLOR := Color(0, 0, 0, 0.14)
const ARROW_POINTS: Array[Vector2] = [Vector2(1910, 221.3), Vector2(1838, 560), Vector2(1910, 898.7)]
const ARROW_BORDER: float = 6.0
const MODAL_WIDTH: float = 780.0
const PROFILE_MODAL_WIDTH: float = 820.0
const MODAL_PAD := Vector2(48, 36)
const MODAL_TITLE_FONT: int = 40
const PROFILE_ART_SIZE: float = 240.0
const TOAST_MIN_WIDTH: float = 400.0
const PLAYER_LIST_SCENE: PackedScene = preload("res://scenes/ui/lobby/player_list.tscn")
const SLANT_GRID_SCENE: PackedScene = preload("res://scenes/ui/lobby/slant_grid.tscn")
const SETTINGS_PANEL_SCENE: PackedScene = preload("res://scenes/ui/lobby/settings_panel.tscn")

var flow: FlowState = FlowState.BROWSING
var active_tab: Tab = Tab.ROOM
var settings_view: SettingsView = SettingsView.ROOM
var modal_kind: ModalKind = ModalKind.NONE
var modal_target_id: int = 0
var menu_target_id: int = 0
## Players I muted (int -> true). Their bubbles are not shown. Cleared when leaving.
var muted_ids: Dictionary = {}
## { &"bgm": int, &"sfx": int }, shared with the main menu settings (settings.cfg [audio]).
var prefs: Dictionary = {}
var _bubbles: Dictionary = {}                 # int -> { "text": String, "left": float }
var _chat_closed_msec: int = -CHAT_REOPEN_GUARD_MSEC
var _room_mode: ScreenTypes.RoomMode = ScreenTypes.RoomMode.ONLINE
## The one child of ContentHost (PlayerList, SlantGrid or SettingsPanel).
var _content: Control
var _copy_left: float = 0.0
var _toast_left: float = 0.0
var _last_notice: String = ""
var _profile_state_label: Label

@onready var lobby_stage: Control = %LobbyStage
@onready var stage_frame: Panel = %StageFrame
@onready var stage: Control = %Stage
@onready var stripes: Control = %Stripes
@onready var portrait_shadow: Control = %PortraitShadow
@onready var portrait_art: CharacterArt = %PortraitArt
@onready var my_bubble: BubbleView = %MyBubble
@onready var chat_input: BubbleInput = %ChatInput
@onready var chat_hint_button: Button = %ChatHintButton
@onready var my_card_shape: Control = %MyCardShape
@onready var my_character_name: Label = %MyCharacterName
@onready var my_nickname: Label = %MyNickname
@onready var my_host_star: TextureRect = %MyHostStar
@onready var ready_button: RoundButton = %ReadyButton
@onready var content_host: Control = %ContentHost
@onready var tab_room: SlantTab = %TabRoom
@onready var tab_character: SlantTab = %TabCharacter
@onready var tab_settings: SlantTab = %TabSettings
@onready var ready_arrow: Control = %ReadyArrow
@onready var back_button: RoundButton = %BackButton
@onready var room_name_box: PanelContainer = %RoomNameBox
@onready var room_name_label: Label = %RoomNameLabel
@onready var info_button: Button = %InfoButton
@onready var map_chip: Chip = %MapChip
@onready var ready_chip: Chip = %ReadyChip
@onready var info_popover: PanelContainer = %InfoPopover
@onready var address_label: Label = %AddressLabel
@onready var copy_button: Button = %CopyButton
@onready var modal_layer: Control = %ModalLayer
@onready var dimmer: ColorRect = %Dimmer
@onready var modal_box: SlantBox = %ModalBox
@onready var modal_column: VBoxContainer = %ModalColumn
@onready var modal_title: Label = %ModalTitle
@onready var modal_body: VBoxContainer = %ModalBody
@onready var modal_buttons: HBoxContainer = %ModalButtons
@onready var toast: PanelContainer = %Toast
@onready var toast_label: Label = %ToastLabel

func _ready() -> void:
	stage_frame.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.LOBBY_BG, UiStyle.LOBBY_LINE, 5, 36))
	var name_box := UiStyle.box(UiStyle.LOBBY_CARD, UiStyle.LOBBY_LINE, 4, 22)
	name_box.content_margin_left = 28
	name_box.content_margin_right = 12
	name_box.content_margin_top = 0
	name_box.content_margin_bottom = 0
	room_name_box.add_theme_stylebox_override("panel", name_box)
	room_name_label.add_theme_font_override("font", UiStyle.bold_font())
	_style_flat_button(info_button, UiStyle.box(Color.WHITE, UiStyle.LOBBY_LINE, 3, 14))
	for color_name in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		info_button.add_theme_color_override(color_name, UiStyle.LOBBY_LINE_DARK)
	var popover := UiStyle.box(UiStyle.LOBBY_CARD, UiStyle.LOBBY_LINE, 4, 18)
	popover.shadow_color = UiStyle.LOBBY_LINE
	popover.shadow_size = 1
	popover.shadow_offset = Vector2(0, 6)
	popover.content_margin_left = 24
	popover.content_margin_right = 24
	popover.content_margin_top = 18
	popover.content_margin_bottom = 18
	info_popover.add_theme_stylebox_override("panel", popover)
	address_label.add_theme_font_override("font", UiStyle.bold_font())
	_style_flat_button(copy_button, UiStyle.box(Color.WHITE, UiStyle.LOBBY_LINE, 3, 14))
	copy_button.add_theme_font_override("font", UiStyle.bold_font())
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		copy_button.add_theme_color_override(color_name, UiStyle.LOBBY_TEXT)
	copy_button.icon = LobbyIcons.texture(LobbyIcons.Kind.COPY)
	copy_button.expand_icon = false
	for color_name in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		copy_button.add_theme_color_override(color_name, UiStyle.LOBBY_LINE_DARK)
	copy_button.add_theme_constant_override("icon_max_width", 28)
	_style_flat_button(chat_hint_button, UiStyle.box(Color(0, 0, 0, 0.25), Color.TRANSPARENT, 0, 22))
	chat_hint_button.text = UiStyle.CHAT_HINT
	var toast_style := UiStyle.box(Color(0, 0, 0, 0.7), Color.TRANSPARENT, 0, 30)
	toast_style.content_margin_left = 28
	toast_style.content_margin_right = 28
	toast.add_theme_stylebox_override("panel", toast_style)
	toast.custom_minimum_size.x = TOAST_MIN_WIDTH
	my_character_name.add_theme_font_override("font", UiStyle.bold_font())
	my_nickname.add_theme_font_override("font", UiStyle.bold_font(1.0))
	tab_room.text = UiStyle.TAB_ROOM
	tab_character.text = UiStyle.TAB_CHARACTER
	tab_settings.text = UiStyle.TAB_SETTINGS
	back_button.pressed.connect(_on_back_pressed)
	info_button.pressed.connect(_on_info_pressed)
	copy_button.pressed.connect(_on_copy_pressed)
	chat_hint_button.pressed.connect(_open_chat)
	ready_button.pressed.connect(_on_ready_button_pressed)
	tab_room.pressed.connect(_on_tab_pressed.bind(Tab.ROOM))
	tab_character.pressed.connect(_on_tab_pressed.bind(Tab.CHARACTER))
	tab_settings.pressed.connect(_on_tab_pressed.bind(Tab.SETTINGS))
	chat_input.line_edit.text_submitted.connect(_on_chat_submitted)
	chat_input.line_edit.focus_exited.connect(_on_chat_focus_exited)
	dimmer.gui_input.connect(_on_dimmer_input)
	stripes.draw.connect(_draw_stripes)
	portrait_shadow.draw.connect(_draw_portrait_shadow)
	my_card_shape.draw.connect(_draw_my_card)
	ready_arrow.draw.connect(_draw_ready_arrow)
	resized.connect(_fit_stage)
	set_process(false)
	_fit_stage()

func _process(delta: float) -> void:
	var bubbles_changed := false
	for peer_id: int in _bubbles.keys():
		var bubble: Dictionary = _bubbles[peer_id]
		bubble["left"] = float(bubble["left"]) - delta
		if float(bubble["left"]) <= 0.0:
			_bubbles.erase(peer_id)
			bubbles_changed = true
	if _copy_left > 0.0:
		_copy_left -= delta
		if _copy_left <= 0.0:
			copy_button.text = UiStyle.COPY
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			toast.visible = false
	if bubbles_changed:
		_refresh_view()
	if _bubbles.is_empty() and _copy_left <= 0.0 and _toast_left <= 0.0:
		set_process(false)

## Popover and ⋯ menu close on a click outside them (Docs/02 §4.9).
func _input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if flow == FlowState.INFO_OPEN:
		if not info_popover.get_global_rect().has_point(click.position) and not info_button.get_global_rect().has_point(click.position):
			_set_flow(FlowState.BROWSING)
	elif flow == FlowState.MENU_OPEN:
		var list := _content as PlayerList
		if list == null or not list.menu_rect().has_point(click.position):
			_set_flow(FlowState.BROWSING)
			# The cards are rebuilt on close, so the same click must not reopen the menu.
			get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		_on_escape()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER] and not key.alt_pressed:
		if _chat_enabled() and flow == FlowState.BROWSING and Time.get_ticks_msec() - _chat_closed_msec > CHAT_REOPEN_GUARD_MSEC:
			_open_chat()
			get_viewport().set_input_as_handled()

func enter(data: LobbyEnterData) -> void:
	if data == null:
		data = LobbyEnterData.new()
	_room_mode = data.room_mode
	active_tab = clampi(data.initial_tab, 0, Tab.size() - 1) as Tab
	settings_view = SettingsView.ROOM
	flow = FlowState.BROWSING
	modal_kind = ModalKind.NONE
	muted_ids.clear()
	_bubbles.clear()
	_last_notice = Session.room.notice
	prefs = {
		&"bgm": int(Session.load_setting("audio", "bgm", Session.DEFAULT_BGM)),
		&"sfx": int(Session.load_setting("audio", "sfx", Session.DEFAULT_SFX)),
	}
	if not Session.changed.is_connected(_on_session_changed):
		Session.changed.connect(_on_session_changed)
	if not Session.chat_received.is_connected(_on_chat_received):
		Session.chat_received.connect(_on_chat_received)
	_rebuild_content()
	_refresh_view()

func ready_button_state() -> ReadyButtonState:
	if _is_training() or Session.is_host():
		return ReadyButtonState.START if Session.can_start() else ReadyButtonState.START_DISABLED
	var me := Session.room.player(Session.my_id())
	return ReadyButtonState.READY if me != null and me.is_ready else ReadyButtonState.IDLE

func _set_flow(next: FlowState) -> void:
	if flow == FlowState.LEAVING:
		return
	if flow == FlowState.CHAT_INPUT and next != FlowState.CHAT_INPUT:
		_chat_closed_msec = Time.get_ticks_msec()
	if next != FlowState.MODAL_OPEN:
		modal_kind = ModalKind.NONE
	flow = next
	_refresh_view()

func _exit_to(route: LobbyExitResult.Route, notice: String = "", setup: MatchSetup = null) -> void:
	_set_flow(FlowState.LEAVING)
	var result := LobbyExitResult.new()
	result.route = route
	result.notice = notice
	result.match_setup = setup
	exit_requested.emit(result)

func _is_training() -> bool:
	return _room_mode == ScreenTypes.RoomMode.TRAINING

## Chat needs real peers: not in training or the one-keyboard test room.
func _chat_enabled() -> bool:
	return not _is_training() and not Session.is_offline()

# View ---------------------------------------------------------------------------

## Docs/02 §3. Display only: reads Session and the four state axes.
func _refresh_view() -> void:
	var room := Session.room
	var online := not _is_training()
	var me := room.player(Session.my_id())
	var busy := flow in [FlowState.STARTING, FlowState.CLOSING, FlowState.LEAVING]
	var title := UiStyle.TRAINING_ROOM
	if online:
		title = room.name if not room.name.is_empty() else UiStyle.ROOM_UNNAMED
	room_name_label.text = title
	room_name_label.custom_minimum_size.x = minf(ROOM_NAME_MAX_WIDTH, UiStyle.bold_font().get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, ROOM_NAME_FONT).x + 2.0)
	info_button.visible = online and not Session.is_offline()
	info_button.disabled = busy
	back_button.disabled = busy
	info_popover.visible = flow == FlowState.INFO_OPEN
	address_label.text = room.address
	copy_button.text = UiStyle.COPIED if _copy_left > 0.0 else UiStyle.COPY
	map_chip.set_parts(UiStyle.MAP_CHIP_LABEL, Session.catalog.map_name(room.map))
	ready_chip.visible = online
	ready_chip.set_parts(UiStyle.READY_CHIP_LABEL, UiStyle.READY_CHIP_VALUE % [Session.ready_count(), maxi(0, room.players.size() - 1)])
	var pick := me.character if me != null else Session.catalog.default_character()
	if portrait_art.pick != pick:
		portrait_art.pick = pick
	my_character_name.text = Session.catalog.character_name(pick)
	my_nickname.text = me.display_name if me != null else Session.local_name
	var nickname_width := minf(NICKNAME_MAX_WIDTH, UiStyle.bold_font(1.0).get_string_size(my_nickname.text, HORIZONTAL_ALIGNMENT_LEFT, -1, NICKNAME_FONT).x)
	my_host_star.visible = online and Session.is_host() and not Session.is_offline()
	my_host_star.position.x = my_nickname.position.x + nickname_width + HOST_STAR_GAP
	_apply_ready_button(ready_button_state(), busy)
	chat_hint_button.visible = _chat_enabled() and flow == FlowState.BROWSING
	chat_input.visible = flow == FlowState.CHAT_INPUT
	var my_bubble_text := "" if flow == FlowState.CHAT_INPUT else _bubble_text(Session.my_id())
	my_bubble.show_text(my_bubble_text, Vector2.ZERO)
	tab_room.active = active_tab == Tab.ROOM
	tab_character.active = active_tab == Tab.CHARACTER
	tab_settings.active = active_tab == Tab.SETTINGS
	for tab: SlantTab in [tab_room, tab_character, tab_settings]:
		tab.disabled = busy
	ready_arrow.visible = online
	ready_arrow.queue_redraw()
	modal_layer.visible = flow == FlowState.MODAL_OPEN
	if flow == FlowState.MODAL_OPEN and modal_kind == ModalKind.PROFILE and _profile_state_label != null:
		_profile_state_label.text = _profile_state_text(room.player(modal_target_id))
	_refresh_content(online, me)

func _refresh_content(online: bool, me: PlayerData) -> void:
	if _content is PlayerList:
		var bubbles: Dictionary = {}
		for peer_id: int in _bubbles:
			bubbles[peer_id] = _bubble_text(peer_id)
		var can_manage := Session.is_host() and not Session.is_offline()
		(_content as PlayerList).refresh(Session.room, Session.my_id(), can_manage, online, muted_ids, bubbles,
			menu_target_id if flow == FlowState.MENU_OPEN else 0)
	elif _content is SlantGrid:
		var grid := _content as SlantGrid
		if grid.kind == SelectTile.Kind.CHARACTER:
			grid.set_selected(me.character if me != null else &"")
			var locked := online and not Session.is_host() and me != null and me.is_ready
			grid.set_locked(locked, UiStyle.READY_LOCKED, locked)
		else:
			grid.set_selected(Session.room.map)
	elif _content is SettingsPanel:
		var view := SettingsPanel.VIEW_PERSONAL if settings_view == SettingsView.PERSONAL else SettingsPanel.VIEW_ROOM
		var my_name := me.display_name if me != null else Session.local_name
		(_content as SettingsPanel).refresh(view, Session.room, Session.is_host(), not online, my_name, prefs)

## Docs/02 §3.5 ReadyButton table.
func _apply_ready_button(state: ReadyButtonState, busy: bool) -> void:
	match state:
		ReadyButtonState.IDLE:
			_paint_ready_button(UiStyle.LOBBY_RED_BG, UiStyle.LOBBY_RED, UiStyle.LOBBY_RED_SHADOW, LobbyIcons.Kind.X, 56.0, UiStyle.TIP_READY)
		ReadyButtonState.READY:
			_paint_ready_button(UiStyle.LOBBY_READY_BG, UiStyle.LOBBY_LINE, UiStyle.LOBBY_LINE, LobbyIcons.Kind.V, 56.0, UiStyle.TIP_UNREADY)
		ReadyButtonState.START:
			_paint_ready_button(UiStyle.LOBBY_START_BG, UiStyle.LOBBY_START, UiStyle.LOBBY_START_SHADOW, LobbyIcons.Kind.PLAY, 46.0, UiStyle.TIP_START)
		ReadyButtonState.START_DISABLED:
			_paint_ready_button(UiStyle.LOBBY_START_BG, UiStyle.LOBBY_START, UiStyle.LOBBY_START_SHADOW, LobbyIcons.Kind.PLAY, 46.0, _start_condition_text())
	ready_button.disabled = busy or state == ReadyButtonState.START_DISABLED
	ready_button.modulate.a = 0.4 if state == ReadyButtonState.START_DISABLED else 1.0

func _paint_ready_button(fill: Color, line: Color, shadow: Color, icon: LobbyIcons.Kind, icon_size: float, tooltip: String) -> void:
	ready_button.fill = fill
	ready_button.border_color = line
	ready_button.shadow_color = shadow
	ready_button.icon = icon
	ready_button.icon_size = icon_size
	ready_button.icon_color = line
	ready_button.tooltip_text = tooltip

func _start_condition_text() -> String:
	if Session.catalog.characters.is_empty() or Session.catalog.maps.is_empty():
		return UiStyle.EMPTY_CATALOG
	if Session.room.players.size() < RoomState.MIN_PLAYERS:
		return UiStyle.NEED_TWO
	return UiStyle.NEED_READY

func _bubble_text(peer_id: int) -> String:
	var bubble: Dictionary = _bubbles.get(peer_id, {})
	return str(bubble.get("text", ""))

func _ready_ratio() -> float:
	var others := Session.room.players.size() - 1
	return float(Session.ready_count()) / others if others > 0 else 0.0

## Keeps the 1920×1080 stage whole and centered; Backdrop fills the rest (Docs/02 §5).
func _fit_stage() -> void:
	var factor := minf(size.x / LobbyGeometry.ROOT_SIZE.x, size.y / LobbyGeometry.ROOT_SIZE.y)
	if factor <= 0.0:
		return
	lobby_stage.scale = Vector2(factor, factor)
	lobby_stage.position = (size - LobbyGeometry.ROOT_SIZE * factor) / 2.0

func _show_toast(text: String) -> void:
	if text.is_empty():
		return
	toast_label.text = text
	toast.visible = true
	toast.size = toast.get_combined_minimum_size()
	toast.position.x = (stage.size.x - toast.size.x) / 2.0
	_toast_left = TOAST_SECONDS
	set_process(true)

# Content ------------------------------------------------------------------------

## Docs/02 §4.4: ContentHost holds exactly one of the four content scenes.
func _rebuild_content() -> void:
	# Cleared first: removing a focused input commits it, which refreshes the view.
	_content = null
	for child in content_host.get_children():
		content_host.remove_child(child)
		child.queue_free()
	var content: Control
	if active_tab == Tab.CHARACTER:
		var grid: SlantGrid = SLANT_GRID_SCENE.instantiate()
		content_host.add_child(grid)
		var items := _grid_items(SelectTile.Kind.CHARACTER)
		var columns := clampi(items.size(), 1, CHARACTER_COLUMNS_MAX)
		var shifts: Array[float] = []
		if columns == CHARACTER_COLUMNS_MAX:
			shifts.assign(CHARACTER_SHIFTS)
		grid.setup(SelectTile.Kind.CHARACTER, items, columns, CHARACTER_TILE_HEIGHT, shifts)
		grid.tile_picked.connect(_on_character_tile_selected)
		grid.unready_pressed.connect(_on_unready_pressed)
		grid.gui_input.connect(_on_grid_input.bind(grid))
		content = grid
	elif active_tab == Tab.SETTINGS and settings_view == SettingsView.MAP and Session.is_host():
		var map_grid: SlantGrid = SLANT_GRID_SCENE.instantiate()
		content_host.add_child(map_grid)
		var no_shifts: Array[float] = []
		map_grid.setup(SelectTile.Kind.MAP, _grid_items(SelectTile.Kind.MAP), 1, MAP_TILE_HEIGHT, no_shifts)
		map_grid.tile_picked.connect(_on_map_tile_selected)
		map_grid.gui_input.connect(_on_grid_input.bind(map_grid))
		content = map_grid
	elif active_tab == Tab.SETTINGS:
		var panel: SettingsPanel = SETTINGS_PANEL_SCENE.instantiate()
		content_host.add_child(panel)
		panel.sub_tab_selected.connect(_on_sub_tab_selected)
		panel.room_name_committed.connect(_on_room_name_committed)
		panel.map_button_pressed.connect(_on_map_button_pressed)
		panel.max_players_pressed.connect(_on_max_players_pressed)
		panel.nickname_committed.connect(_on_nickname_committed)
		panel.pref_changed.connect(_on_pref_changed)
		content = panel
	else:
		var list: PlayerList = PLAYER_LIST_SCENE.instantiate()
		content_host.add_child(list)
		list.menu_pressed.connect(_on_player_menu_pressed)
		list.action_chosen.connect(_on_player_action)
		content = list
	_content = content

## Docs/02 §2.5: catalog order, plus random once there are two or more entries.
func _grid_items(kind: SelectTile.Kind) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var catalog := Session.catalog
	if kind == SelectTile.Kind.CHARACTER:
		for pick in catalog.character_choices():
			items.append({"pick": pick, "name": catalog.character_name(pick)})
	else:
		for pick in catalog.map_choices():
			var map_def := catalog.map(pick)
			items.append({"pick": pick, "name": catalog.map_name(pick), "english": map_def.english_name if map_def != null else ""})
	return items

# Tabs ---------------------------------------------------------------------------

func _on_tab_pressed(tab: Tab) -> void:
	if flow not in [FlowState.BROWSING, FlowState.INFO_OPEN]:
		return
	if flow == FlowState.INFO_OPEN:
		_set_flow(FlowState.BROWSING)
	if tab == Tab.SETTINGS and settings_view == SettingsView.MAP:
		settings_view = SettingsView.ROOM
	active_tab = tab
	_rebuild_content()
	_refresh_view()

func _on_sub_tab_selected(view: int) -> void:
	if flow != FlowState.BROWSING:
		return
	settings_view = SettingsView.PERSONAL if view == SettingsPanel.VIEW_PERSONAL else SettingsView.ROOM
	_refresh_view()

# Ready / start ------------------------------------------------------------------

func _on_ready_button_pressed() -> void:
	if flow != FlowState.BROWSING:
		return
	match ready_button_state():
		ReadyButtonState.START:
			_set_flow(FlowState.STARTING)
			if not Session.start_game():
				_set_flow(FlowState.BROWSING)
		ReadyButtonState.IDLE:
			Session.set_ready(true)
		ReadyButtonState.READY:
			Session.set_ready(false)

func _on_unready_pressed() -> void:
	if flow == FlowState.BROWSING:
		Session.set_ready(false)

# Character / map ----------------------------------------------------------------

func _on_character_tile_selected(pick: StringName) -> void:
	if flow != FlowState.BROWSING:
		return
	var me := Session.room.player(Session.my_id())
	if not _is_training() and not Session.is_host() and me != null and me.is_ready:
		return
	Session.set_character(pick)

func _on_map_button_pressed() -> void:
	if flow != FlowState.BROWSING or not Session.is_host():
		return
	settings_view = SettingsView.MAP
	_rebuild_content()
	_refresh_view()

func _on_map_tile_selected(pick: StringName) -> void:
	if flow != FlowState.BROWSING or not Session.is_host():
		return
	Session.update_room({"map": pick})
	settings_view = SettingsView.ROOM
	_rebuild_content()
	_refresh_view()

func _on_grid_input(event: InputEvent, grid: SlantGrid) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			grid.scroll_by(-WHEEL_STEP_PX)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			grid.scroll_by(WHEEL_STEP_PX)
	var pan := event as InputEventPanGesture
	if pan != null:
		grid.scroll_by(pan.delta.y * WHEEL_STEP_PX)

# Settings -----------------------------------------------------------------------

func _on_room_name_committed(text: String) -> void:
	if Session.is_host() and RoomState.clean_name(text) != Session.room.name:
		Session.update_room({"name": text})

func _on_max_players_pressed(value: int) -> void:
	if flow == FlowState.BROWSING and Session.is_host():
		Session.update_room({"max_players": value})

func _on_nickname_committed(text: String) -> void:
	var me := Session.room.player(Session.my_id())
	if me == null or Session.clean_name(text) != me.display_name:
		Session.set_display_name(text)

func _on_pref_changed(key: StringName, value: int) -> void:
	prefs[key] = value
	Session.save_setting("audio", String(key), value)

# Chat ---------------------------------------------------------------------------

func _open_chat() -> void:
	if not _chat_enabled() or flow != FlowState.BROWSING:
		return
	_set_flow(FlowState.CHAT_INPUT)
	chat_input.clear_and_focus()

func _on_chat_submitted(text: String) -> void:
	if flow != FlowState.CHAT_INPUT:
		return
	if not text.strip_edges().is_empty():
		Session.send_chat(text)
	_set_flow(FlowState.BROWSING)

func _on_chat_focus_exited() -> void:
	if flow == FlowState.CHAT_INPUT:
		_set_flow(FlowState.BROWSING)

func _on_chat_received(peer_id: int, text: String) -> void:
	if flow == FlowState.LEAVING or muted_ids.has(peer_id) or not Session.room.has_player(peer_id):
		return
	_bubbles[peer_id] = {"text": text, "left": BUBBLE_SECONDS}
	set_process(true)
	_refresh_view()

# Header, menu, modal ------------------------------------------------------------

func _on_back_pressed() -> void:
	if flow in [FlowState.BROWSING, FlowState.INFO_OPEN]:
		_open_modal(ModalKind.EXIT)

func _on_info_pressed() -> void:
	if not _chat_enabled():
		return
	if flow == FlowState.INFO_OPEN:
		_set_flow(FlowState.BROWSING)
	elif flow == FlowState.BROWSING:
		_set_flow(FlowState.INFO_OPEN)

func _on_copy_pressed() -> void:
	if flow != FlowState.INFO_OPEN:
		return
	# No way to detect a failed copy, so the feedback is always shown (Docs/02 §5).
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(Session.room.address)
	_copy_left = COPY_FEEDBACK_SECONDS
	copy_button.text = UiStyle.COPIED
	set_process(true)

func _on_escape() -> void:
	match flow:
		FlowState.CHAT_INPUT, FlowState.MENU_OPEN, FlowState.INFO_OPEN:
			_set_flow(FlowState.BROWSING)
		FlowState.MODAL_OPEN:
			_on_modal_cancelled()
		FlowState.BROWSING:
			if active_tab == Tab.SETTINGS and settings_view == SettingsView.MAP:
				settings_view = SettingsView.ROOM
				_rebuild_content()
				_refresh_view()

func _on_player_menu_pressed(peer_id: int) -> void:
	if flow != FlowState.BROWSING or not Session.is_host() or Session.is_offline():
		return
	menu_target_id = peer_id
	_set_flow(FlowState.MENU_OPEN)

func _on_player_action(action: int, peer_id: int) -> void:
	if flow != FlowState.MENU_OPEN or not Session.room.has_player(peer_id):
		return
	match action as PlayerAction:
		PlayerAction.MUTE:
			if muted_ids.has(peer_id):
				muted_ids.erase(peer_id)
			else:
				muted_ids[peer_id] = true
				_bubbles.erase(peer_id)
			_set_flow(FlowState.BROWSING)
		PlayerAction.PROFILE:
			_open_modal(ModalKind.PROFILE, peer_id)
		PlayerAction.KICK:
			_open_modal(ModalKind.KICK, peer_id)

func _open_modal(kind: ModalKind, target_id: int = 0) -> void:
	modal_kind = kind
	modal_target_id = target_id
	_build_modal()
	_set_flow(FlowState.MODAL_OPEN)

func _on_modal_confirmed() -> void:
	if flow != FlowState.MODAL_OPEN:
		return
	match modal_kind:
		ModalKind.EXIT:
			# Session moves to CLOSING (host with others) or MENU; _on_session_changed follows.
			Session.leave_room()
		ModalKind.KICK:
			if Session.room.has_player(modal_target_id):
				Session.kick(modal_target_id)
			_set_flow(FlowState.BROWSING)

func _on_modal_cancelled() -> void:
	if flow == FlowState.MODAL_OPEN:
		_set_flow(FlowState.BROWSING)

func _on_dimmer_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_on_modal_cancelled()

## Docs/02 §3.12. Built once when the modal opens; the profile's ready state is kept current.
func _build_modal() -> void:
	for container: Control in [modal_body, modal_buttons]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
	_profile_state_label = null
	var target := Session.room.player(modal_target_id)
	var width := PROFILE_MODAL_WIDTH if modal_kind == ModalKind.PROFILE else MODAL_WIDTH
	match modal_kind:
		ModalKind.EXIT:
			modal_title.text = UiStyle.EXIT_TITLE
			if not _is_training() and Session.is_host() and Session.room.players.size() > 1:
				modal_body.add_child(_label(UiStyle.CLOSE_ROOM_CONFIRM, 26, UiStyle.LOBBY_TEXT_DIM))
			modal_buttons.add_child(_modal_button(UiStyle.CANCEL, Color.WHITE, UiStyle.LOBBY_TEXT, _on_modal_cancelled))
			modal_buttons.add_child(_modal_button(UiStyle.LEAVE, UiStyle.LOBBY_LINE_DARK, Color.WHITE, _on_modal_confirmed))
		ModalKind.KICK:
			modal_title.text = UiStyle.KICK_TITLE % (target.display_name if target != null else "")
			modal_buttons.add_child(_modal_button(UiStyle.CANCEL, Color.WHITE, UiStyle.LOBBY_TEXT, _on_modal_cancelled))
			modal_buttons.add_child(_modal_button(UiStyle.MENU_KICK, UiStyle.LOBBY_RED, Color.WHITE, _on_modal_confirmed))
		ModalKind.PROFILE:
			modal_title.text = target.display_name if target != null else ""
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 32)
			var art := CharacterArt.new()
			art.custom_minimum_size = Vector2(PROFILE_ART_SIZE, PROFILE_ART_SIZE)
			art.pick = target.character if target != null else &""
			row.add_child(art)
			var info := VBoxContainer.new()
			info.alignment = BoxContainer.ALIGNMENT_CENTER
			info.add_theme_constant_override("separation", 12)
			info.add_child(_label(Session.catalog.character_name(art.pick), 32, UiStyle.LOBBY_TEXT, UiStyle.bold_font()))
			_profile_state_label = _label(_profile_state_text(target), 26, UiStyle.LOBBY_TEXT_DIM)
			info.add_child(_profile_state_label)
			row.add_child(info)
			modal_body.add_child(row)
			modal_buttons.add_child(_modal_button(UiStyle.CLOSE, Color.WHITE, UiStyle.LOBBY_TEXT, _on_modal_cancelled))
	var column_width := width - 2.0 * MODAL_PAD.x
	modal_title.add_theme_font_override("font", UiStyle.bold_font())
	var title_height := UiStyle.bold_font().get_multiline_string_size(modal_title.text, HORIZONTAL_ALIGNMENT_LEFT, column_width, MODAL_TITLE_FONT).y
	modal_title.custom_minimum_size = Vector2(column_width, title_height)
	modal_body.visible = modal_body.get_child_count() > 0
	modal_column.position = MODAL_PAD
	modal_column.size = Vector2(column_width, 0)
	var column_height := modal_column.get_combined_minimum_size().y
	modal_column.size = Vector2(column_width, column_height)
	modal_box.size = Vector2(width, column_height + 2.0 * MODAL_PAD.y)
	modal_box.position = (stage.size - modal_box.size) / 2.0

func _profile_state_text(target: PlayerData) -> String:
	if target == null:
		return ""
	if target.peer_id == 1:
		return UiStyle.HOST_LABEL
	return UiStyle.STATE_READY if target.is_ready else UiStyle.STATE_NOT_READY

func _modal_button(text: String, fill: Color, text_color: Color, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(170, 64)
	button.add_theme_font_override("font", UiStyle.bold_font())
	button.add_theme_font_size_override("font_size", 26)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(color_name, text_color)
	var line := UiStyle.LOBBY_LINE if fill == Color.WHITE else fill.darkened(0.2)
	_style_flat_button(button, UiStyle.box(fill, line, 4, 16))
	button.pressed.connect(handler)
	return button

func _label(text: String, font_size: int, color: Color, font: Font = null) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if font != null:
		label.add_theme_font_override("font", font)
	return label

static func _style_flat_button(button: Button, style: StyleBoxFlat) -> void:
	for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state_name, style)

# Session ------------------------------------------------------------------------

## Docs/02 §4.10.
func _on_session_changed() -> void:
	if flow == FlowState.LEAVING:
		return
	match Session.phase:
		Session.Phase.MENU:
			var notice := Session.toast
			Session.toast = ""
			_exit_to(LobbyExitResult.Route.START_GAME, notice)
			return
		Session.Phase.PLAYING:
			_exit_to(LobbyExitResult.Route.MATCH, "", Session.match_setup)
			return
		Session.Phase.CLOSING:
			if flow != FlowState.CLOSING:
				_set_flow(FlowState.CLOSING)
	if flow == FlowState.MENU_OPEN and not Session.room.has_player(menu_target_id):
		_set_flow(FlowState.BROWSING)
	if flow == FlowState.MODAL_OPEN and modal_kind in [ModalKind.KICK, ModalKind.PROFILE] and not Session.room.has_player(modal_target_id):
		_set_flow(FlowState.BROWSING)
	for peer_id: int in _bubbles.keys():
		if not Session.room.has_player(peer_id):
			_bubbles.erase(peer_id)
	if Session.room.notice != _last_notice:
		_last_notice = Session.room.notice
		_show_toast(_last_notice)
	_refresh_view()

# Drawing ------------------------------------------------------------------------

## 78° stripes, parallel to the panel's 12° slant.
func _draw_stripes() -> void:
	var height := stripes.size.y
	var step := STRIPE_SPACING / cos(deg_to_rad(LobbyGeometry.SKEW_DEG))
	var points := PackedVector2Array()
	var x := -LobbyGeometry.TAN * height
	while x < stripes.size.x:
		points.append(Vector2(x, 0))
		points.append(Vector2(x + LobbyGeometry.TAN * height, height))
		x += step
	stripes.draw_multiline(points, STRIPE_COLOR, STRIPE_WIDTH)

func _draw_portrait_shadow() -> void:
	var half := portrait_shadow.size / 2.0
	var points := PackedVector2Array()
	for index in range(32):
		var angle := TAU * index / 32.0
		points.append(half + Vector2(cos(angle) * half.x, sin(angle) * half.y))
	portrait_shadow.draw_colored_polygon(points, PORTRAIT_SHADOW_COLOR)

func _draw_my_card() -> void:
	var outline := _my_card_outline()
	var shadow := PackedVector2Array()
	for point in outline:
		shadow.append(point + MY_CARD_SHADOW_OFFSET)
	my_card_shape.draw_colored_polygon(shadow, MY_CARD_SHADOW_COLOR)
	my_card_shape.draw_colored_polygon(outline, Color.WHITE)
	my_card_shape.draw_polyline(LobbyGeometry.closed(outline), UiStyle.LOBBY_LINE, MY_CARD_BORDER, true)

## (−20,0) → (572,48) → quadratic curve (control (592,50)) → (592,70) → (592,226) → (−20,226).
func _my_card_outline() -> PackedVector2Array:
	var points := PackedVector2Array([MY_CARD_START, MY_CARD_CURVE[0]])
	for step in range(1, 9):
		var t := step / 8.0
		points.append(MY_CARD_CURVE[0].lerp(MY_CARD_CURVE[1], t).lerp(MY_CARD_CURVE[1].lerp(MY_CARD_CURVE[2], t), t))
	points.append(Vector2(MY_CARD_CURVE[2].x, MY_CARD_BOTTOM))
	points.append(Vector2(MY_CARD_START.x, MY_CARD_BOTTOM))
	return points

## Docs/02 §3.11: red → green as participants get ready.
func _draw_ready_arrow() -> void:
	var t := _ready_ratio()
	var line := UiStyle.LOBBY_RED.lerp(UiStyle.LOBBY_GREEN, t)
	var points := PackedVector2Array(ARROW_POINTS)
	ready_arrow.draw_colored_polygon(points, UiStyle.LOBBY_RED_BG.lerp(UiStyle.LOBBY_GREEN_BG, t))
	ready_arrow.draw_polyline(LobbyGeometry.closed(points), line, ARROW_BORDER, true)
	for point in points:
		ready_arrow.draw_circle(point, ARROW_BORDER / 2.0, line)
