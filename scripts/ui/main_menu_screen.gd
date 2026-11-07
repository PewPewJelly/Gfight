class_name MainMenuScreen
extends Control
## Main menu from the Figma mock "S1 Main Menu" (1920x1080, 2026-11-05). The art is laid out in
## 1920x1080 design units under Canvas and scaled to fit the window. Keyboard: ↑/↓ move the
## selection, Enter confirms, Esc closes the game. Mouse: hover selects, click confirms.
## 가이드북 / 설정 have no screen yet, so they can be selected but not confirmed.
## Confirming PLAY opens the PLAY submenu (Figma "S1 Main Menu - Play state"): ONLINE and
## TRAINING, each in its own torn hole above and right of PLAY. ↑/↓ move between them, Enter
## confirms, Esc closes the submenu. ONLINE opens the temporary online screen; TRAINING opens
## the training lobby directly.
## When the game starts, the GFIGHT title slides up and the photo slides in from the right
## (Figma prototype motion, played once per launch instead of looping).
## Every time an item is selected, the black wedge grows up from its base line behind the word
## and a yellow slanted band sweeps through the word (only inside the letters), leaving the
## last letter yellow.

signal exit_requested(result: MainMenuExitResult)

enum Item { PLAY, GUIDEBOOK, SETTINGS }
enum PlayItem { ONLINE, TRAINING }

const DESIGN_SIZE := Vector2(1920.0, 1080.0)
const SWEEP_SHADER: Shader = preload("res://resources/shaders/menu_sweep.gdshader")
const NO_BAND: float = -100000.0
## Base line of the wedge in selected_wedge.svg (design units); the wedge grows up from it.
const WEDGE_BASE_Y: float = 590.0

## Intro motion in design units / seconds, from the Figma prototype (2 s timeline):
## title y +89 → -25 over 0–30.05 % linear, photo x +200 → 0 over 0–29.58 % ease-out.
@export var intro_title_from_y: float = 89.0
@export var intro_title_to_y: float = -25.0
@export var intro_title_duration: float = 0.601
@export var intro_photo_from_x: float = 200.0
@export var intro_photo_duration: float = 0.592

## Selection band sweep (design units / seconds). The reference GIF took about 0.3 s; this
## is faster on purpose.
@export var sweep_duration: float = 0.15
@export var sweep_half_width: float = 22.0
@export var sweep_slant: float = 0.6
## Wedge grow on selection (reference GIF: about 3 frames at 30 ms).
@export var wedge_grow_duration: float = 0.09

## PLAY submenu. The Figma mock is a still frame, so the opening motion is provisional: each
## hole pops from a smaller size while fading in, the second slightly after the first.
@export var submenu_pop_duration: float = 0.12
@export var submenu_pop_from_scale: float = 0.85
@export var submenu_pop_stagger: float = 0.04
## GUIDEBOOK / SETTINGS opacity while the submenu is open (Figma: 35 %).
@export var submenu_dim_alpha: float = 0.35

## The intro plays only the first time the menu opens after launch.
static var _intro_played: bool = false

var selected: Item = Item.PLAY
var _leaving: bool = false
var _items: Array[Control] = []
var _ko_labels: Array[Label] = []
var _intro: Tween
var _title_rest: Vector2
var _photo_rest: Vector2
var _has_selection: bool = false
var _wedge_scale: Vector2 = Vector2.ONE
var _wedge_target: Vector2 = Vector2.ZERO
var _sweep: Tween
var _sweep_item: int = -1
var _sweep_delay: float = 0.0
var play_menu_open: bool = false
var play_selected: PlayItem = PlayItem.ONLINE
var _holes: Array[Control] = []
var _submenu_tween: Tween

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
@onready var play_submenu: Control = %PlaySubmenu
@onready var online_hole: Control = %OnlineHole
@onready var training_hole: Control = %TrainingHole
@onready var esc_action: Label = %EscAction

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
	esc_action.text = UiStyle.MAIN_KEY_CLOSE
	_holes = [online_hole, training_hole]
	_hole_word(PlayItem.ONLINE).text = UiStyle.MAIN_ITEM_ONLINE
	_hole_word(PlayItem.TRAINING).text = UiStyle.MAIN_ITEM_TRAINING
	(online_hole.get_node("Face/Ko") as Label).text = UiStyle.MENU_ONLINE
	(training_hole.get_node("Face/Ko") as Label).text = UiStyle.MODE_TRAINING
	for index in range(_holes.size()):
		var face := _holes[index].get_node("Face") as Control
		var hit := face.get_node("HitArea") as Control
		# The hole pops around its own centre.
		_holes[index].pivot_offset = face.get_transform() * (hit.position + hit.size * 0.5)
		hit.mouse_entered.connect(_on_hole_mouse_entered.bind(index))
		hit.gui_input.connect(_on_hole_gui_input.bind(index))
	for index in range(_items.size()):
		var word := _word(_items[index])
		word.mouse_entered.connect(_on_word_mouse_entered.bind(index))
		word.gui_input.connect(_on_word_gui_input.bind(index))
		for label_name in ["Body", "Last"]:
			var material := ShaderMaterial.new()
			material.shader = SWEEP_SHADER
			material.set_shader_parameter("band_color", UiStyle.MAIN_YELLOW)
			material.set_shader_parameter("band_half_width", sweep_half_width)
			material.set_shader_parameter("slant", sweep_slant)
			material.set_shader_parameter("keep_passed", label_name == "Last")
			(word.get_node(label_name) as Label).material = material
	resized.connect(_fit_canvas)
	_fit_canvas()
	_title_rest = title_art.position + Vector2(0.0, intro_title_to_y)
	_photo_rest = player_photo.position
	var play_intro := not _intro_played
	# PLAY is selected from the start; its sweep waits until the title has risen.
	_sweep_delay = intro_title_duration if play_intro else 0.0
	select(Item.PLAY)
	if play_intro:
		_intro_played = true
		_play_intro()
	else:
		skip_intro()

