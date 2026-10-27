class_name PlayerList
extends Control
## [방] tab (Docs/02 §3.7): one slanted card per other player, stacked in slot order.
## Display only: clicks are reported with signals and LobbyScreen decides.

signal menu_pressed(peer_id: int)
signal action_chosen(action: int, peer_id: int)

const CARD_GAP: float = 14.0
const CARD_RADIUS: float = 16.0
const CARD_BORDER: float = 4.0
const ART_RATIO: float = 0.7
const ART_MAX: float = 400.0
const NICK_RATIO: float = 0.15
const NICK_MIN: float = 44.0
const NICK_MAX: float = 80.0
const CHARACTER_FONT: int = 22
const MENU_BUTTON_SIZE := Vector2(80, 42)
const MENU_WIDTH: float = 280.0
const BUBBLE_ANCHOR := Vector2(0.74, -0.26)
## Action ids match LobbyScreen.PlayerAction.
const ACTION_PROFILE: int = 0
const ACTION_MUTE: int = 1
const ACTION_KICK: int = 2

var _menu_panel: Control

@onready var card_layer: Control = %CardLayer

## Rebuilds every card. bubbles: peer id -> text currently shown.
func refresh(room: RoomState, my_id: int, i_am_host: bool, online: bool, muted: Dictionary, bubbles: Dictionary, menu_target: int) -> void:
	for child in card_layer.get_children():
		card_layer.remove_child(child)
		child.queue_free()
	_menu_panel = null
	var others: Array[PlayerData] = []
	for entry in room.players:
		if entry.peer_id != my_id:
			others.append(entry)
	if others.is_empty():
		_build_empty(online)
		return
	var count := others.size()
	var card_h := (LobbyGeometry.PANEL_INNER_H - CARD_GAP * (count - 1)) / count
	for index in range(count):
		var top := LobbyGeometry.PANEL_PAD_Y + index * (card_h + CARD_GAP)
		var entry := others[index]
		var card := _build_card(entry, card_h, i_am_host, muted.has(entry.peer_id), str(bubbles.get(entry.peer_id, "")))
		card.position = Vector2(LobbyGeometry.PANEL_BORDER + LobbyGeometry.PANEL_PAD + LobbyGeometry.TAN * top, top)
		card_layer.add_child(card)
		if entry.peer_id == menu_target and i_am_host:
			card.z_index = 10
			_menu_panel = _build_menu(entry.peer_id, muted.has(entry.peer_id))
			_menu_panel.position = Vector2(LobbyGeometry.PANEL_INNER_W - 28.0 - MENU_WIDTH + LobbyGeometry.TAN * 64.0, 64.0)
			card.add_child(_menu_panel)

## Global rect of the open ⋯ menu, or an empty rect.
func menu_rect() -> Rect2:
	return _menu_panel.get_global_rect() if is_instance_valid(_menu_panel) else Rect2()

