## 逻辑编辑器：在界面上配「当…如果…就…」，不用碰 JSON。
##
## 界面上的每一个控件都是**从词汇表生成的**，不是一个个手写的。
## 词汇表里给每种事件/条件/动作声明了参数（类型、名字、默认值、取值范围），
## 这里照着声明把控件造出来。所以新增一种动作只需要改词汇表，
## 这个文件一行都不用动 —— 这是当初把词汇表做成数据的回报。
class_name RuleEditor
extends Control

signal request_close

const LIST_WIDTH := 380.0

var session: EditSession = null

var _list_box: VBoxContainer = null
var _detail_box: VBoxContainer = null
var _sentence_label: Label = null

var _selected_rule_id: String = ""
var _structure_signature: String = ""
var _summary_labels: Dictionary = {}
## 规则 id → 这条规则身上的问题（校验器给的），用来在界面上标出来
var _issues_by_rule: Dictionary = {}


# --------------------------------------------------------------------------
# 组装
# --------------------------------------------------------------------------

func setup(p_session: EditSession) -> void:
	session = p_session
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_ensure_selection()
	rebuild()
	session.changed.connect(_on_session_changed)


func _build() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	add_child(row)

	# 左边：规则清单
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	left.add_theme_stylebox_override("panel", _panel_style())
	row.add_child(left)
	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 8)
	left.add_child(left_box)

	var header := HBoxContainer.new()
	left_box.add_child(header)
	var title := Label.new()
	title.text = "规则"
	title.add_theme_font_size_override("font_size", 17)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back := Button.new()
	back.text = "← 回到关卡"
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func() -> void: request_close.emit())
	header.add_child(back)

	var add := Button.new()
	add.text = "＋ 新规则"
	add.focus_mode = Control.FOCUS_NONE
	add.pressed.connect(_on_add_rule)
	left_box.add_child(add)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_box.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_list_box)

	# 右边：选中那条规则的详情
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_stylebox_override("panel", _panel_style())
	row.add_child(right)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(detail_scroll)
	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override("separation", 10)
	detail_scroll.add_child(_detail_box)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1b2130")
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	return style


func _ensure_selection() -> void:
	if session == null or session.project == null:
		return
	if session.find_rule(_selected_rule_id) != null:
		return
	_selected_rule_id = session.project.rules[0].id if not session.project.rules.is_empty() else ""


# --------------------------------------------------------------------------
# 刷新
# --------------------------------------------------------------------------

func _on_session_changed() -> void:
	# 形式和值要分开对待：
	# 增删规则/条件/动作、换事件类型 —— 这些改变了"有哪些控件"，必须重建；
	# 只是改了参数值 —— 那就不该重建，否则用户正在拖的数字框会被销毁。
	if _current_signature() != _structure_signature:
		rebuild()
		return
	_update_summaries()
	_update_sentence()


func _current_signature() -> String:
	if session == null or session.project == null:
		return ""
	var parts: Array[String] = [_selected_rule_id]
	for rule in session.project.rules:
		var shape: Array[String] = [rule.id, String(rule.trigger.get("type", ""))]
		for condition in rule.conditions:
			shape.append(String(condition.get("type", "")))
		shape.append("|")
		for action in rule.actions:
			shape.append(String(action.get("type", "")))
		parts.append(",".join(shape))
	return ";".join(parts)


func rebuild() -> void:
	if _list_box == null:
		return
	_structure_signature = _current_signature()
	_summary_labels.clear()
	_clear(_list_box)
	_clear(_detail_box)
	_collect_issues()
	_build_list()
	_build_detail()


## 跑一遍校验，把跟规则有关的问题按规则分组。
##
## 为什么要在界面上显示：校验器从很早就认得"在没有触发对象的事件里用了自身"
## 这类问题，但结果只有自动化测试看得到 —— 用户配出一条**永远不会生效**的
## 规则，界面上一个提示都没有。用户踩到之后才发现的，所以现在补上。
##
## 每次都重跑一遍全工程校验：工程不大，几毫秒的事，
## 换来的是"改完立刻看到"。
func _collect_issues() -> void:
	_issues_by_rule.clear()
	if session == null or session.project == null:
		return
	for issue in ProjectValidator.validate(session.project):
		if not issue.path.begins_with("rules/"):
			continue
		# 路径形如 rules/<id>/actions/0
		var parts := issue.path.split("/")
		if parts.size() < 2:
			continue
		var rule_id := parts[1]
		if not _issues_by_rule.has(rule_id):
			_issues_by_rule[rule_id] = []
		(_issues_by_rule[rule_id] as Array).append(issue.message)


