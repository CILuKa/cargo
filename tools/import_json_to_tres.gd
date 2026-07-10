@tool
extends EditorScript

## JSON → .tres 导入工具
## 在 Godot 编辑器中运行：File → Run（或 Ctrl+Shift+X）
## 功能：将 data/ 目录下的 JSON 配置文件转换为合规的 .tres Resource 文件
## JSON 文件作为源数据保留，.tres 由 Godot 原生序列化，格式绝对正确

func _run() -> void:
	print("\n========== JSON → .tres 导入工具 ==========")
	_import_characters()
	_import_terrain_types()
	print("========== 导入完成 ==========\n")


# =============================================================================
# 角色数据导入
# =============================================================================

func _import_characters() -> void:
	var dir_path := "res://data/characters/"
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("无法打开目录: " + dir_path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	var count := 0
	while not file_name.is_empty():
		if file_name.ends_with(".json"):
			var json_path := dir_path + file_name
			if _import_character_json(json_path):
				count += 1
		file_name = dir.get_next()
	dir.list_dir_end()
	print("[导入] 角色: %d 个" % count)


func _import_character_json(json_path: String) -> bool:
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		return false

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("JSON 解析失败: " + json_path)
		return false

	var data: Dictionary = json.get_data()
	var character_id: String = data.get("character_id", "")
	if character_id.is_empty():
		return false

	# 根据 type 创建对应子类
	var char_type: String = data.get("type", "")
	var unit_res: UnitResource = _create_character_resource(char_type)
	if unit_res == null:
		unit_res = UnitResource.new()

	# 填充通用属性
	unit_res.character_id = character_id
	unit_res.unit_name = data.get("name", character_id)
	unit_res.max_hp = int(data.get("hp", 100))
	unit_res.atk = int(data.get("atk", 10))
	unit_res.def = int(data.get("def", 5))
	unit_res.matk = int(data.get("matk", 8))
	unit_res.mdef = int(data.get("mdef", 4))
	unit_res.mental_speed = int(data.get("mental_speed", 10))
	unit_res.move_speed = int(data.get("move_speed", 3))
	unit_res.mass = float(data.get("mass", 1.0))

	var skills_raw = data.get("available_skills", [])
	var skills: Array[String] = []
	for s in skills_raw:
		skills.append(str(s))
	unit_res.available_skills = skills
	unit_res.equipped_skill = str(data.get("equipped_skill", ""))

	# 行为脚本路径
	var behavior_path: String = data.get("behavior_script_path", "")
	if behavior_path.is_empty():
		# 自动推导
		var behavior_map := {
			"knight": "res://data/characters/knight_behavior.gd",
			"slime": "res://data/characters/slime_behavior.gd",
			"vip_student": "res://data/characters/vip_behavior.gd",
		}
		if behavior_map.has(char_type):
			behavior_path = behavior_map[char_type]
	unit_res.behavior_script_path = behavior_path

	# 子类特有属性
	_apply_character_subclass_data(unit_res, char_type, data)

	# 保存为 .tres（Godot 原生序列化）
	var tres_path := json_path.replace(".json", ".tres")
	var err := ResourceSaver.save(unit_res, tres_path)
	if err != OK:
		push_error("保存失败: " + tres_path + " error=" + str(err))
		return false

	print("  ✓ ", character_id, " → ", tres_path)
	return true


func _create_character_resource(char_type: String) -> UnitResource:
	match char_type:
		"knight":
			return KnightResource.new()
		"slime":
			return SlimeResource.new()
		"vip_student":
			return VipStudentResource.new()
		_:
			return null


func _apply_character_subclass_data(res: UnitResource, char_type: String, data: Dictionary) -> void:
	if res is KnightResource:
		var kr: KnightResource = res
		kr.shield_defense_bonus = int(data.get("shield_defense_bonus", 0))
		kr.counter_attack_chance = float(data.get("counter_attack_chance", 0.0))
	elif res is SlimeResource:
		var sr: SlimeResource = res
		sr.split_on_death = data.get("split_on_death", false)
		sr.split_count = int(data.get("split_count", 2))
		var absorbs_raw = data.get("absorbs_elements", [])
		var absorbs: Array[String] = []
		for a in absorbs_raw:
			absorbs.append(str(a))
		sr.absorbs_elements = absorbs
	elif res is VipStudentResource:
		var vr: VipStudentResource = res
		vr.is_protected_target = data.get("is_protected_target", true)
		vr.protection_priority = int(data.get("protection_priority", 1))
		vr.auto_dodge_chance = float(data.get("auto_dodge_chance", 0.0))


# =============================================================================
# 地形类型导入
# =============================================================================

func _import_terrain_types() -> void:
	var dir_path := "res://data/terrain_types/"
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("无法打开目录: " + dir_path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	var count := 0
	while not file_name.is_empty():
		if file_name.ends_with(".json"):
			var json_path := dir_path + file_name
			if _import_terrain_type_json(json_path):
				count += 1
		file_name = dir.get_next()
	dir.list_dir_end()
	print("[导入] 地形类型: %d 个" % count)


func _import_terrain_type_json(json_path: String) -> bool:
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		return false

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("JSON 解析失败: " + json_path)
		return false

	var data: Dictionary = json.get_data()
	var type_id: String = data.get("terrain_type_id", "")
	if type_id.is_empty():
		return false

	var terrain := TerrainType.new()
	terrain.terrain_type_id = type_id
	terrain.display_name = data.get("display_name", "")

	# usage_type 字符串 → 枚举
	var usage_str: String = data.get("usage_type", "WALKABLE")
	match usage_str:
		"SOLID": terrain.usage_type = TerrainType.TerrainUsage.SOLID
		"WALKABLE": terrain.usage_type = TerrainType.TerrainUsage.WALKABLE
		"INTERACTIVE": terrain.usage_type = TerrainType.TerrainUsage.INTERACTIVE
		"HAZARD": terrain.usage_type = TerrainType.TerrainUsage.HAZARD
		_: terrain.usage_type = TerrainType.TerrainUsage.WALKABLE

	# material_type 字符串 → 枚举
	var mat_str: String = data.get("material_type", "STONE")
	match mat_str:
		"PLASTIC": terrain.material_type = TerrainType.MaterialType.PLASTIC
		"WOOD": terrain.material_type = TerrainType.MaterialType.WOOD
		"STONE": terrain.material_type = TerrainType.MaterialType.STONE
		"METAL": terrain.material_type = TerrainType.MaterialType.METAL
		_: terrain.material_type = TerrainType.MaterialType.STONE

	terrain.mass = float(data.get("mass", 100.0))
	terrain.friction_coefficient = float(data.get("friction_coefficient", 1.0))
	terrain.has_health = data.get("has_health", true)
	terrain.custom_max_health = int(data.get("custom_max_health", -1))
	terrain.is_attackable = data.get("is_attackable", false)
	terrain.is_interactive = data.get("is_interactive", false)
	terrain.transform_to_id = data.get("transform_to_id", "")
	terrain.is_passable = data.get("is_passable", true)
	terrain.base_height = int(data.get("base_height", 0))

	# texture_paths
	var tex_raw: Array = data.get("texture_paths", [])
	var tex_paths: Array[String] = []
	for tp in tex_raw:
		tex_paths.append(str(tp))
	if tex_paths.size() == 6:
		terrain.texture_paths = tex_paths

	# 保存
	var tres_path := json_path.replace(".json", ".tres")
	var err := ResourceSaver.save(terrain, tres_path)
	if err != OK:
		push_error("保存失败: " + tres_path + " error=" + str(err))
		return false

	print("  ✓ ", type_id, " → ", tres_path)
	return true
