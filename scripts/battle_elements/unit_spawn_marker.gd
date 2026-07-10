@tool
extends Node3D
class_name UnitSpawnMarker

## 单位出生标记 — 在编辑器中可视化单位出生位置
## 显示为彩色圆盘 + ID 标签
##
## 使用方式：作为 scenes/battle_elements/unit_spawn_marker.tscn 的实例
## 由 import_battle_to_scene.gd 自动创建，也可手动添加

const TILE_SIZE := 1.0

@export var spawn_id: String = "":
	set(v): spawn_id = v; _request_rebuild()
@export var character_id: String = "":
	set(v): character_id = v; _request_rebuild()
@export var col: int = 0:
	set(v): col = v; _request_rebuild()
@export var row: int = 0:
	set(v): row = v; _request_rebuild()
@export var team: String = "player":
	set(v): team = v; _request_rebuild()
@export var texture_path: String = "":
	set(v): texture_path = v

var _rebuild_pending: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		_rebuild_marker()


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		_rebuild_marker()


func _process(_delta: float) -> void:
	if _rebuild_pending:
		_rebuild_pending = false
		_rebuild_marker()


func _request_rebuild() -> void:
	if not Engine.is_editor_hint():
		return
	_rebuild_pending = true


func _clear_marker() -> void:
	var to_remove: Array[Node] = []
	for child in get_children():
		if child is MeshInstance3D or child is Label3D:
			to_remove.append(child)
	for child in to_remove:
		remove_child(child)
		child.queue_free()


func _rebuild_marker() -> void:
	if not Engine.is_editor_hint():
		return
	_clear_marker()

	# 底座圆盘
	var disk_mesh := CylinderMesh.new()
	disk_mesh.top_radius = TILE_SIZE * 0.35
	disk_mesh.bottom_radius = TILE_SIZE * 0.35
	disk_mesh.height = 0.06

	var disk := MeshInstance3D.new()
	disk.name = "Disk"
	disk.mesh = disk_mesh
	disk.position = Vector3(0, 0.03, 0)

	var mat := StandardMaterial3D.new()
	match team:
		"player":  mat.albedo_color = Color(0.3, 0.6, 1.0, 0.8)
		"enemy":   mat.albedo_color = Color(1.0, 0.3, 0.3, 0.8)
		"neutral": mat.albedo_color = Color(0.3, 1.0, 0.5, 0.8)
		_:         mat.albedo_color = Color(0.8, 0.8, 0.8, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disk.material_override = mat
	add_child(disk)

	# ID 标签
	var label := Label3D.new()
	label.name = "Label"
	label.text = spawn_id if not spawn_id.is_empty() else "Unit"
	label.font_size = 16
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 0.5, 0)
	label.pixel_size = 0.01
	label.outline_size = 3

	match team:
		"player":  label.modulate = Color(0.5, 0.8, 1.0)
		"enemy":   label.modulate = Color(1.0, 0.5, 0.5)
		"neutral": label.modulate = Color(0.5, 1.0, 0.6)
		_:         label.modulate = Color.WHITE
	add_child(label)
