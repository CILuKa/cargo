extends Node

## 全局角色数据管理 Autoload
## 存储所有角色的基础属性和技能配置，战斗中从此处读取角色数据
## 剧情过程中可随时修改角色技能配置

## 角色模板字典 {character_id: {name, hp, atk, def, matk, mdef, mental_speed, move_speed, available_skills, equipped_skill}}
var characters: Dictionary = {}

func _ready() -> void:
	_init_default_characters()

## 初始化默认角色数据
func _init_default_characters() -> void:
	characters = {
		"knight": {
			"name": "骑士",
			"hp": 30,
			"atk": 8,
			"def": 4,
			"matk": 2,
			"mdef": 3,
			"mental_speed": 12,
			"move_speed": 3,
			"mass": 3.0,
			"available_skills": ["basic_attack", "fireball", "push_force", "basic_heal"],
			"equipped_skill": "basic_attack"
		},
		"vip_student": {
			"name": "学生（保护目标）",
			"hp": 15,
			"atk": 0,
			"def": 1,
			"matk": 0,
			"mdef": 1,
			"mental_speed": 8,
			"move_speed": 2,
			"mass": 2.0,
			"available_skills": [],
			"equipped_skill": ""
		},
		"slime": {
			"name": "史莱姆",
			"hp": 15,
			"atk": 5,
			"def": 2,
			"matk": 1,
			"mdef": 1,
			"mental_speed": 10,
			"move_speed": 2,
			"mass": 1.0,
			"available_skills": ["basic_attack"],
			"equipped_skill": "basic_attack"
		}
	}

## 获取角色数据
func get_character(character_id: String) -> Dictionary:
	if characters.has(character_id):
		return characters[character_id]
	push_error("CharacterRoster: 未找到角色: " + character_id)
	return {}

## 获取角色当前装备的技能 ID
func get_equipped_skill(character_id: String) -> String:
	var char_data := get_character(character_id)
	if char_data.is_empty():
		return ""
	return char_data.get("equipped_skill", "")

## 设置角色装备的技能
func set_equipped_skill(character_id: String, skill_id: String) -> void:
	if not characters.has(character_id):
		push_error("CharacterRoster: 未找到角色: " + character_id)
		return
	var available: Array = characters[character_id].get("available_skills", [])
	if skill_id.is_empty() or skill_id in available:
		characters[character_id]["equipped_skill"] = skill_id
		print("[CharacterRoster] ", character_id, " 装备技能: ", skill_id)
	else:
		push_error("CharacterRoster: 技能不在可用列表中: " + skill_id)

## 获取角色可用技能列表
func get_available_skills(character_id: String) -> Array:
	var char_data := get_character(character_id)
	if char_data.is_empty():
		return []
	return char_data.get("available_skills", [])

## 添加可用技能（剧情中获得新技能时调用）
func add_skill(character_id: String, skill_id: String) -> void:
	if not characters.has(character_id):
		push_error("CharacterRoster: 未找到角色: " + character_id)
		return
	var available: Array = characters[character_id].get("available_skills", [])
	if skill_id not in available:
		available.append(skill_id)
		print("[CharacterRoster] ", character_id, " 获得新技能: ", skill_id)

## 重置所有角色数据（新游戏时调用）
func reset() -> void:
	_init_default_characters()


## 获取存档数据（完整保存当前角色状态）
func get_save_data() -> Dictionary:
	return characters.duplicate(true)


## 从存档恢复角色数据
func restore_from_save(data: Dictionary) -> void:
	if data.is_empty():
		_init_default_characters()
		return
	characters = data.duplicate(true)
	print("[CharacterRoster] 从存档恢复角色数据，共 ", characters.size(), " 个角色")