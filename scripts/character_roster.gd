extends Node

## 全局角色数据管理 Autoload
## 加载优先级：.tres（编辑器生成的 Resource）→ .json（运行时动态创建 Resource）
## 工作流：编辑 JSON → 运行 import_json_to_tres.gd → 生成 .tres → Godot 直接加载
## JSON 是源数据，.tres 是编译产物（由 Godot 原生序列化，格式绝对正确）

## 角色 Resource 字典 {character_id: UnitResource}
var _character_resources: Dictionary = {}

## 角色数据目录
const CHARACTER_DIR = "res://data/characters/"

## 角色类型 → 行为脚本路径映射（.tres 中不存储此信息时使用）
const BEHAVIOR_MAP: Dictionary = {
	"knight": "res://data/characters/knight_behavior.gd",
	"slime": "res://data/characters/slime_behavior.gd",
	"vip_student": "res://data/characters/vip_behavior.gd",
}


func _ready() -> void:
	_load_characters()


## 从目录加载角色资源（.tres 优先，.json 回退）
func _load_characters() -> void:
	_character_resources.clear()

	var dir := DirAccess.open(CHARACTER_DIR)
	if dir == null:
		push_error("CharacterRoster: 无法打开角色目录: " + CHARACTER_DIR)
		return

	# 第一轮：尝试加载 .tres 文件
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	var tres_loaded: Dictionary = {}
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var path: String = CHARACTER_DIR + file_name
			var res := load(path)
			if res is UnitResource:
				var unit_res: UnitResource = res
				if not unit_res.character_id.is_empty():
					_character_resources[unit_res.character_id] = unit_res
					tres_loaded[file_name.replace(".tres", ".json")] = true
		file_name = dir.get_next()
	dir.list_dir_end()

	# 第二轮：加载没有对应 .tres 的 .json 文件（回退）
	dir.list_dir_begin()
	file_name = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			if not tres_loaded.has(file_name):
				_load_character_from_json(CHARACTER_DIR + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	print("[CharacterRoster] 已加载 %d 个角色资源" % _character_resources.size())


## 从 JSON 文件创建 UnitResource 实例（回退路径）
func _load_character_from_json(file_path: String) -> void:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return

	var data: Dictionary = json.get_data()
	var character_id: String = data.get("character_id", "")
	if character_id.is_empty():
		return

	var char_type: String = data.get("type", "")
	var unit_res: UnitResource = _create_resource_by_type(char_type)
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
	if BEHAVIOR_MAP.has(char_type):
		unit_res.behavior_script_path = BEHAVIOR_MAP[char_type]

	# 子类特有属性
	_apply_subclass_data(unit_res, char_type, data)

	_character_resources[character_id] = unit_res
	print("[CharacterRoster] 从 JSON 加载: ", character_id)


func _create_resource_by_type(char_type: String) -> UnitResource:
	match char_type:
		"knight":
			return KnightResource.new()
		"slime":
			return SlimeResource.new()
		"vip_student":
			return VipStudentResource.new()
		_:
			return null


func _apply_subclass_data(res: UnitResource, char_type: String, data: Dictionary) -> void:
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
# 获取角色数据
# =============================================================================

func get_character_resource(character_id: String) -> UnitResource:
	if _character_resources.has(character_id):
		return _character_resources[character_id]
	push_error("CharacterRoster: 未找到角色: " + character_id)
	return null

func get_character(character_id: String) -> Dictionary:
	var res := get_character_resource(character_id)
	if res != null:
		return res.to_dict()
	return {}

func get_equipped_skill(character_id: String) -> String:
	var res := get_character_resource(character_id)
	if res != null:
		return res.equipped_skill
	return ""

func set_equipped_skill(character_id: String, skill_id: String) -> void:
	var res := get_character_resource(character_id)
	if res == null:
		return
	if skill_id.is_empty() or skill_id in res.available_skills:
		res.equipped_skill = skill_id
	else:
		push_error("CharacterRoster: 技能不在可用列表中: " + skill_id)

func get_available_skills(character_id: String) -> Array:
	var res := get_character_resource(character_id)
	if res != null:
		return res.available_skills
	return []

func add_skill(character_id: String, skill_id: String) -> void:
	var res := get_character_resource(character_id)
	if res == null:
		return
	if skill_id not in res.available_skills:
		res.available_skills.append(skill_id)

func reset() -> void:
	_load_characters()

# =============================================================================
# 存档兼容
# =============================================================================

func get_save_data() -> Dictionary:
	var data: Dictionary = {}
	for character_id in _character_resources:
		var res: UnitResource = _character_resources[character_id]
		data[character_id] = {
			"equipped_skill": res.equipped_skill,
			"available_skills": res.available_skills.duplicate()
		}
	return data

func restore_from_save(data: Dictionary) -> void:
	if data.is_empty():
		_load_characters()
		return
	_load_characters()
	for character_id in data:
		if _character_resources.has(character_id):
			var res: UnitResource = _character_resources[character_id]
			res.apply_runtime_data(data[character_id])
