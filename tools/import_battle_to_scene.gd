@tool
extends EditorScript

## 战斗 JSON → .tscn 场景 导入工具
##
## 使用方式：
##   1. 在 Godot 编辑器中打开此脚本
##   2. 按 Ctrl+Shift+X 运行
##   3. 自动扫描 data/battles/*.json 并生成 scenes/battles/*.tscn
##
## 生成的场景结构：
##   BattleScene
##   ├── WorldEnvironment
##   ├── DirectionalLight3D
##   ├── Camera3D
##   ├── TerrainContainer
##   │   ├── BasePlatform (底座平面)
##   │   ├── Cube_0_6 (TerrainCube 实例 - 非默认地形)
##   │   └── ...
##   └── UnitContainer
##       ├── Unit_knight_1 (UnitSpawnMarker 实例)
##       └── ...

const BATTLES_DIR: String = "res://data/battles/"
const SCENES_DIR: String = "res://scenes/battles/"
const TERRAIN_CUBE_SCENE: String = "res://scenes/battle_elements/terrain_cube.tscn"
const UNIT_MARKER_SCENE: String = "res://scenes/battle_elements/unit_spawn_marker.tscn"
const TILE_SIZE := 1.0


func _run() -> void:
	print("===== 战斗JSON → 场景导入工具 =====")

	# 确保输出目录存在
	DirAccess.make_dir_recursive_absolute(SCENES_DIR)

	# 检查基础场景是否存在
	if not ResourceLoader.exists(TERRAIN_CUBE_SCENE):
		push_error("缺少基础场景: " + TERRAIN_CUBE_SCENE)
		return
	if not ResourceLoader.exists(UNIT_MARKER_SCENE):
		push_error("缺少基础场景: " + UNIT_MARKER_SCENE)
		return

	var terrain_cube_res := load(TERRAIN_CUBE_SCENE) as PackedScene
	var unit_marker_res := load(UNIT_MARKER_SCENE) as PackedScene

	# 扫描所有战斗 JSON 文件
	var dir := DirAccess.open(BATTLES_DIR)
	if dir == null:
		push_error("无法打开目录: " + BATTLES_DIR)
		return

	var count := 0
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.begins_with("battle_") and file_name.ends_with(".json") and not file_name.begins_with("battle_terrain_"):
			var json_path: String = BATTLES_DIR + file_name
			if _import_battle(json_path, terrain_cube_res, unit_marker_res):
				count += 1
		file_name = dir.get_next()
	dir.list_dir_end()

	print("===== 导入完成：共生成 %d 个场景 =====" % count)