## data: MainMenuEnterData or null. Coming back from the online screen or the training lobby
## reopens the PLAY submenu on the mode the player left from.
func enter(data: RefCounted) -> void:
	_leaving = false
	var menu_data := data as MainMenuEnterData
	if menu_data != null and menu_data.open_play_menu:
		skip_intro()
		_end_sweep()
		open_play_menu(menu_data.play_item, false)

func _unhandled_input(event: InputEvent) -> void:
	# Confirming can remove this screen from the tree, so keep the viewport first.
	var viewport := get_viewport()
	if play_menu_open:
		if event.is_action_pressed(&"ui_up", true):
			select_mode(wrapi(play_selected - 1, 0, _holes.size()))
		elif event.is_action_pressed(&"ui_down", true):
			select_mode(wrapi(play_selected + 1, 0, _holes.size()))
		elif event.is_action_pressed(&"ui_accept"):
			confirm_mode()
		elif event.is_action_pressed(&"ui_cancel"):
			close_play_menu()
		else:
			return
		viewport.set_input_as_handled()
		return
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
	if _has_selection and item == selected:
		return
	if play_menu_open:
		close_play_menu()
	_has_selection = true
	_end_sweep()
	selected = item as Item
	_sweep_item = selected
	# Word sizes are known only after the containers lay out.
	_run_sweep.call_deferred(selected)
	_apply_colors()
	_update_hint()

## Enter / click on the selected item. Only PLAY leads anywhere for now: it opens the submenu.
func confirm() -> void:
	if _leaving or selected != Item.PLAY:
		return
	open_play_menu()

## Shows ONLINE / TRAINING next to PLAY and dims GUIDEBOOK / SETTINGS.
func open_play_menu(item: int = PlayItem.ONLINE, animate: bool = true) -> void:
	if play_menu_open:
		return
	play_menu_open = true
	play_submenu.visible = true
	_apply_submenu_dim()
	select_mode(item)
	_update_hint()
	if animate:
		_pop_holes()

func close_play_menu() -> void:
	if not play_menu_open:
		return
	play_menu_open = false
	if _submenu_tween != null and _submenu_tween.is_valid():
		_submenu_tween.kill()
	for hole in _holes:
		hole.scale = Vector2.ONE
		hole.modulate.a = 1.0
	play_submenu.visible = false
	_apply_submenu_dim()
	_update_hint()

## Moves the submenu highlight (yellow word + ▶ marker).
func select_mode(item: int) -> void:
	if item < 0 or item >= _holes.size():
		push_warning("PLAY submenu item %d does not exist" % item)
		return
	play_selected = item as PlayItem
	for index in range(_holes.size()):
		var is_selected := index == play_selected
		_hole_word(index).add_theme_color_override("font_color", UiStyle.MAIN_YELLOW if is_selected else UiStyle.MAIN_SELECTED_TEXT)
		(_holes[index].get_node("Face/Marker") as CanvasItem).visible = is_selected

## Enter / click on the selected submenu mode.
func confirm_mode() -> void:
	if _leaving or not play_menu_open:
		return
	_leaving = true
	var result := MainMenuExitResult.new()
	if play_selected == PlayItem.TRAINING:
		Session.start_training()
		result.route = MainMenuExitResult.Route.TRAINING
	else:
		result.route = MainMenuExitResult.Route.ONLINE
	exit_requested.emit(result)

## Text of a submenu mode's English word, for tests and screenshots.
func mode_text(item: int) -> String:
	return _hole_word(item).text

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

func _on_word_mouse_entered(item: int) -> void:
	# While the submenu is open the dimmed items do not follow the mouse.
	if not play_menu_open:
		select(item)

