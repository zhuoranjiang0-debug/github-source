## AI 面板：一句话让工具帮你做点东西，但**改不改由你决定**。
##
## 三件事写在界面上，都是有意的：
##
## 1. **当前用的是哪一种**（离线 / 在线）。不写的话，用户会觉得
##    "这工具怎么有时候灵有时候不灵"，反而更难解释。
## 2. **它会做哪些改动**，一条条列出来给人看。人点头它才动手。
## 3. **可以撤销**。应用之后明说一句"按 Ctrl+Z 能整份撤掉"，
##    这样"让 AI 动手"才不吓人。
class_name AIPanel
extends Control

signal request_close

## 界面上的例子。用户第一次打开面板时多半不知道该说什么，
## 给两句能直接点的话，比写一段说明有用。
const EXAMPLES: Array[String] = [
	"一个会飞的紫色小怪",
	"每 2 秒掉一个金币",
]

var session: EditSession = null
var service := AIService.new()

var _input: LineEdit = null
var _status_label: Label = null
var _preview_box: VBoxContainer = null
var _apply_button: Button = null
var _discard_button: Button = null
var _draft: AIDraft = null
var _message: String = ""


func setup(p_session: EditSession) -> void:
	session = p_session
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	rebuild()


func _build() -> void:
	var outer := PanelContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_stylebox_override("panel", _panel_style())
	add_child(outer)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 10)
	scroll.add_child(page)

	# 标题
	var header := HBoxContainer.new()
	page.add_child(header)
	var title := Label.new()
	title.text = "✨ 帮我做一个"
	title.add_theme_font_size_override("font_size", 19)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back := Button.new()
	back.text = "← 回到关卡"
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func() -> void: request_close.emit())
	header.add_child(back)

	# 当前用的是哪一种 —— 如实写出来
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	page.add_child(_status_label)
	var key_row := HBoxContainer.new()
	key_row.add_theme_constant_override("separation", 8)
	page.add_child(key_row)
	var key_button := Button.new()
	key_button.text = "填 key 变聪明"
	key_button.focus_mode = Control.FOCUS_NONE
	# 还没做的东西就明说还没做，别放一个点了没反应的按钮
	key_button.disabled = true
	key_button.tooltip_text = "接在线模型排在 M4-c，还没做。现在用的是离线生成。"
	key_row.add_child(key_button)
	var key_note := Label.new()
	key_note.text = service.mode_hint()
	key_note.add_theme_font_size_override("font_size", 11)
	key_note.add_theme_color_override("font_color", Color(1, 1, 1, 0.38))
	key_row.add_child(key_note)

	# 输入
	var hint := Label.new()
	hint.text = "用一句话说你想加什么。我先给你一份草稿，你看过再决定要不要用。"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.62))
	page.add_child(hint)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 8)
	page.add_child(input_row)
	_input = LineEdit.new()
	_input.placeholder_text = "例如：一个会飞的紫色小怪"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(_text: String) -> void: _on_generate())
	input_row.add_child(_input)
	var generate := Button.new()
	generate.text = "生成草稿"
	generate.focus_mode = Control.FOCUS_NONE
	generate.pressed.connect(_on_generate)
	input_row.add_child(generate)

	# 例子：点一下就换掉输入框里的字，省得用户对着空框发呆
	var examples := HBoxContainer.new()
	examples.add_theme_constant_override("separation", 8)
	page.add_child(examples)
	var examples_label := _muted("试试：")
	examples.add_child(examples_label)
	for example in EXAMPLES:
		var button := Button.new()
		button.text = example
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void:
			_input.text = example
			_on_generate())
		examples.add_child(button)

	page.add_child(HSeparator.new())

	# 预览
	_preview_box = VBoxContainer.new()
	_preview_box.add_theme_constant_override("separation", 6)
	page.add_child(_preview_box)

	# 决定
	var decide := HBoxContainer.new()
	decide.add_theme_constant_override("separation", 8)
	page.add_child(decide)
	_apply_button = Button.new()
	_apply_button.text = "应用到工程"
	_apply_button.focus_mode = Control.FOCUS_NONE
	_apply_button.pressed.connect(func() -> void: apply_current())
	decide.add_child(_apply_button)
	_discard_button = Button.new()
	_discard_button.text = "算了，不要"
	_discard_button.focus_mode = Control.FOCUS_NONE
	_discard_button.pressed.connect(func() -> void: discard_current())
	decide.add_child(_discard_button)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1b2130")
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	return style


