class_name SlantGrid
extends Control
## Endlessly repeating slanted selection grid (Docs/02 §3.8). Tile nodes are created once in
## setup() and only moved while scrolling.

signal tile_picked(pick: StringName)
signal unready_pressed

const TILE_GAP: float = 14.0
const COLUMN_SPAN: float = 832.0   # panel width minus both 4px borders

var kind: SelectTile.Kind = SelectTile.Kind.CHARACTER
var offset: float = 0.0
var _columns: Array = []            # Array of Array[Dictionary]
var _tiles: Array = []              # Array of Array[SelectTile]
var _col_shift: Array[float] = []
var _tile_h: float = 300.0
var _col_w: float = LobbyGeometry.PANEL_INNER_W

@onready var panel: SlantBox = %Panel
@onready var tile_layer: Control = %TileLayer
@onready var empty_label: Label = %EmptyLabel
@onready var banner: PanelContainer = %Banner
@onready var banner_label: Label = %BannerLabel
@onready var banner_button: Button = %BannerButton

func _ready() -> void:
	empty_label.text = UiStyle.EMPTY_CATALOG
	banner_button.text = UiStyle.UNREADY
	var style := UiStyle.box(UiStyle.LOBBY_BANNER, Color.TRANSPARENT, 0, 12)
	style.content_margin_left = 24
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	banner.add_theme_stylebox_override("panel", style)
	banner.position.x += LobbyGeometry.TAN * banner.position.y
	banner_button.pressed.connect(func() -> void: unready_pressed.emit())

## items: { "pick": StringName, "name": String, "english": String } in catalog order.
func setup(tile_kind: SelectTile.Kind, items: Array[Dictionary], column_count: int, tile_height: float, shifts: Array[float]) -> void:
	kind = tile_kind
	_tile_h = tile_height
	for column in _tiles:
		for tile: SelectTile in column:
			tile.queue_free()
	_tiles.clear()
	_columns.clear()
	empty_label.visible = items.is_empty()
	if items.is_empty():
		push_error("Selection grid has no items")
		return
	var count := clampi(column_count, 1, items.size())
	_col_w = (COLUMN_SPAN - 2.0 * LobbyGeometry.PANEL_PAD - TILE_GAP * (count - 1)) / count
	_col_shift.clear()
	for c in range(count):
		_columns.append([])
		_col_shift.append(shifts[c] if c < shifts.size() else 0.0)
	for index in range(items.size()):
		_columns[index % count].append(items[index])
	var pitch := _tile_h + TILE_GAP
	for c in range(count):
		var column: Array = _columns[c]
		var cycle := column.size() * pitch
		var node_count := ceili((LobbyGeometry.PANEL_INNER_H + cycle + 2.0 * pitch) / pitch) + 1
		var nodes: Array = []
		for k in range(node_count):
			var item: Dictionary = column[k % column.size()]
			var tile := SelectTile.new()
			tile.mouse_filter = Control.MOUSE_FILTER_PASS
			tile_layer.add_child(tile)
			tile.size = Vector2(_col_w, _tile_h)
			tile.configure(tile_kind, item.pick, item.name, item.get("english", ""))
			tile.picked.connect(func(pick: StringName) -> void: tile_picked.emit(pick))
			nodes.append(tile)
		_tiles.append(nodes)
	offset = 0.0
	_layout_tiles()

func set_selected(pick: StringName) -> void:
	for column in _tiles:
		for tile: SelectTile in column:
			tile.selected = tile.pick == pick

## Locked: tiles 50% and unclickable, banner on top (not faded).
func set_locked(locked: bool, message: String = "", show_button: bool = false) -> void:
	tile_layer.modulate.a = 0.5 if locked else 1.0
	for column in _tiles:
		for tile: SelectTile in column:
			tile.mouse_filter = Control.MOUSE_FILTER_IGNORE if locked else Control.MOUSE_FILTER_PASS
	banner.visible = locked
	banner_label.text = message
	banner_button.visible = show_button

func scroll_by(pixels: float) -> void:
	offset += pixels
	_layout_tiles()

func _layout_tiles() -> void:
	var pitch := _tile_h + TILE_GAP
	for c in range(_tiles.size()):
		var column: Array = _columns[c]
		var cycle := column.size() * pitch
		var m := fposmod(offset + _col_shift[c] * pitch, cycle)
		var column_x := LobbyGeometry.PANEL_BORDER + LobbyGeometry.PANEL_PAD + c * (_col_w + TILE_GAP)
		var nodes: Array = _tiles[c]
		for k in range(nodes.size()):
			var top := LobbyGeometry.PANEL_PAD_Y + k * pitch - m - pitch
			var tile: SelectTile = nodes[k]
			tile.position = Vector2(column_x + LobbyGeometry.TAN * top, top)
