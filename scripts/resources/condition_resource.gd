class_name ConditionResource
extends Resource

## 战斗胜负条件配置
## 支持多种条件类型，每种类型有不同的 params 参数

## 条件类型枚举提示：
##   eliminate_all  - 消灭某队全部单位  params: {"team": "enemy"}
##   eliminate_count - 消灭指定数量单位  params: {"team": "enemy", "count": 1}
##   unit_alive     - 指定单位存活      params: {"unit_id": "vip_student"}
##   unit_dead      - 指定单位死亡      params: {"unit_id": "vip_student"}
##   all_units_dead - 某队全灭          params: {"team": "player"}
##   turn_count     - 回合数达到        params: {"count": 10}

@export var condition_id: String = ""       # 条件唯一标识
@export var description: String = ""        # 条件描述
@export var type: String = ""               # 条件类型（见上方枚举）
@export var params: Dictionary = {}         # 条件参数
@export var next_branch: String = ""        # 满足条件后跳转的剧情节点ID
@export var next_file: String = ""          # 跨文件引用：目标剧本文件路径（为空则同文件跳转）


## 转换为旧格式字典（兼容 _check_conditions 接口）
## next 字段支持两种格式：
##   - 字符串：同文件节点跳转，如 "battle_001_win"
##   - 字典：跨文件跳转，如 {"file": "res://data/story/xxx.json", "node": "node_id"}
func to_condition_dict() -> Dictionary:
	var next_value: Variant
	if not next_file.is_empty():
		next_value = {"file": next_file, "node": next_branch}
	else:
		next_value = next_branch
	return {
		"id": condition_id,
		"description": description,
		"type": type,
		"params": params,
		"next": next_value
	}
