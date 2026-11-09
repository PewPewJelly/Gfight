@tool
extends EditorPlugin
## Adds the 캐릭터 작업실 tab next to 2D, 3D, and Script. Editor-only hooks are handed to the
## panel here so the panel itself stays free of editor classes.

var panel: WorkshopPanel

func _enter_tree() -> void:
	panel = WorkshopPanel.new()
	panel.file_system = EditorInterface.get_resource_filesystem()
	panel.ui_scale = EditorInterface.get_editor_scale()
	panel.play_lab = func() -> void: EditorInterface.play_custom_scene(CharacterFiles.LAB_SCENE)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(panel)
	_make_visible(false)

func _exit_tree() -> void:
	if is_instance_valid(panel):
		panel.queue_free()

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool) -> void:
	if is_instance_valid(panel):
		panel.visible = visible

func _get_plugin_name() -> String:
	return "캐릭터 작업실"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("CharacterBody2D", "EditorIcons")
