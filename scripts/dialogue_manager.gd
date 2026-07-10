extends Node
class_name DialogueManager

## 对话管理器：加载 JSON 剧本、解析节点、执行效果、跳转分支

signal dialogue_updated(data: Dictionary)
signal dialogue_ended
signal choices_shown(choices: Array)
signal node_changed(node_id: String)
## 战斗触发信号，携带战斗配置 JSON 文件路径
signal battle_started(config_path: String)

var _story_data: Dictionary = {}
var _current_node_id: String = ""
var _is_playing: bool = false
## 当前加载的剧本文件路径
var _story_file_path: String = ""
## 战斗等待标志：为 true 时暂停剧情推进，等待战斗结果
var _is_waiting_battle: bool = false

## 加载剧本 JSON 文件
func load_story(file_path: String) -> bool:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("DialogueManager: 无法加载剧本文件: " + file_path)
		return false

	var json_text = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_error("DialogueManager: JSON 解析失败: " + json.get_error_message())
		return false

	_story_data = json.data
	_story_file_path = file_path
	_current_node_id = _story_data.get("start_node", "")
	_is_playing = true
	return true

## 开始剧本
func start_story():
	_is_playing = true
	_current_node_id = _story_data.get("start_node", "")
	_advance_to_node(_current_node_id)

## 获取当前节点数据
func get_current_node() -> Dictionary:
	if not _is_playing or _current_node_id.is_empty():
		return {}
	var nodes = _story_data.get("nodes", {})
	return nodes.get(_current_node_id, {})

## 推进到下一个节点
func advance():
	if not _is_playing:
		return

	# 战斗等待中：不推进剧情，等待战斗结果
	if _is_waiting_battle:
		return

	var node = get_current_node()
	if node.is_empty():
		dialogue_ended.emit()
		return

	# 如果有选项，不发信号推进，而是等待用户选择
	if node.has("choices") and node["choices"].size() > 0:
		choices_shown.emit(node["choices"])
		return

	# 否则直接下一个节点
	_next_node()

## 用户选择某个选项
func select_choice(choice_index: int):
	var node = get_current_node()
	if node.is_empty():
		return

	var choices = node.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size():
		return

	var choice = choices[choice_index]

	# 执行选项的效果
	_execute_effects(choice.get("effects", []))

	# 跳转到选项指定的下一个节点（支持 string 或 {file, node}）
	var next_target = choice.get("next", "")
	_advance_to_target(next_target)

## 内部：推进到下一个节点
func _next_node():
	var node = get_current_node()
	if node.is_empty():
		dialogue_ended.emit()
		return

	# 执行当前节点的效果
	_execute_effects(node.get("effects", []))

	# 如果战斗效果已触发，暂停推进，等待战斗结果
	if _is_waiting_battle:
		return

	# 找到下一个节点（支持 string 或 {file, node} 两种格式）
	var next_target = node.get("next", "")
	if next_target is String and next_target.is_empty():
		dialogue_ended.emit()
		return

	_advance_to_target(next_target)


## 解析跳转目标为 {file, node} 格式
## @param target: String（同文件节点ID）或 Dictionary（{file, node} 跨文件）
func _resolve_target(target: Variant) -> Dictionary:
	if target is String:
		return {"file": _story_file_path, "node": target}
	elif target is Dictionary:
		return {
			"file": target.get("file", _story_file_path),
			"node": target.get("node", "")
		}
	else:
		return {"file": _story_file_path, "node": ""}


## 跳转到指定目标（支持跨文件）
func _advance_to_target(target: Variant):
	var resolved := _resolve_target(target)
	var file_path: String = resolved["file"]
	var node_id: String = resolved["node"]

	if node_id.is_empty():
		dialogue_ended.emit()
		return

	# 如果目标文件与当前文件不同，加载新文件
	if file_path != _story_file_path:
		if not _load_story_file(file_path):
			dialogue_ended.emit()
			return

	# 在当前剧本数据中查找节点
	var nodes = _story_data.get("nodes", {})
	if not nodes.has(node_id):
		push_error("DialogueManager: 节点不存在: " + node_id + " (文件: " + _story_file_path + ")")
		dialogue_ended.emit()
		return

	_current_node_id = node_id
	var node = nodes[node_id]

	# 记录访问过的节点
	var visited = GameState.get_flag("visited_nodes", [])
	if not visited.has(node_id):
		visited.append(node_id)
	GameState.set_flag("visited_nodes", visited)

	# 执行节点效果（跳过 battle，battle 在玩家点击推进时由 _next_node 处理）
	_execute_effects(node.get("effects", []), true)

	# 发出信号
	node_changed.emit(node_id)
	dialogue_updated.emit(node)

	# 如果节点有选项，发出选项信号
	if node.has("choices") and node["choices"].size() > 0:
		choices_shown.emit(node["choices"])