static func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _update_summaries() -> void:
	if session == null or session.project == null:
		return
	for rule in session.project.rules:
		if _summary_labels.has(rule.id) and is_instance_valid(_summary_labels[rule.id]):
			_summary_labels[rule.id].text = RuleVocabulary.describe(rule, session.project)


func _update_sentence() -> void:
	var rule := session.find_rule(_selected_rule_id)
	if rule == null or _sentence_label == null or not is_instance_valid(_sentence_label):
		return
	_sentence_label.text = RuleVocabulary.describe(rule, session.project)


# --------------------------------------------------------------------------
# 左边的规则清单
# --------------------------------------------------------------------------

func _build_list() -> void:
	if session == null or session.project == null:
		return
	if session.project.rules.is_empty():
		var hint := Label.new()
		hint.text = "还没有任何规则。\n点上面的「＋ 新规则」开始。"
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
		_list_box.add_child(hint)
		return

	for rule in session.project.rules:
		_list_box.add_child(_rule_row(rule))


func _rule_row(rule: RuleDef) -> Control:
	var selected := rule.id == _selected_rule_id
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _row_style(selected))

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var enabled := CheckBox.new()
	enabled.button_pressed = rule.enabled
	enabled.tooltip_text = "取消勾选可以暂时停用这条规则"
	enabled.focus_mode = Control.FOCUS_NONE
	enabled.toggled.connect(func(on: bool) -> void:
		session.set_rule_enabled(rule.id, on))
	box.add_child(enabled)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 2)
	box.add_child(column)

	var name_label := Label.new()
	# 有问题（比如"这条规则永远不会生效"）就在名字前打个标记，
	# 用户不必逐条点开才知道哪条配错了
	var flagged: Array = _issues_by_rule.get(rule.id, [])
	name_label.text = ("⚠ %s" % rule.name) if not flagged.is_empty() else rule.name
	name_label.add_theme_font_size_override("font_size", 15)
	if not flagged.is_empty():
		name_label.add_theme_color_override("font_color", Color("#fbbf24"))
	if not rule.enabled:
		name_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	column.add_child(name_label)

	var summary := Label.new()
	summary.text = RuleVocabulary.describe(rule, session.project)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", 12)
	summary.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	column.add_child(summary)
	_summary_labels[rule.id] = summary

	# 整行可点：点击切换选中。用一个透明按钮盖在上面，
	# 比给面板接鼠标事件简单，也不会和里面的勾选框抢
	var pick := Button.new()
	pick.flat = true
	pick.focus_mode = Control.FOCUS_NONE
	pick.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pick.mouse_filter = Control.MOUSE_FILTER_PASS
	pick.pressed.connect(func() -> void:
		_selected_rule_id = rule.id
		rebuild())
	panel.add_child(pick)

	return panel


func _row_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#243044") if selected else Color(1, 1, 1, 0.04)
	if selected:
		style.border_width_left = 4
		style.border_color = Color("#38bdf8")
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


# --------------------------------------------------------------------------
# 右边的规则详情
# --------------------------------------------------------------------------

