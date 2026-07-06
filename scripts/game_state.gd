extends Node

## 全局游戏状态 Autoload，管理所有 flags 变量
## 注意：Autoload 脚本不能使用 class_name，否则与 Autoload 名称冲突

var flags: Dictionary = {}

func _ready():
	reset()

## 重置所有状态（新游戏时调用）
func reset():
	flags = {
		"route": "",
		"affection_heroine": 0,
		"affection_osananajimi": 0,
		"met_heroine": false,
		"met_osananajimi": false,
		"chapter": 1,
		"visited_nodes": []
	}
	CharacterRoster.reset()

## 设置标记
func set_flag(key: String, value):
	flags[key] = value

## 读取标记
func get_flag(key: String, default = null):
	return flags.get(key, default)

## 检查条件是否满足
## condition 格式: {"flag": "key", "op": "==", "value": val}
## 或 {"and": [条件1, 条件2]} / {"or": [条件1, 条件2]}
func check_condition(condition: Dictionary) -> bool:
	if condition.is_empty():
		return true

	if condition.has("and"):
		for cond in condition["and"]:
			if not check_condition(cond):
				return false
		return true

	if condition.has("or"):
		for cond in condition["or"]:
			if check_condition(cond):
				return true
		return false

	if condition.has("flag"):
		var key = condition["flag"]
		var op = condition.get("op", "==")
		var expected = condition["value"]
		var actual = flags.get(key)

		match op:
			"==": return actual == expected
			"!=": return actual != expected
			">=": return actual >= expected
			"<=": return actual <= expected
			">":  return actual > expected
			"<":  return actual < expected

	return true
