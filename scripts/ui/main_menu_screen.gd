class_name MainMenuScreen
extends Control
## Main menu from the Figma mock "S1 Main Menu" (1920x1080, 2026-11-05). The art is laid out in
## 1920x1080 design units under Canvas and scaled to fit the window. Keyboard: ↑/↓ move the
## selection, Enter confirms, Esc closes the game. Mouse: hover selects, click confirms.
## 가이드북 / 설정 have no screen yet, so they can be selected but not confirmed.
## When the game starts, the GFIGHT title slides up and the photo slides in from the right
## (Figma prototype motion, played once per launch instead of looping).

signal exit_requested(result: MainMenuExitResult)

enum Item { PLAY, GUIDEBOOK, SETTINGS }

const DESIGN_SIZE := Vector2(1920.0, 1080.0)

## Intro motion in design units / seconds, from the Figma prototype (2 s timeline):
## title y +89 → -25 over 0–30.05 % linear, photo x +200 → 0 over 0–29.58 % ease-out.
@export var intro_title_from_y: float = 89.0
@export var intro_title_to_y: float = -25.0
@export var intro_title_duration: float = 0.601
@export var intro_photo_from_x: float = 200.0
@export var intro_photo_duration: float = 0.592

## The intro plays only the first time the menu opens after launch.
static var _intro_played: bool = false

var selected: Item = Item.PLAY
var _leaving: bool = false
var _items: Array[Control] = []
var _ko_labels: Array[Label] = []
var _intro: Tween
var _title_rest: Vector2
var _photo_rest: Vector2

@onready var canvas: Control = %Canvas
@onready var hint_corner: Control = %HintCorner
@onready var title_label: Label = %TitleLabel
@onready var selected_wedge: TextureRect = %SelectedWedge
@onready var play_item: Control = %PlayItem
@onready var guidebook_item: Control = %GuidebookItem
@onready var settings_item: Control = %SettingsItem
@onready var hint_title: Label = %HintTitle
@onready var hint_sub: Label = %HintSub
@onready var title_art: Control = %TitleArt
@onready var player_photo: TextureRect = %PlayerPhoto

func _ready() -> void:
	_items = [play_item, guidebook_item, settings_item]
	_ko_labels = [%PlayKoLabel, %GuidebookKoLabel, %SettingsKoLabel]
	title_label.text = UiStyle.MAIN_TITLE_ART
	_set_word(play_item, UiStyle.MAIN_ITEM_PLAY)
	_set_word(guidebook_item, UiStyle.MAIN_ITEM_GUIDEBOOK)
	_set_word(settings_item, UiStyle.MAIN_ITEM_SETTINGS)
	_ko_labels[Item.PLAY].text = UiStyle.MENU_PLAY
	_ko_labels[Item.GUIDEBOOK].text = UiStyle.MENU_GUIDEBOOK
	_ko_labels[Item.SETTINGS].text = UiStyle.MENU_SETTINGS
	%EnterKey.text = UiStyle.MAIN_KEY_ENTER
	%EnterAction.text = UiStyle.MAIN_KEY_CONFIRM
	%EscKey.text = UiStyle.MAIN_KEY_ESC
	%EscAction.text = UiStyle.MAIN_KEY_CLOSE
	for index in range(_items.size()):
		var word := _word(_items[index])
		word.mouse_entered.connect(select.bind(index))
		word.gui_input.connect(_on_word_gui_input.bind(index))
	resized.connect(_fit_canvas)
	_fit_canvas()
	select(Item.PLAY)
	_title_rest = title_art.position + Vector2(0.0, intro_title_to_y)
	_photo_rest = player_photo.position
	if _intro_played:
		skip_intro()
	else:
		_intro_played = true
		_play_intro()

func enter(_data: RefCounted) -> void:
	_leaving = false

func _unhandled_input(event: InputEvent) -> void:
	# Confirming can remove this screen from the tree, so keep the viewport first.
	var viewport := get_viewport()
	if event.is_action_pressed(&"ui_up", true):
		select(wrapi(selected - 1, 0, _items.size()))
	elif event.is_action_pressed(&"ui_down", true):
		select(wrapi(selected + 1, 0, _items.size()))
	elif event.is_action_pressed(&"ui_accept"):
		confirm()
	elif event.is_action_pressed(&"ui_cancel"):
		get_tree().quit()
	else:
		return
	viewport.set_input_as_handled()