func _muted(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	return label


# --------------------------------------------------------------------------
# 对外（界面按钮和自动化测试都走这几个函数）
# --------------------------------------------------------------------------

## 生成一份草稿。测试也调这个，保证测的是用户真实走的那条路。
func generate(prompt: String) -> void:
	if session == null or session.project == null:
		_message = "还没有打开工程"
		rebuild()
		return
	_message = ""
	_draft = service.draft(prompt, session.project)
	rebuild()


## 把当前草稿应用到工程。返回空字符串表示成功，否则是失败原因。
func apply_current() -> String:
	if _draft == null:
		return "还没有草稿"
	var problem := session.apply_ai_draft(_draft)
	if problem.is_empty():
		_message = "已应用「%s」。想反悔就按 Ctrl+Z —— 整份改动一步就能撤掉。" % _draft.title
		_draft = null
		rebuild()
	else:
		_message = problem
		rebuild()
	return problem


func discard_current() -> void:
	_draft = null
	_message = "已放弃这份草稿，工程没有改动。"
	rebuild()


## 供测试使用
func current_draft() -> AIDraft:
	return _draft


func draft_steps() -> String:
	if _draft == null:
		return ""
	return "\n".join(_draft.steps)


func status_message() -> String:
	return _message


func input_line() -> LineEdit:
	return _input


func rebuild() -> void:
	if _status_label == null:
		return
	_status_label.text = "当前：%s" % service.mode_label()
	for child in _preview_box.get_children():
		_preview_box.remove_child(child)
		child.queue_free()

	if _draft != null:
		_build_draft_preview(_draft)
	elif not _message.is_empty():
		_preview_box.add_child(_paragraph(_message, Color(1, 1, 1, 0.7)))
	else:
		_preview_box.add_child(_paragraph(
			"还没有草稿。写一句话，或者点上面那两句例子试试。", Color(1, 1, 1, 0.45)))

	_apply_button.disabled = _draft == null or not _draft.ok()
	_discard_button.disabled = _draft == null


func _build_draft_preview(draft: AIDraft) -> void:
	if not draft.error.is_empty():
		var title := Label.new()
		title.text = "✗ 这句我没听懂"
		title.add_theme_font_size_override("font_size", 15)
		title.add_theme_color_override("font_color", Color("#fbbf24"))
		_preview_box.add_child(title)
		_preview_box.add_child(_paragraph(draft.error, Color(1, 1, 1, 0.72)))
		return

	var title := Label.new()
	title.text = "草稿：%s" % draft.title
	title.add_theme_font_size_override("font_size", 16)
	_preview_box.add_child(title)

	var source := _muted("来自：%s" % service.mode_label())
	source.add_theme_font_size_override("font_size", 11)
	_preview_box.add_child(source)

	var list_title := Label.new()
	list_title.text = "我会做这些："
	list_title.add_theme_font_size_override("font_size", 13)
	list_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.62))
	_preview_box.add_child(list_title)
	for step in draft.steps:
		_preview_box.add_child(_paragraph("· %s" % step, Color(1, 1, 1, 0.8)))

	var checked := _muted("✓ 这份草稿已经过工程校验器检查，应用后还可以撤销。")
	checked.add_theme_font_size_override("font_size", 11)
	checked.add_theme_color_override("font_color", Color("#4ade80"))
	_preview_box.add_child(checked)


func _paragraph(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", color)
	return label


func _on_generate() -> void:
	generate(_input.text if _input != null else "")
