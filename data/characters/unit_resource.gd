class_name UnitResource
extends Resource

## 角色数据资源基类 — 定义通用属性 + 关联行为脚本
## 子脚本（KnightResource / SlimeResource 等）定义差异化数据字段
## 行为脚本（scripts/behaviors/）定义差异化运行时逻辑
## .tres 数据文件选择子类类型 + 填具体数值 + 指定行为脚本

# =============================================================================
# 通用属性
# =============================================================================

@export var character_id: String = ""
@export var unit_name: String = ""
@export var max_hp: int = 100
@export var atk: int = 10
@export var def: int = 5
@export var matk: int = 8
@export var mdef: int = 4
@export var mental_speed: int = 10
@export var move_speed: int = 3
@export var mass: float = 1.0
@export var available_skills: Array[String] = []
@export var equipped_skill: String = ""

## 关联的行为脚本路径（如 "res://data/characters/slime_behavior.gd"）
## 留空则无差异化行为；运行时按路径加载 GDScript
@export var behavior_script_path: String = ""

# =============================================================================
# 虚方法 — 子脚本可覆盖实现差异化数据初始化
# =============================================================================

## 单位创建后的数据层初始化（设置 meta 等，子脚本覆盖）
func _on_unit_created(unit: TacticsUnit) -> void:
	pass

## 获取差异化描述（子脚本覆盖）
func get_type_description() -> String:
	return ""

## 将 Resource 属性应用到 TacticsUnit 实例，并挂载行为脚本
func apply_to_unit(unit: TacticsUnit) -> void:
	unit.unit_name = unit_name
	unit.max_hp = max_hp
	unit.current_hp = max_hp
	unit.mental_speed = mental_speed
	unit.move_speed = move_speed
	unit.atk = atk
	unit.def = def
	unit.matk = matk
	unit.mdef = mdef
	unit.physics.mass = mass

	# 技能：使用当前装备的技能
	if not equipped_skill.is_empty():
		unit.skill_ids = [equipped_skill]
	else:
		unit.skill_ids.clear()

	# 子脚本数据层初始化（设置 meta 等）
	_on_unit_created(unit)

	# 挂载行为脚本（按路径运行时加载）
	if not behavior_script_path.is_empty():
		var script := load(behavior_script_path) as GDScript
		if script != null:
			var behavior: UnitBehavior = script.new()
			behavior.name = "Behavior"
			unit.add_child(behavior)
			behavior.setup(unit)
		else:
			push_warning("UnitResource: 无法加载行为脚本: " + behavior_script_path)

## 转换为 Dictionary（兼容存档系统）
func to_dict() -> Dictionary:
	var d := {
		"character_id": character_id,
		"name": unit_name,
		"hp": max_hp,
		"atk": atk,
		"def": def,
		"matk": matk,
		"mdef": mdef,
		"mental_speed": mental_speed,
		"move_speed": move_speed,
		"mass": mass,
		"available_skills": available_skills,
		"equipped_skill": equipped_skill,
	}
	_merge_extra_dict(d)
	return d

## 子脚本覆盖，将额外属性合并到字典
func _merge_extra_dict(d: Dictionary) -> void:
	pass

## 从 Dictionary 恢复运行时可修改的属性（equipped_skill、available_skills）
func apply_runtime_data(data: Dictionary) -> void:
	if data.has("equipped_skill"):
		equipped_skill = data["equipped_skill"]
	if data.has("available_skills"):
		available_skills = Array(data["available_skills"], TYPE_STRING, &"", null)