## Moves the highlight (black wedge, white word, yellow last letter) and the bottom-right hint.
func select(item: int) -> void:
	if item < 0 or item >= _items.size():
		push_warning("Main menu item %d does not exist" % item)
		return
	selected = item as Item
	for index in range(_items.size()):
		var is_selected := index == selected
		var word := _word(_items[index])
		var body := word.get_node("Body") as Label
		var last := word.get_node("Last") as Label
		body.add_theme_color_override("font_color", UiStyle.MAIN_SELECTED_TEXT if is_selected else UiStyle.MAIN_BROWN)
		last.add_theme_color_override("font_color", UiStyle.MAIN_YELLOW if is_selected else UiStyle.MAIN_BROWN)
		_ko_labels[index].add_theme_color_override("font_color", UiStyle.MAIN_INK if is_selected else UiStyle.MAIN_BROWN)
	match selected:
		Item.PLAY:
			hint_title.text = UiStyle.MAIN_HINT_PLAY
			hint_sub.text = UiStyle.MAIN_HINT_PLAY_SUB
		Item.GUIDEBOOK:
			hint_title.text = UiStyle.MAIN_HINT_GUIDEBOOK
			hint_sub.text = UiStyle.MAIN_HINT_SOON_SUB % UiStyle.MENU_GUIDEBOOK
		Item.SETTINGS:
			hint_title.text = UiStyle.MAIN_HINT_SETTINGS
			hint_sub.text = UiStyle.MAIN_HINT_SOON_SUB % UiStyle.MENU_SETTINGS
	# Word sizes are known only after the containers lay out.
	_place_wedge.call_deferred()

## Enter / click on the selected item. Only PLAY leads anywhere for now.
func confirm() -> void:
	if _leaving or selected != Item.PLAY:
		return
	_leaving = true
	exit_requested.emit(MainMenuExitResult.new())

## Jumps the intro to its last frame (screenshots, returning to the menu).
func skip_intro() -> void:
	if _intro != null and _intro.is_valid():
		_intro.kill()
	title_art.position = _title_rest
	player_photo.position = _photo_rest

func is_item_available(item: int) -> bool:
	return item == Item.PLAY

## Text of an item's English word, for tests and screenshots.
func item_text(item: int) -> String:
	var word := _word(_items[item])
	return (word.get_node("Body") as Label).text + (word.get_node("Last") as Label).text

func _on_word_gui_input(event: InputEvent, item: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	select(item)
	confirm()
	accept_event()

## The wedge art is drawn for PLAY; for other items it is moved and stretched to their word.
func _place_wedge() -> void:
	if not is_inside_tree():
		return
	var base_size := _word(play_item).size
	var target := _items[selected]
	var target_size := _word(target).size
	if is_zero_approx(base_size.x) or is_zero_approx(base_size.y):
		return
	selected_wedge.pivot_offset = play_item.position
	selected_wedge.position = target.position - play_item.position
	selected_wedge.scale = Vector2(target_size.x / base_size.x, target_size.y / base_size.y)

func _play_intro() -> void:
	title_art.position = _title_rest + Vector2(0.0, intro_title_from_y - intro_title_to_y)
	player_photo.position = _photo_rest + Vector2(intro_photo_from_x, 0.0)
	_intro = create_tween().set_parallel(true)
	_intro.tween_property(title_art, "position", _title_rest, intro_title_duration)
	_intro.tween_property(player_photo, "position", _photo_rest, intro_photo_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _fit_canvas() -> void:
	var fit := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	if fit <= 0.0:
		return
	canvas.scale = Vector2(fit, fit)
	canvas.position = Vector2(0.0, (size.y - DESIGN_SIZE.y * fit) * 0.5)
	hint_corner.scale = Vector2(fit, fit)

func _set_word(item: Control, text: String) -> void:
	var word := _word(item)
	(word.get_node("Body") as Label).text = text.left(-1)
	(word.get_node("Last") as Label).text = text.right(1)

func _word(item: Control) -> HBoxContainer:
	return item.get_node("Word") as HBoxContainer