func _import_battle(json_path: String, terrain_cube_res: PackedScene, unit_marker_res: PackedScene) -> bool:
	# 读取 JSON
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("无法读取: " + json_path)
		return false

	var json_text := file.get_as_text()
	var json := JSON.new()
	if json.parse(json_text) != OK:
		push_error("JSON 解析失败: " + json_path + " - " + json.get_error_message())
		return false

	var data: Dictionary = json.data
	var battle_id: String = data.get("battle_id", "")
	if battle_id.is_empty():
		battle_id = json_path.get_file().replace(".json", "")

	print("  导入: %s → %s.tscn" % [battle_id, battle_id])

	# === 1. 创建 BattleScene 根节点 ===
	var scene_node := BattleScene.new()
	scene_node.load_from_dict(data)

	# 自动设置 terrain_json_path
	var json_filename: String = json_path.get_file()
	var terrain_filename: String = json_filename.replace("battle_", "battle_terrain_")
	var terrain_path: String = BATTLES_DIR + terrain_filename
	if FileAccess.file_exists(terrain_path):
		scene_node.terrain_json_path = terrain_path
		print("    地形引用: %s" % terrain_path)
	else:
		print("    警告: 地形文件不存在: %s" % terrain_path)

	# 临时父节点（PackedScene.pack 需要 owner 链）
	var temp_parent := Node.new()
	temp_parent.add_child(scene_node)
	scene_node.owner = temp_parent

	# === 2. WorldEnvironment ===
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.ambient_light_energy = 0.8
	world_env.environment = env
	scene_node.add_child(world_env)
	world_env.owner = scene_node

	# === 3. DirectionalLight3D ===
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "DirectionalLight3D"
	dir_light.light_color = Color(1.0, 0.95, 0.9)
	dir_light.light_energy = 1.0
	dir_light.rotation_degrees = Vector3(-55, 45, 0)
	scene_node.add_child(dir_light)
	dir_light.owner = scene_node

	# === 4. Camera3D ===
	var grid_cols: int = data.get("grid_cols", 10)
	var grid_rows: int = data.get("grid_rows", 10)
	var cam_data: Dictionary = data.get("camera_look_at", {})
	var cam_col: int = cam_data.get("col", 5)
	var cam_row: int = cam_data.get("row", 4)
	var cam_height: float = cam_data.get("height", 1.0)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 45.0
	cam.near = 0.1
	cam.far = 500.0

	var target := _grid_to_world(cam_col, cam_row, grid_cols, grid_rows)
	target.y = cam_height
	var max_dim := maxf(float(grid_cols), float(grid_rows))
	var distance := clampf(max_dim * 0.9, 3.0, 80.0)
	var angle_x := deg_to_rad(55.0)
	var angle_y := deg_to_rad(45.0)
	cam.position = Vector3(
		target.x + distance * cos(angle_x) * sin(angle_y),
		target.y + distance * sin(angle_x),
		target.z + distance * cos(angle_x) * cos(angle_y)
	)
	cam.rotation_degrees = Vector3(-55, -45, 0)
	scene_node.add_child(cam)
	cam.owner = scene_node

	# === 5. 加载地形数据 ===
	var terrain_tiles: Dictionary = {}
	var excluded_tiles: Dictionary = {}
	var default_type: String = data.get("initial_terrain_type", "stone_floor")
	_load_terrain_data(terrain_path, grid_cols, grid_rows, terrain_tiles, excluded_tiles, default_type)

	# === 6. TerrainContainer ===
	var terrain_container := Node3D.new()
	terrain_container.name = "TerrainContainer"
	scene_node.add_child(terrain_container)
	terrain_container.owner = scene_node

	# BasePlatform
	var base_platform := _create_base_platform(grid_cols, grid_rows)
	terrain_container.add_child(base_platform)
	base_platform.owner = scene_node

	# 地形方块（只创建非默认地形）
	var tile_light_color: Color = _hex_to_color(data.get("tile_light_color", "#E0D4BD"))
	var tile_dark_color: Color = _hex_to_color(data.get("tile_dark_color", "#847560"))
	var cube_count := 0
	for key in terrain_tiles:
		var t_data: Dictionary = terrain_tiles[key]
		var cube := terrain_cube_res.instantiate() as TerrainCube
		cube.col = int(key.x)
		cube.row = int(key.y)
		cube.height = int(t_data.get("height", 0))
		cube.terrain_type = str(t_data.get("type_id", default_type))
		cube.layers = t_data.get("layers", [])
		cube.light_color = tile_light_color
		cube.dark_color = tile_dark_color
		cube.name = "Cube_%d_%d" % [int(key.x), int(key.y)]
		cube.position = _grid_to_world(int(key.x), int(key.y), grid_cols, grid_rows)
		terrain_container.add_child(cube)
		cube.owner = scene_node
		cube_count += 1
	print("    地形方块: %d 个（非默认）" % cube_count)

	# === 7. UnitContainer ===
	var unit_container := Node3D.new()
	unit_container.name = "UnitContainer"
	scene_node.add_child(unit_container)
	unit_container.owner = scene_node

	var units: Array = data.get("units", [])
	for unit_data in units:
		var marker := unit_marker_res.instantiate() as UnitSpawnMarker
		marker.spawn_id = str(unit_data.get("id", ""))
		marker.character_id = str(unit_data.get("character_id", ""))
		marker.col = int(unit_data.get("col", 0))
		marker.row = int(unit_data.get("row", 0))
		marker.team = str(unit_data.get("team", "player"))
		marker.texture_path = str(unit_data.get("texture", ""))
		marker.name = "Unit_%s" % marker.spawn_id

		# 站在格子顶部
		var key := Vector2i(marker.col, marker.row)
		var surface_y: float = 0.0
		if terrain_tiles.has(key):
			surface_y = TILE_SIZE * (int(terrain_tiles[key].get("height", 0)) + 1)
		else:
			surface_y = TILE_SIZE  # 默认 height=0 → 1层
		var world_pos := _grid_to_world(marker.col, marker.row, grid_cols, grid_rows)
		marker.position = Vector3(world_pos.x, surface_y + 0.01, world_pos.z)

		unit_container.add_child(marker)
		marker.owner = scene_node
	print("    单位标记: %d 个" % units.size())

	# === 8. 打包保存 ===
	var scene := PackedScene.new()
	if scene.pack(scene_node) != OK:
		push_error("打包场景失败: " + battle_id)
		temp_parent.queue_free()
		return false

	temp_parent.remove_child(scene_node)
	scene_node.queue_free()
	temp_parent.queue_free()

	var save_path: String = SCENES_DIR + battle_id + ".tscn"
	if ResourceSaver.save(scene, save_path) != OK:
		push_error("保存场景失败: " + save_path)
		return false

	print("    保存成功: %s" % save_path)
	return true


