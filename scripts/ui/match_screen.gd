class_name MatchScreen
extends Control
## Match HUD (S3) and result (S4) over Session.arena. No Docs spec yet, so this keeps the
## existing flow: countdown, play, result after a short pause, Enter to confirm, back to lobby.
## Training uses the same flow; the arena adds the dummy (Docs/02 decision 8: no cheats yet).

signal exit_requested(result: MatchExitResult)

## [제안] Pause on the final ring-out before S4 appears.
@export var result_delay: float = 0.8
## [제안] Short fade when the match screen opens.
@export var fade_seconds: float = 0.2

var _result_wait: float = 0.0
var _leaving: bool = false

@onready var hud: MatchHud = %Hud
@onready var result_panel: ResultScreen = %ResultPanel
@onready var fade: ColorRect = %Fade

func enter(_data: RefCounted) -> void:
	_leaving = false
	_result_wait = 0.0
	if not Session.changed.is_connected(_on_session_changed):
		Session.changed.connect(_on_session_changed)
	if fade_seconds > 0.0:
		fade.color.a = 1.0
		create_tween().tween_property(fade, "color:a", 0.0, fade_seconds)
	_refresh()

func _process(delta: float) -> void:
	if Session.phase == Session.Phase.RESULT and not result_panel.visible:
		_result_wait += delta
		if _result_wait >= result_delay:
			result_panel.visible = true
			_refresh()

func _physics_process(_delta: float) -> void:
	if Session.phase == Session.Phase.PLAYING and not Session.local_mode:
		Session.submit_local_input(Fighter.read_keyboard([KEY_A, KEY_D, KEY_W, KEY_J], KEY_S))

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.alt_pressed:
		return
	if key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER] and result_panel.visible:
		# Confirming can return to the lobby at once, which removes this screen.
		get_viewport().set_input_as_handled()
		Session.confirm_result()

func _on_session_changed() -> void:
	if _leaving:
		return
	if Session.phase == Session.Phase.LOBBY:
		_leaving = true
		var result := MatchExitResult.new()
		result.route = MatchExitResult.Route.LOBBY
		exit_requested.emit(result)
		return
	_refresh()

func _refresh() -> void:
	if Session.phase != Session.Phase.RESULT:
		result_panel.visible = false
		_result_wait = 0.0
	hud.visible = Session.phase in [Session.Phase.PLAYING, Session.Phase.RESULT] and not result_panel.visible
	if result_panel.visible:
		result_panel.refresh()