func _build_detail() -> void:
	var rule := session.find_rule(_selected_rule_id)
	if rule == null:
		var hint := Label.new()
		hint.text = "左边选一条规则，或者新建一条。"
		hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
		_detail_box.add_child(hint)
		return

	_build_name_row(rule)
	_sentence_label = _build_sentence(rule)
	_build_rule_issues(rule)

	_detail_box.add_child(HSeparator.new())
	_detail_box.add_child(_section_title("当（事件）"))
	var trigger_type := String(rule.trigger.get("type", ""))
	var trigger_def := RuleVocabulary.trigger_def(trigger_type)
	_detail_box.add_child(_type_picker("event", RuleVocabulary.TRIGGERS,
		trigger_type,
		func(type: String) -> void:
			session.push_undo("修改事件")
			session.set_rule_trigger_type(rule.id, type)))
	_build_params(_detail_box, rule.trigger, trigger_def,
		func(key: String, value: Variant) -> void:
			_pick_undo()
			session.set_rule_trigger_param(rule.id, key, value),
		"trigger", trigger_type)

	_detail_box.add_child(HSeparator.new())
	_detail_box.add_child(_section_title("如果（条件）"))
	if rule.conditions.is_empty():
		_detail_box.add_child(_muted("没有任何条件，事件一发生就会执行。"))
	for i in rule.conditions.size():
		_detail_box.add_child(_statement_block(rule, "condition", i, rule.conditions[i]))
	var add_condition := Button.new()
	add_condition.text = "＋ 加一个条件"
	add_condition.focus_mode = Control.FOCUS_NONE
	add_condition.pressed.connect(func() -> void:
		session.add_rule_condition(rule.id, RuleVocabulary.DEFAULT_CONDITION))
	_detail_box.add_child(add_condition)

	_detail_box.add_child(HSeparator.new())
	_detail_box.add_child(_section_title("就（动作）"))
	if rule.actions.is_empty():
		_detail_box.add_child(_muted("还没有动作，这条规则不会产生任何效果。"))
	for i in rule.actions.size():
		_detail_box.add_child(_statement_block(rule, "action", i, rule.actions[i]))
	var add_action := Button.new()
	add_action.text = "＋ 加一个动作"
	add_action.focus_mode = Control.FOCUS_NONE
	add_action.pressed.connect(func() -> void:
		session.add_rule_action(rule.id, RuleVocabulary.DEFAULT_ACTION))
	_detail_box.add_child(add_action)

	_detail_box.add_child(HSeparator.new())
	var remove := Button.new()
	remove.text = "删除这条规则"
	remove.focus_mode = Control.FOCUS_NONE
	remove.pressed.connect(func() -> void:
		session.push_undo("删除规则")
		if session.remove_rule(rule.id):
			_selected_rule_id = ""
			_ensure_selection()
			rebuild())
	_detail_box.add_child(remove)


## 这条规则身上的问题，直接写在句子下面。
##
## 用户配完一条规则，最该立刻知道的是"它到底会不会生效"。
## 校验器早就能认出这类问题，只是以前没有任何地方显示过。
func _build_rule_issues(rule: RuleDef) -> void:
	var flagged: Array = _issues_by_rule.get(rule.id, [])
	for message in flagged:
		var label := Label.new()
		label.text = "⚠ %s" % String(message)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color("#fbbf24"))
		_detail_box.add_child(label)


func _build_name_row(rule: RuleDef) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_detail_box.add_child(row)

	var edit := LineEdit.new()
	edit.text = rule.name
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_size_override("font_size", 17)
	edit.text_submitted.connect(func(text: String) -> void: _rename_rule(rule.id, text))
	edit.focus_exited.connect(func() -> void: _rename_rule(rule.id, edit.text))
	row.add_child(edit)

	var enabled := CheckBox.new()
	enabled.text = "启用"
	enabled.button_pressed = rule.enabled
	enabled.focus_mode = Control.FOCUS_NONE
	enabled.toggled.connect(func(on: bool) -> void:
		session.push_undo("启用/停用规则")
		session.set_rule_enabled(rule.id, on))
	row.add_child(enabled)


func _rename_rule(rule_id: String, text: String) -> void:
	var name := text.strip_edges()
	if name.is_empty():
		rebuild()
		return
	session.push_undo("重命名规则")
	session.set_rule_name(rule_id, name)


func _build_sentence(rule: RuleDef) -> Label:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sentence_style())
	var label := Label.new()
	label.text = RuleVocabulary.describe(rule, session.project)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	panel.add_child(label)
	_detail_box.add_child(panel)
	return label


func _sentence_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.22, 0.74, 0.97, 0.12)
	style.border_width_left = 4
	style.border_color = Color("#38bdf8")
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


## 一条条件或一个动作：上排是"是什么类型"，下排是它的参数
func _statement_block(rule: RuleDef, kind: String, index: int, statement: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _row_style(false))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	box.add_child(head)

	var vocabulary := RuleVocabulary.CONDITIONS if kind == "condition" else RuleVocabulary.ACTIONS
	var type := String(statement.get("type", ""))
	head.add_child(_type_picker(kind, vocabulary, type,
		func(new_type: String) -> void:
			_replace_statement(rule.id, kind, index, new_type)))
	head.add_child(_spacer())

	# 「反向」：这条条件要**不成立**才算通过。
	# 数据里一直有这个字段（示例里的「松开方向键就停下」就在用它），
	# 但以前界面上没地方勾，只能手改 JSON —— 于是那句话读出来还是正着的，
	# 写着"正按住左、正按住右"，实际执行的却是"两个都没按住"。
	if kind == "condition":
		var negate := CheckBox.new()
		negate.text = "反向（不满足）"
		negate.tooltip_text = "勾上以后，这条条件要「不成立」才算通过"
		negate.button_pressed = bool(statement.get("negate", false))
		negate.focus_mode = Control.FOCUS_NONE
		negate.toggled.connect(func(on: bool) -> void:
			_pick_undo()
			session.set_rule_condition_param(rule.id, index, "negate", on))
		head.add_child(negate)

	var remove := Button.new()
	remove.text = "×"
	remove.tooltip_text = "删掉这一条"
	remove.focus_mode = Control.FOCUS_NONE
	remove.pressed.connect(func() -> void:
		if kind == "condition":
			session.remove_rule_condition(rule.id, index)
		else:
			session.remove_rule_action(rule.id, index))
	head.add_child(remove)

	var def := RuleVocabulary.condition_def(type) if kind == "condition" \
		else RuleVocabulary.action_def(type)
	_build_params(box, statement, def, func(key: String, value: Variant) -> void:
		_pick_undo()
		if kind == "condition":
			session.set_rule_condition_param(rule.id, index, key, value)
		else:
			session.set_rule_action_param(rule.id, index, key, value),
		kind, String(rule.trigger.get("type", "")))
	return panel