func _on_word_gui_input(event: InputEvent, item: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if play_menu_open:
		# Clicking PLAY again closes the submenu; clicking another item moves to it.
		close_play_menu()
		select(item)
		return
	select(item)
	confirm()

func _on_hole_mouse_entered(item: int) -> void:
	if play_menu_open and not _leaving:
		select_mode(item)

func _on_hole_gui_input(event: InputEvent, item: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if not play_menu_open:
		return
	select_mode(item)
	confirm_mode()

func _update_hint() -> void:
	esc_action.text = UiStyle.MAIN_KEY_BACK if play_menu_open else UiStyle.MAIN_KEY_CLOSE
	if play_menu_open:
		hint_title.text = UiStyle.MAIN_HINT_CHOOSE
		hint_sub.text = UiStyle.MAIN_HINT_CHOOSE_SUB
		return
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

func _apply_submenu_dim() -> void:
	var alpha := submenu_dim_alpha if play_menu_open else 1.0
	for item in [Item.GUIDEBOOK, Item.SETTINGS]:
		_items[item].modulate.a = alpha
		_ko_labels[item].modulate.a = alpha

func _pop_holes() -> void:
	if _submenu_tween != null and _submenu_tween.is_valid():
		_submenu_tween.kill()
	_submenu_tween = create_tween().set_parallel(true)
	for index in range(_holes.size()):
		var hole := _holes[index]
		var delay := submenu_pop_stagger * index
		hole.scale = Vector2.ONE * submenu_pop_from_scale
		hole.modulate.a = 0.0
		_submenu_tween.tween_property(hole, "scale", Vector2.ONE, submenu_pop_duration) \
			.set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_submenu_tween.tween_property(hole, "modulate:a", 1.0, submenu_pop_duration * 0.5).set_delay(delay)

func _hole_word(item: int) -> Label:
	return _holes[item].get_node("Face/Word") as Label

## The wedge art is drawn for PLAY; for other items it is moved and stretched to their word.
func _aim_wedge(item: int) -> void:
	var base_size := _word(play_item).size
	var target_size := _word(_items[item]).size
	if is_zero_approx(base_size.x) or is_zero_approx(base_size.y):
		return
	_wedge_scale = Vector2(target_size.x / base_size.x, target_size.y / base_size.y)
	_wedge_target = _items[item].position
	selected_wedge.pivot_offset = Vector2(play_item.position.x, WEDGE_BASE_Y)

## grow 0 = flat on its base line, 1 = full wedge for the aimed item. The base line stays put.
func _set_wedge_grow(grow: float) -> void:
	var pivot := selected_wedge.pivot_offset
	selected_wedge.scale = Vector2(_wedge_scale.x, _wedge_scale.y * grow)
	selected_wedge.position = _wedge_target - pivot + _wedge_scale * (pivot - play_item.position)

func _apply_colors() -> void:
	for index in range(_items.size()):
		var is_selected := index == selected
		var word := _word(_items[index])
		var body := word.get_node("Body") as Label
		var last := word.get_node("Last") as Label
		var last_color := UiStyle.MAIN_BROWN
		if is_selected:
			# While the band runs, the last letter starts white and the band paints it yellow.
			last_color = UiStyle.MAIN_SELECTED_TEXT if index == _sweep_item else UiStyle.MAIN_YELLOW
		body.add_theme_color_override("font_color", UiStyle.MAIN_SELECTED_TEXT if is_selected else UiStyle.MAIN_BROWN)
		last.add_theme_color_override("font_color", last_color)
		_ko_labels[index].add_theme_color_override("font_color", UiStyle.MAIN_INK if is_selected else UiStyle.MAIN_BROWN)

func _run_sweep(item: int) -> void:
	if _sweep_item != item or not is_inside_tree():
		return
	var word := _word(_items[item])
	var last := word.get_node("Last") as Label
	(last.material as ShaderMaterial).set_shader_parameter("offset_x", last.position.x)
	var start := -sweep_half_width - word.size.y * sweep_slant
	var finish := word.size.x + sweep_half_width
	_set_band(start, item)
	_aim_wedge(item)
	_set_wedge_grow(0.0)
	_sweep = create_tween()
	if _sweep_delay > 0.0:
		_sweep.tween_interval(_sweep_delay)
		_sweep_delay = 0.0
	_sweep.tween_method(_set_wedge_grow, 0.0, 1.0, wedge_grow_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_sweep.parallel().tween_method(_set_band.bind(item), start, finish, sweep_duration)
	_sweep.finished.connect(_end_sweep)

func _set_band(band_pos: float, item: int) -> void:
	var word := _word(_items[item])
	for label_name in ["Body", "Last"]:
		((word.get_node(label_name) as Label).material as ShaderMaterial).set_shader_parameter("band_pos", band_pos)

## Stops the band (finished or interrupted) and leaves the word in its resting colors.
func _end_sweep() -> void:
	if _sweep != null and _sweep.is_valid():
		_sweep.kill()
	if _sweep_item == -1:
		return
	_set_band(NO_BAND, _sweep_item)
	_aim_wedge(_sweep_item)
	_set_wedge_grow(1.0)
	_sweep_item = -1
	_apply_colors()

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