# =============================================================================
# 地形数据加载
# =============================================================================

func _load_terrain_data(terrain_path: String, grid_cols: int, grid_rows: int,
		out_tiles: Dictionary, out_excluded: Dictionary, default_type: String) -> void:

	if terrain_path.is_empty():
		return

	var file := FileAccess.open(terrain_path, FileAccess.READ)
	if file == null:
		return

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return

	var terrain_config: Dictionary = json.data.get("terrain_config", {})

	# 排除格子
	var excluded: Array = terrain_config.get("excluded_tiles", [])
	for entry in excluded:
		out_excluded[Vector2i(entry.get("col", -1), entry.get("row", -1))] = true

	# 稀疏格式 tiles
	var tiles: Array = terrain_config.get("tiles", [])
	for t in tiles:
		var col: int = t.get("col", 0)
		var row: int = t.get("row", 0)
		var key := Vector2i(col, row)

		var layers: Array = t.get("layers", [])
		if not layers.is_empty():
			var top_type_id: String = default_type
			for li in range(layers.size() - 1, -1, -1):
				if layers[li] != "__AIR__":
					top_type_id = layers[li]
					break
			out_tiles[key] = {
				"type_id": top_type_id,
				"height": layers.size() - 1,
				"layers": layers
			}
		else:
			var type_id: String = t.get("type_id", t.get("type", default_type))
			var height: int = t.get("height", 0)
			out_tiles[key] = {
				"type_id": type_id,
				"height": height
			}

	# 密集格式 grid
	var grid: Array = terrain_config.get("grid", [])
	if not grid.is_empty():
		var height_grid: Array = terrain_config.get("height_grid", [])
		for row_idx in range(grid.size()):
			var row_data: Array = grid[row_idx]
			for col_idx in range(row_data.size()):
				var type_id_val = row_data[col_idx]
				if type_id_val != null and type_id_val != "":
					var key := Vector2i(col_idx, row_idx)
					var height_val: int = 0
					if row_idx < height_grid.size() and col_idx < height_grid[row_idx].size():
						height_val = height_grid[row_idx][col_idx]
					out_tiles[key] = {
						"type_id": str(type_id_val),
						"height": height_val
					}


# =============================================================================
# 辅助函数
# =============================================================================

func _grid_to_world(col: int, row: int, grid_cols: int, grid_rows: int) -> Vector3:
	var cx: float = col - (grid_cols - 1) * 0.5
	var rz: float = row - (grid_rows - 1) * 0.5
	return Vector3(cx * TILE_SIZE, 0, rz * TILE_SIZE)


func _create_base_platform(grid_cols: int, grid_rows: int) -> MeshInstance3D:
	var corners: Array = [
		_grid_to_world(0, 0, grid_cols, grid_rows),
		_grid_to_world(grid_cols - 1, 0, grid_cols, grid_rows),
		_grid_to_world(grid_cols - 1, grid_rows - 1, grid_cols, grid_rows),
		_grid_to_world(0, grid_rows - 1, grid_cols, grid_rows),
	]
	var x_min: float = corners[0].x; var x_max: float = corners[0].x
	var z_min: float = corners[0].z; var z_max: float = corners[0].z
	for c in corners:
		x_min = minf(x_min, c.x); x_max = maxf(x_max, c.x)
		z_min = minf(z_min, c.z); z_max = maxf(z_max, c.z)

	var bw: float = (x_max - x_min) + TILE_SIZE
	var bd: float = (z_max - z_min) + TILE_SIZE

	var mesh := BoxMesh.new()
	mesh.size = Vector3(bw, 0.04, bd)

	var platform := MeshInstance3D.new()
	platform.name = "BasePlatform"
	platform.mesh = mesh
	platform.position = Vector3(0, -0.02, 0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.08, 0.05)
	platform.material_override = mat

	return platform


func _hex_to_color(hex: String) -> Color:
	if hex.is_empty():
		return Color.WHITE
	hex = hex.lstrip("#")
	if hex.length() < 6:
		return Color.WHITE
	var r := hex.substr(0, 2).hex_to_int() / 255.0
	var g := hex.substr(2, 2).hex_to_int() / 255.0
	var b := hex.substr(4, 2).hex_to_int() / 255.0
	return Color(r, g, b)
