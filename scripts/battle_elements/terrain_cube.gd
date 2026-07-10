@tool
extends Node3D
class_name TerrainCube

## 地形方块 — 棋盘中一个格子的地形可视化
## 在编辑器中根据属性自动生成立方体网格层
##
## 使用方式：作为 scenes/battle_elements/terrain_cube.tscn 的实例
## 由 import_battle_to_scene.gd 自动创建，也可手动添加

const TILE_SIZE := 1.0

@export var col: int = 0:
	set(v): col = v; _request_rebuild()
@export var row: int = 0:
	set(v): row = v; _request_rebuild()
@export var height: int = 0:
	set(v): height = v; _request_rebuild()
@export var terrain_type: String = "stone_floor":
	set(v): terrain_type = v; _request_rebuild()
@export var layers: Array = []:
	set(v): layers = v; _request_rebuild()
@export var light_color: Color = Color(0.88, 0.83, 0.74):
	set(v): light_color = v; _request_rebuild()
@export var dark_color: Color = Color(0.52, 0.46, 0.38):
	set(v): dark_color = v; _request_rebuild()

var _rebuild_pending: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		_rebuild_meshes()


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		_rebuild_meshes()


func _process(_delta: float) -> void:
	if _rebuild_pending:
		_rebuild_pending = false
		_rebuild_meshes()


func _request_rebuild() -> void:
	if not Engine.is_editor_hint():
		return
	_rebuild_pending = true


## 清空所有网格子节点
func _clear_meshes() -> void:
	var to_remove: Array[Node] = []
	for child in get_children():
		if child is MeshInstance3D:
			to_remove.append(child)
	for child in to_remove:
		remove_child(child)
		child.queue_free()


## 根据 height/layers/terrain_type 重建立方体层
func _rebuild_meshes() -> void:
	if not Engine.is_editor_hint():
		return
	_clear_meshes()

	var total_layers := maxi(height, 0) + 1

	# 找到最顶层非 AIR 层（用于着色区分）
	var last_real_layer := -1
	for li in range(total_layers - 1, -1, -1):
		if li >= layers.size() or layers[li] != "__AIR__":
			last_real_layer = li
			break

	for layer in range(total_layers):
		# 跳过 AIR 层
		if layer < layers.size() and layers[layer] == "__AIR__":
			continue

		var mesh := BoxMesh.new()
		mesh.size = Vector3(TILE_SIZE, TILE_SIZE, TILE_SIZE)

		var cube := MeshInstance3D.new()
		cube.name = "Mesh_L%d" % layer
		cube.mesh = mesh
		cube.position = Vector3(0, TILE_SIZE * 0.5 + layer * TILE_SIZE, 0)

		# 确定该层地形类型
		var layer_type: String = terrain_type
		if layer < layers.size() and layers[layer] != "" and layers[layer] != "__AIR__":
			layer_type = layers[layer]

		var layer_color := _get_terrain_color(layer_type)

		var mat := StandardMaterial3D.new()
		if layer == last_real_layer:
			mat.albedo_color = layer_color
		else:
			mat.albedo_color = layer_color.darkened(0.15)
		cube.material_override = mat

		add_child(cube)


## 简化地形着色（编辑器预览用，不需要 TerrainManager）
func _get_terrain_color(type_id: String) -> Color:
	var is_light := (col + row) % 2 == 0
	match type_id:
		"stone_floor", "stone_wall":
			return Color(0.62, 0.62, 0.65) if is_light else Color(0.50, 0.50, 0.53)
		"wood_floor", "wood_wall":
			return Color(0.65, 0.42, 0.22) if is_light else Color(0.52, 0.34, 0.18)
		"hill":
			return Color(0.45, 0.65, 0.30) if is_light else Color(0.35, 0.52, 0.24)
		"wall":
			return Color(0.55, 0.55, 0.58) if is_light else Color(0.42, 0.42, 0.45)
		"water":
			return Color(0.3, 0.5, 0.75) if is_light else Color(0.22, 0.38, 0.60)
		_:
			return light_color if is_light else dark_color
