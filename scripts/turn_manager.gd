class_name TurnManager
extends Node

## 回合管理器 — 行动计量条 + 行动顺序排序
##
## 核心逻辑：
##   1. 每回合开始，所有单位行动计量条 += 思维速度
##   2. 行动计量条 >= 10 的单位获得行动机会
##   3. 每次行动消耗 10 点，溢出部分保留
##   4. 同回合内多次行动的单位，按思维速度排序交错行动
##
## 排序算法（贪心）：
##   统计每个单位本回合行动次数 → 每次选择剩余行动次数最多的单位
##   平局时思维速度高的优先
##
## 示例：
##   A=30(3次), B=20(2次), C=15(1次) → AABABC

# =============================================================================
# 信号
# =============================================================================

signal unit_turn_started(unit: TacticsUnit)
signal unit_turn_ended(unit: TacticsUnit)
signal round_started(round_num: int)
signal round_ended(round_num: int)
signal all_actions_done()

# =============================================================================
# 内部状态
# =============================================================================

## 所有注册单位
var _units: Array[TacticsUnit] = []

## 当前回合数
var _current_round: int = 0

## 当前回合行动队列
var _action_queue: Array[TacticsUnit] = []

## 当前行动在队列中的索引
var _current_action_index: int = -1

## 标准行动计量值
const GAUGE_THRESHOLD := 10

## 是否正在战斗中
var _is_battle_active: bool = false


# =============================================================================
# 单位管理
# =============================================================================

## 注册单位
func register_unit(unit: TacticsUnit) -> void:
	_units.append(unit)
	unit.turn_manager = self


## 注销单位
func unregister_unit(unit: TacticsUnit) -> void:
	_units.erase(unit)


## 获取所有存活的单位
func get_alive_units() -> Array[TacticsUnit]:
	var alive: Array[TacticsUnit] = []
	for u in _units:
		if not u.is_dead():
			alive.append(u)
	return alive


## 获取指定队伍的单位
func get_units_by_team(team: String) -> Array[TacticsUnit]:
	var result: Array[TacticsUnit] = []
	for u in _units:
		if u.team == team and not u.is_dead():
			result.append(u)
	return result


## 获取当前行动单位
func get_current_unit() -> TacticsUnit:
	if _current_action_index >= 0 and _current_action_index < _action_queue.size():
		return _action_queue[_current_action_index]
	return null


## 清空所有单位
func clear_units() -> void:
	_units.clear()
	_action_queue.clear()
	_current_action_index = -1
	_current_round = 0
	_is_battle_active = false


# =============================================================================
# 战斗流程
# =============================================================================

## 开始战斗
func start_battle() -> void:
	_current_round = 0
	_is_battle_active = true

	# 初始化所有单位的行动计量条
	for unit in _units:
		unit.action_gauge = 0.0
		unit.actions_this_round = 0

	_next_round()


## 开始下一回合
func _next_round() -> void:
	_current_round += 1
	round_started.emit(_current_round)

	# 检查是否有存活单位
	var alive = get_alive_units()
	if alive.is_empty():
		_is_battle_active = false
		all_actions_done.emit()
		return

	# 计算本回合每个单位的行动次数
	_build_action_queue()

	if _action_queue.is_empty():
		# 没有单位能行动，直接下一回合
		_next_round()
		return

	_current_action_index = 0
	unit_turn_started.emit(_action_queue[0])


## 构建行动队列（贪心算法）
func _build_action_queue() -> void:
	_action_queue.clear()

	# 第一步：计算每个单位的行动次数
	var unit_actions: Array[Dictionary] = []
	for unit in _units:
		if unit.is_dead():
			continue

		# 行动计量条累加思维速度
		unit.action_gauge += float(unit.mental_speed)
		var actions: int = int(unit.action_gauge / GAUGE_THRESHOLD)
		# 保留溢出部分
		unit.action_gauge = fmod(unit.action_gauge, float(GAUGE_THRESHOLD))
		unit.actions_this_round = actions

		if actions > 0:
			unit_actions.append({"unit": unit, "remaining": actions})

	if unit_actions.is_empty():
		return

	# 第二步：贪心排序 — 每次选剩余行动次数最多的
	# 平局时思维速度高的优先
	while not unit_actions.is_empty():
		var best_idx: int = 0
		for i in range(1, unit_actions.size()):
			var a_entry: Dictionary = unit_actions[i]
			var b_entry: Dictionary = unit_actions[best_idx]
			var a_rem: int = a_entry["remaining"]
			var b_rem: int = b_entry["remaining"]
			var a_unit: TacticsUnit = a_entry["unit"]
			var b_unit: TacticsUnit = b_entry["unit"]

			if a_rem > b_rem:
				best_idx = i
			elif a_rem == b_rem:
				if a_unit.mental_speed > b_unit.mental_speed:
					best_idx = i

		var entry: Dictionary = unit_actions[best_idx]
		_action_queue.append(entry["unit"])
		entry["remaining"] -= 1
		if entry["remaining"] <= 0:
			unit_actions.remove_at(best_idx)


## 结束当前单位行动，推进到下一个
func end_current_turn() -> void:
	if not _is_battle_active:
		return

	var current_unit := get_current_unit()
	if current_unit:
		unit_turn_ended.emit(current_unit)

	_current_action_index += 1

	if _current_action_index >= _action_queue.size():
		# 当前回合所有行动结束
		round_ended.emit(_current_round)
		_next_round()
	else:
		# 推进到下一个单位
		unit_turn_started.emit(_action_queue[_current_action_index])


# =============================================================================
# 调试
# =============================================================================

## 获取当前回合的行动队列（调试用）
func get_action_queue() -> Array[TacticsUnit]:
	return _action_queue

## 获取当前回合数
func get_current_round() -> int:
	return _current_round

## 获取行动顺序预览（字符串形式，调试用）
func get_action_order_preview() -> String:
	var parts: Array[String] = []
	for unit in _action_queue:
		parts.append(unit.unit_name if not unit.unit_name.is_empty() else unit.unit_id)
	return " → ".join(parts)