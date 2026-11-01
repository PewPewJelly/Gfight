class_name MainMenuScreen
extends Control
## Main menu. SYS-00 is not written yet: buttons follow Docs/01 decision 1
## ([게임하기][가이드북][설정]); 가이드북/설정 have no screen yet, 게임 종료 stays as before.

signal exit_requested(result: MainMenuExitResult)

var _leaving: bool = false

@onready var menu_panel: PanelContainer = %MenuPanel
@onready var title_label: Label = %TitleLabel
@onready var play_button: Button = %PlayButton
@onready var guidebook_button: Button = %GuidebookButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var version_label: Label = %VersionLabel

func _ready() -> void:
	menu_panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.TEXT_DIM, 1, 14))
	title_label.text = UiStyle.TITLE
	play_button.text = UiStyle.MENU_PLAY
	guidebook_button.text = UiStyle.MENU_GUIDEBOOK
	guidebook_button.tooltip_text = UiStyle.COMING_SOON
	settings_button.text = UiStyle.MENU_SETTINGS
	settings_button.tooltip_text = UiStyle.COMING_SOON
	quit_button.text = UiStyle.QUIT
	version_label.text = "v%s" % Session.game_version()
	version_label.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	play_button.pressed.connect(_on_play_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)

func enter(_data: RefCounted) -> void:
	_leaving = false

func _on_play_button_pressed() -> void:
	if _leaving:
		return
	_leaving = true
	play_button.disabled = true
	exit_requested.emit(MainMenuExitResult.new())

func _on_quit_button_pressed() -> void:
	get_tree().quit()