## 换类型 = 重新生成这一条（旧参数整个丢掉）
func _replace_statement(rule_id: String, kind: String, index: int, new_type: String) -> void:
	session.push_undo("修改%s" % ("条件" if kind == "condition" else "动作"))
	if kind == "condition":
		var rule := session.find_rule(rule_id)
		if rule == null or index >= rule.conditions.size():
			return
		rule.conditions[index] = EditSession.build_statement(
			RuleVocabulary.condition_def(new_type), new_type)
	else:
		var rule := session.find_rule(rule_id)
		if rule == null or index >= rule.actions.size():
			return
		rule.actions[index] = EditSession.build_statement(
			RuleVocabulary.action_def(new_type), new_type)
	session._mark_dirty()
	rebuild()


# --------------------------------------------------------------------------
# 参数表单：全部由词汇表生成
# --------------------------------------------------------------------------

## host 是这些控件要挂到哪里：事件参数挂在详情里，
## 条件/动作的参数挂在各自的语句块里，所以必须由调用者指定。
## place 和 trigger_type 只用来决定对象选择器里该列哪些选项 ——
## 「自身」「对方」能不能用，取决于事件给不给触发对象。
func _build_params(host: Control, statement: Dictionary, def: Dictionary,
		on_change: Callable, place: String, trigger_type: String) -> void:
	var params: Dictionary = def.get("params", {})
	if params.is_empty():
		return
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	host.add_child(box)
	for key in params:
		var spec: Dictionary = params[key]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var label := Label.new()
		label.text = String(spec.get("label", key))
		label.custom_minimum_size = Vector2(120, 0)
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		row.add_child(label)
		var current: Variant = statement.get(key, spec.get("default"))
		row.add_child(_make_widget(spec, current, key, on_change, place, trigger_type))


func _make_widget(spec: Dictionary, current: Variant, key: String, on_change: Callable,
		place: String, trigger_type: String) -> Control:
	match String(spec.get("type", "string")):
		"number", "int":
			var spin := SpinBox.new()
			spin.min_value = float(spec.get("min", -999999.0))
			spin.max_value = float(spec.get("max", 999999.0))
			spin.step = 1.0
			spin.value = float(current) if current != null else 0.0
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spin.focus_mode = Control.FOCUS_NONE
			spin.value_changed.connect(func(value: float) -> void: on_change.call(key, value))
			return spin
		"bool":
			var check := CheckBox.new()
			check.button_pressed = bool(current)
			check.focus_mode = Control.FOCUS_NONE
			check.toggled.connect(func(value: bool) -> void: on_change.call(key, value))
			return check
		"selector":
			var options := session.selector_options(place, trigger_type)
			return _selector_choice(options, String(current),
				func(value: String) -> void: on_change.call(key, value))
		"enum":
			var values: Array[String] = []
			var labels: Array[String] = []
			var option_labels: Dictionary = spec.get("option_labels", {})
			for option in spec.get("options", []):
				values.append(String(option))
				labels.append(String(option_labels.get(String(option), option)))
			return _choice(values, labels, String(current),
				func(value: String) -> void: on_change.call(key, value))
		"entity":
			var values: Array[String] = []
			var labels: Array[String] = []
			if session.project != null:
				for def in session.project.entities:
					values.append(def.id)
					labels.append(def.name)
			return _choice(values, labels, String(current),
				func(value: String) -> void: on_change.call(key, value))
		"scene":
			var values: Array[String] = []
			var labels: Array[String] = []
			if session.project != null:
				for scene in session.project.scenes:
					values.append(scene.id)
					labels.append(scene.name)
			return _choice(values, labels, String(current),
				func(value: String) -> void: on_change.call(key, value))
		"asset":
			var values: Array[String] = []
			var labels: Array[String] = []
			if session.project != null:
				for asset in session.project.assets:
					values.append(asset.id)
					labels.append(asset.name)
			return _choice(values, labels, String(current),
				func(value: String) -> void: on_change.call(key, value))
		_:
			var edit := LineEdit.new()
			edit.text = String(current)
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			edit.text_submitted.connect(func(text: String) -> void: on_change.call(key, text))
			edit.focus_exited.connect(func() -> void: on_change.call(key, edit.text))
			return edit