func _build_card(entry: PlayerData, card_h: float, i_am_host: bool, is_muted: bool, bubble_text: String) -> SlantBox:
	var card := SlantBox.new()
	card.size = Vector2(LobbyGeometry.PANEL_INNER_W, card_h)
	card.fill = Color.WHITE
	card.border_color = UiStyle.LOBBY_LINE_DARK
	card.border_width = CARD_BORDER
	card.corner_radius = CARD_RADIUS
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art_size := minf(card_h * ART_RATIO, ART_MAX)
	var art := CharacterArt.new()
	art.pick = entry.character
	art.size = Vector2(art_size, art_size)
	art.position = Vector2((card.size.x - art_size) / 2.0 + LobbyGeometry.TAN * card_h / 2.0, (card_h - art_size) / 2.0)
	card.add_child(art)
	var nick_size := clampf(card_h * NICK_RATIO, NICK_MIN, NICK_MAX)
	var character_y := card_h - 20.0 - CHARACTER_FONT * 1.3
	var nick_y := character_y - nick_size * 1.25
	var nick := _label(entry.display_name, int(nick_size), UiStyle.LOBBY_TEXT, UiStyle.bold_font(1.0))
	nick.position = Vector2(36.0 + LobbyGeometry.TAN * nick_y, nick_y)
	card.add_child(nick)
	if entry.peer_id == 1:
		var star_size := nick_size * 0.72
		var nick_width := UiStyle.bold_font(1.0).get_string_size(entry.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(nick_size)).x
		var star := _icon(LobbyIcons.Kind.STAR, star_size, UiStyle.LOBBY_GOLD)
		star.position = nick.position + Vector2(nick_width + 10.0, (nick_size * 1.25 - star_size) / 2.0)
		card.add_child(star)
	var character := _label(Session.catalog.character_name(entry.character), CHARACTER_FONT, UiStyle.LOBBY_TEXT_DIM)
	character.position = Vector2(36.0 + LobbyGeometry.TAN * character_y, character_y)
	card.add_child(character)
	if is_muted:
		var mute := _icon(LobbyIcons.Kind.MUTE, 28.0, UiStyle.LOBBY_TEXT_DIM)
		var character_width := ThemeDB.fallback_font.get_string_size(character.text, HORIZONTAL_ALIGNMENT_LEFT, -1, CHARACTER_FONT).x
		mute.position = character.position + Vector2(character_width + 10.0, 0.0)
		card.add_child(mute)
	var mark_size := maxf(56.0, nick_size * 1.1)
	var mark_y := card_h - 16.0 - mark_size
	var mark_x := card.size.x - 40.0 - mark_size + LobbyGeometry.TAN * mark_y
	if entry.peer_id == 1:
		var host_label := _label(UiStyle.HOST_LABEL, int(mark_size * 0.6), UiStyle.LOBBY_GOLD, UiStyle.bold_font(1.0))
		host_label.position = Vector2(mark_x - mark_size * 0.4, mark_y + mark_size * 0.1)
		card.add_child(host_label)
	else:
		var mark := _icon(LobbyIcons.Kind.O if entry.is_ready else LobbyIcons.Kind.X, mark_size, UiStyle.LOBBY_GREEN if entry.is_ready else UiStyle.LOBBY_RED)
		mark.position = Vector2(mark_x, mark_y)
		card.add_child(mark)
	var menu_button := Button.new()
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.icon = LobbyIcons.texture(LobbyIcons.Kind.DOTS)
	menu_button.expand_icon = true
	menu_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_button.add_theme_color_override("icon_normal_color", UiStyle.LOBBY_LINE_DARK)
	menu_button.add_theme_color_override("icon_hover_color", UiStyle.LOBBY_LINE_DARK)
	menu_button.add_theme_color_override("icon_pressed_color", UiStyle.LOBBY_LINE_DARK)
	menu_button.add_theme_color_override("icon_disabled_color", UiStyle.LOBBY_LINE_DARK)
	for state_name in ["normal", "hover", "pressed", "disabled"]:
		menu_button.add_theme_stylebox_override(state_name, _flat_box(UiStyle.LOBBY_CARD, UiStyle.LOBBY_LINE, 3, 14))
	menu_button.size = MENU_BUTTON_SIZE
	menu_button.position = Vector2(card.size.x - 28.0 - MENU_BUTTON_SIZE.x + LobbyGeometry.TAN * 16.0, 16.0)
	menu_button.disabled = not i_am_host
	if not i_am_host:
		menu_button.modulate.a = 0.35
		menu_button.tooltip_text = UiStyle.HOST_ONLY
	var target := entry.peer_id
	menu_button.pressed.connect(func() -> void: menu_pressed.emit(target))
	card.add_child(menu_button)
	if not bubble_text.is_empty():
		var bubble := BubbleView.new()
		bubble.z_index = 5
		card.add_child(bubble)
		# Docs anchor (74%, −26% of the art); kept inside the card so the top card's bubble is not clipped.
		var anchor := art.position + art.size * BUBBLE_ANCHOR
		anchor.y = maxf(anchor.y, BubbleView.HEIGHT + BubbleView.TAIL_HEIGHT + 12.0)
		bubble.show_text(bubble_text, anchor)
	return card

func _build_menu(peer_id: int, is_muted: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = MENU_WIDTH
	panel.add_theme_stylebox_override("panel", _flat_box(Color.WHITE, UiStyle.LOBBY_LINE, 4, 14))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	column.add_child(_menu_item(UiStyle.MENU_PROFILE, UiStyle.LOBBY_TEXT, ACTION_PROFILE, peer_id))
	column.add_child(_menu_item(UiStyle.MENU_UNMUTE if is_muted else UiStyle.MENU_MUTE, UiStyle.LOBBY_TEXT, ACTION_MUTE, peer_id))
	column.add_child(HSeparator.new())
	column.add_child(_menu_item(UiStyle.MENU_KICK, UiStyle.LOBBY_RED, ACTION_KICK, peer_id))
	return panel

func _menu_item(text: String, color: Color, action: int, peer_id: int) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 52
	button.add_theme_font_size_override("font_size", 24)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(color_name, color)
	button.pressed.connect(func() -> void: action_chosen.emit(action, peer_id))
	return button

func _build_empty(online: bool) -> void:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = Vector2(LobbyGeometry.PANEL_BORDER + LobbyGeometry.PANEL_PAD, LobbyGeometry.PANEL_PAD_Y)
	box.size = Vector2(LobbyGeometry.PANEL_INNER_W, LobbyGeometry.PANEL_INNER_H)
	box.draw.connect(func() -> void:
		var outline := LobbyGeometry.skewed(LobbyGeometry.rounded_rect(Rect2(Vector2.ZERO, box.size), CARD_RADIUS), 0.0)
		SelectTile.draw_dashed_outline(box, outline, Color(1, 1, 1, 0.5), 4.0, 16.0, 10.0))
	card_layer.add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.position = Vector2(LobbyGeometry.TAN * box.size.y / 2.0, 0)
	column.size = box.size
	box.add_child(column)
	var title := _label(UiStyle.INVITE_WAITING if online else UiStyle.TRAINING_ALONE, 40, Color.WHITE, UiStyle.bold_font())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	if online:
		var hint := _label(UiStyle.INVITE_HINT, 24, Color(1, 1, 1, 0.7))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(hint)

func _label(text: String, font_size: int, color: Color, font: Font = null) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if font != null:
		label.add_theme_font_override("font", font)
	return label

func _icon(kind: LobbyIcons.Kind, icon_size: float, color: Color) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = LobbyIcons.texture(kind)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size = Vector2(icon_size, icon_size)
	rect.self_modulate = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

static func _flat_box(color: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := UiStyle.box(color, border, width, radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style