## 加载剧本文件（不改变 _current_node_id）
func _load_story_file(file_path: String) -> bool:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("DialogueManager: 无法加载剧本文件: " + file_path)
		return false

	var json_text = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_error("DialogueManager: JSON 解析失败: " + json.get_error_message())
		return false

	_story_data = json.data
	_story_file_path = file_path
	return true


## 内部：跳转到指定节点（兼容旧接口，仅限同文件）
func _advance_to_node(node_id: String):
	_advance_to_target(node_id)

## 执行效果列表
## @param skip_battle: 跳过战斗效果，推迟到玩家点击推进时处理
func _execute_effects(effects: Array, skip_battle: bool = false):
	for effect in effects:
		_execute_effect(effect, skip_battle)

## 执行单个效果
func _execute_effect(effect: Dictionary, skip_battle: bool = false):
	var type = effect.get("type", "")

	match type:
		"set_flag":
			var key = effect.get("key", "")
			var value = effect.get("value")
			GameState.set_flag(key, value)

		"battle":
			if skip_battle:
				return
			# 战斗效果：暂存配置路径，发出信号，暂停剧情推进
			var config_path: String = effect.get("config", "")
			if config_path.is_empty():
				push_error("DialogueManager: battle 效果缺少 config 字段")
				return
			# 设置等待标志，阻止 advance() 继续推进
			_is_waiting_battle = true
			# 发出信号，由 GameScreen 接收并显示战斗棋盘
			battle_started.emit(config_path)

		"bg", "bgm", "sfx", "char":
			# 这些效果由 GameScreen 通过信号接收并处理
			pass

		_:
			push_warning("DialogueManager: 未知效果类型: " + type)

## 获取所有节点（用于剧情树显示）
func get_all_nodes() -> Dictionary:
	return _story_data.get("nodes", {})

## 获取当前节点 ID
func get_current_node_id() -> String:
	return _current_node_id

## 获取当前剧本文件路径
func get_story_file_path() -> String:
	return _story_file_path

## 是否正在播放
func is_playing() -> bool:
	return _is_playing

## 停止播放
func stop():
	_is_playing = false
	_current_node_id = ""

## 跳转到指定节点（用于剧情树回溯）
## @param node_id: 目标节点 ID
## @param file_path: 目标剧本文件路径，空字符串表示当前文件
func jump_to_node(node_id: String, file_path: String = ""):
	# 如果指定了文件且与当前不同，加载目标文件
	if not file_path.is_empty() and file_path != _story_file_path:
		if not _load_story_file(file_path):
			return

	var nodes = _story_data.get("nodes", {})
	if not nodes.has(node_id):
		push_error("DialogueManager: 节点不存在: " + node_id)
		return

	_current_node_id = node_id
	var node = nodes[node_id]
	_is_playing = true

	node_changed.emit(node_id)
	dialogue_updated.emit(node)

	# 如果有选项，发出选项信号
	if node.has("choices") and node["choices"].size() > 0:
		choices_shown.emit(node["choices"])


# =============================================================================
# 战斗系统 — 战斗结果回调
# =============================================================================

## 战斗结束后由 GameScreen 调用，根据结果跳转到对应剧情分支
## @param result: 结构化结果字典 {"type": "win"|"lose", "branch": "分支ID", "next": 目标}
##                next 支持两种格式：string（同文件节点ID）或 {file, node}（跨文件引用）
##                或兼容旧版字符串 "win" / "lose"
func resolve_battle_result(result: Variant) -> void:
	# 清除等待标志
	_is_waiting_battle = false

	# 兼容旧版字符串参数
	var outcome_type: String
	var next_target: Variant
	if result is String:
		outcome_type = result
		next_target = ""
	elif result is Dictionary:
		outcome_type = result.get("type", "")
		next_target = result.get("next", "")
	else:
		push_error("DialogueManager: 无效的战斗结果类型")
		dialogue_ended.emit()
		return

	# 如果结构化结果中已包含 next，直接使用
	if next_target is String and not next_target.is_empty():
		_advance_to_target(next_target)
		return
	elif next_target is Dictionary:
		_advance_to_target(next_target)
		return

	# 回退到旧逻辑：从当前节点的 battle 效果中查找分支
	var node := get_current_node()
	if node.is_empty():
		dialogue_ended.emit()
		return

	var effects: Array = node.get("effects", [])
	for effect in effects:
		if effect.get("type") == "battle":
			if outcome_type == "win":
				next_target = effect.get("win_next", "")
			else:
				next_target = effect.get("lose_next", "")
			break

	# 判断 next_target 是否为空（支持 string 和 dict 两种格式）
	var is_empty: bool = false
	if next_target is String:
		is_empty = next_target.is_empty()
	elif next_target is Dictionary:
		is_empty = next_target.get("node", "").is_empty()
	else:
		is_empty = true

	if is_empty:
		dialogue_ended.emit()
		return

	# win_next / lose_next 也支持 string 或 {file, node}
	_advance_to_target(next_target)