## 通用的下拉选择框。on_pick 只收一个参数（选中的值）。
##
## 这里刻意不额外传"这是哪个参数"——调用方用闭包自己带上就行。
## 之前多传了一个参数，结果回调调用失败：下拉框照样换文字，
## 底下的数据却一点没变，「间隔」「概率」这些参数栏也就不会跟着换出来。
func _choice(values: Array[String], labels: Array[String], current: String,
		on_pick: Callable) -> OptionButton:
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.focus_mode = Control.FOCUS_NONE

	# 当前值可能不在候选里（手改过 JSON，或者对应的东西已经被删掉）。
	# 补一项显示出来，免得用户的选择凭空消失、被悄悄改成别的。
	var entries := values.duplicate()
	var texts := labels.duplicate()
	var index := entries.find(current)
	if index < 0:
		index = entries.size()
		entries.append(current)
		texts.append("当前值：%s（其他选项里没有）" % current)
	for i in entries.size():
		picker.add_item(texts[i], i)
	picker.selected = index
	picker.item_selected.connect(func(picked: int) -> void:
		on_pick.call(entries[picked]))
	return picker


## 对象选择器专用的下拉框：支持分组标题。
##
## 和 _choice 分开写，是因为这里要插分隔行（"所有这一类" / "就这一个对象"），
## 而分隔行也占一个选项位，值到项的下标映射得单独记一份。
## 列表长了以后，"一半的选项长得一模一样"正是最劝退的地方。
func _selector_choice(options: Array[Dictionary], current: String,
		on_pick: Callable) -> OptionButton:
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.focus_mode = Control.FOCUS_NONE

	var values: Array[String] = []
	# 值在 values 里的下标 → 这个值落在下拉框的第几项
	var item_of_value: Array[int] = []
	for option in options:
		if option.has("separator"):
			picker.add_separator(String(option["separator"]))
			continue
		var value := String(option.get("value", ""))
		values.append(value)
		picker.add_item(String(option.get("label", value)))
		item_of_value.append(picker.item_count - 1)
		if option.has("tooltip"):
			picker.set_item_tooltip(picker.item_count - 1, String(option["tooltip"]))

	# 当前值可能不在候选里（手改过 JSON，或者对应的东西已经被删掉）。
	# 补一项显示出来，免得用户的选择凭空消失、被悄悄改成别的。
	var index := values.find(current)
	if index < 0:
		values.append(current)
		picker.add_item("当前值：%s（其他选项里没有）" % current)
		item_of_value.append(picker.item_count - 1)
		index = values.size() - 1
	picker.selected = item_of_value[index]

	picker.item_selected.connect(func(item: int) -> void:
		var pos := item_of_value.find(item)
		if pos >= 0:
			on_pick.call(values[pos]))
	return picker


func _type_picker(kind: String, vocabulary: Dictionary, current: String,
		on_pick: Callable) -> OptionButton:
	var values: Array[String] = []
	var labels: Array[String] = []
	# 字典的键顺序就是词汇表里的声明顺序，按那个顺序列出来
	for type in vocabulary:
		values.append(type)
		var def: Dictionary = vocabulary[type]
		labels.append(String(def.get("label", type)))
	var picker := _choice(values, labels, current, on_pick)
	picker.custom_minimum_size = Vector2(220, 0)
	return picker


func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	return label


func _muted(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	return label


func _spacer() -> Control:
	var control := Control.new()
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return control


## 连续调节合并成一步撤销（和属性面板同一套做法）
var _last_undo_ms: int = 0

func _pick_undo() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_undo_ms > 700:
		session.push_undo("修改规则")
	_last_undo_ms = now


func _on_add_rule() -> void:
	var rule := session.add_rule()
	if rule != null:
		_selected_rule_id = rule.id
		rebuild()
