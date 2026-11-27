## 编辑器主界面。
##
## 布局刻意保持扁平：上面一条工具栏，中间画布，下面一条素材栏。
## 移动端将来会把上下两条改成可收起的抽屉，但结构不变。
class_name EditorScreen
extends Control

signal request_play

const PALETTE_HEIGHT := 76.0
## 工具栏按钮的最小高度。触屏上按钮要比鼠标时代大一圈，
## 这是"平板上点得准"最直接的一步，也是这次唯一改动布局的地方。
const TOOL_BUTTON_HEIGHT := 38.0

var session: EditSession = null
var default_save_path: String = ""

var _canvas: EditCanvas = null
var _inspector: InspectorPanel = null
var _rule_editor: RuleEditor = null
var _ai_panel: AIPanel = null
var _middle: HBoxContainer = null
var _palette_bar: Control = null
var _logic_button: Button = null
var _ai_button: Button = null

## 编辑区一次只显示一块：关卡 / 逻辑 / AI。
## 三个都是"占满整块编辑区"的独立心智模式，混在一起只会互相挤。
const MODE_LEVEL := "level"
const MODE_RULES := "rules"
const MODE_AI := "ai"
var _mode: String = MODE_LEVEL
var _title_label: Label = null
var _scene_picker: OptionButton = null
var _palette_box: HBoxContainer = null
var _status_label: Label = null
var _undo_button: Button = null
var _redo_button: Button = null
var _delete_button: Button = null

var _palette_signature: String = ""
var _scene_signature: String = ""
var _flash_message: String = ""
var _flash_until: int = 0


func _ready() -> void:
	_fill_viewport()
	var viewport := get_viewport()
	if viewport != null:
		viewport.size_changed.connect(_fill_viewport)


## EditorScreen 的父节点是 Node2D 而不是 Control，
## 这种情况下锚点不会自动生效，尺寸会一直是 0，
## 界面就会缩成左上角的一小块。必须自己跟上视口尺寸。
func _fill_viewport() -> void:
	var viewport := get_viewport()
	var area := Vector2(1280, 720)
	if viewport != null:
		area = viewport.get_visible_rect().size
	position = Vector2.ZERO
	size = area


# --------------------------------------------------------------------------
# 组装
# --------------------------------------------------------------------------

func setup(p_session: EditSession, p_default_save_path: String) -> void:
	session = p_session
	default_save_path = p_default_save_path
	_fill_viewport()
	_build()
	session.changed.connect(_on_session_changed)
	session.scene_switched.connect(_on_scene_switched)
	_refresh_palette()
	_refresh_scenes()
	_refresh()


## 供自动化测试访问画布，用来模拟拖放等交互
func canvas() -> EditCanvas:
	return _canvas


## 供自动化测试访问属性面板
func inspector() -> InspectorPanel:
	return _inspector


## 供自动化测试访问逻辑编辑器
func rule_editor() -> RuleEditor:
	return _rule_editor


## 供自动化测试访问 AI 面板
func ai_panel() -> AIPanel:
	return _ai_panel


## 素材栏里当前列出了哪些实体
func palette_entity_ids() -> Array[String]:
	var ids: Array[String] = []
	if _palette_box == null:
		return ids
	for child in _palette_box.get_children():
		if child is PaletteItem:
			ids.append((child as PaletteItem).entity_id)
	return ids


func _build() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_build_toolbar())

	_middle = HBoxContainer.new()
	_middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_middle.add_theme_constant_override("separation", 0)
	root.add_child(_middle)

	_canvas = EditCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.selection_changed.connect(_on_selection_changed)
	_canvas.instance_placed.connect(_on_instance_placed)
	_middle.add_child(_canvas)
	_canvas.set_session(session)

	_inspector = InspectorPanel.new()
	_middle.add_child(_inspector)
	_inspector.setup(session)

	_palette_bar = _build_palette_bar()
	root.add_child(_palette_bar)

	# 逻辑编辑器占满整块编辑区。一条规则有「事件 + 若干条件 + 若干动作」，
	# 塞进侧栏会挤成一团；而且「编辑关卡」和「编辑逻辑」本来就是
	# 两个不同的心智模式，分开比混在一起清楚。
	_rule_editor = RuleEditor.new()
	_rule_editor.visible = false
	_rule_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rule_editor.request_close.connect(func() -> void: _set_rule_mode(false))
	root.add_child(_rule_editor)
	_rule_editor.setup(session)

	# AI 面板同样占满整块编辑区。它的界面比逻辑界面简单得多，
	# 但"跟 AI 说话"和"改关卡"是两种心态，放在一起会两边都做不好。
	_ai_panel = AIPanel.new()
	_ai_panel.visible = false
	_ai_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ai_panel.request_close.connect(func() -> void: _set_ai_mode(false))
	root.add_child(_ai_panel)
	_ai_panel.setup(session)


func _build_toolbar() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bar_style())
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 17)
	box.add_child(_title_label)

	_scene_picker = OptionButton.new()
	_scene_picker.tooltip_text = "切换关卡"
	_scene_picker.focus_mode = Control.FOCUS_NONE
	_scene_picker.item_selected.connect(_on_scene_selected)
	box.add_child(_scene_picker)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	_undo_button = _tool_button("撤销", _on_undo, "撤销上一步 (Ctrl+Z)")
	box.add_child(_undo_button)
	_redo_button = _tool_button("重做", _on_redo, "重做 (Ctrl+Y)")
	box.add_child(_redo_button)
	_delete_button = _tool_button("删除", _on_delete, "删除选中的对象 (Delete)")
	box.add_child(_delete_button)
	box.add_child(_tool_button("保存", _on_save, "保存工程 (Ctrl+S)"))

	_logic_button = _tool_button("逻辑",
		func() -> void: _set_rule_mode(_mode != MODE_RULES),
		"编辑游戏逻辑：当……如果……就……")
	box.add_child(_logic_button)

	_ai_button = _tool_button("✨ AI",
		func() -> void: _set_ai_mode(not _is_ai_mode()),
		"一句话让工具帮你做一个敌人、或者让天上掉金币")
	_ai_button.add_theme_color_override("font_color", Color("#c084fc"))
	box.add_child(_ai_button)

	var play := _tool_button("▶ 运行", _on_play, "立刻试玩 (F5)")
	play.add_theme_color_override("font_color", Color("#4ade80"))
	box.add_child(play)
	return panel


func _build_palette_bar() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bar_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.62))
	box.add_child(_status_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, PALETTE_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	_palette_box = HBoxContainer.new()
	_palette_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_palette_box)
	return panel


func _bar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1b2130")
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _tool_button(text: String, callback: Callable, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(0, TOOL_BUTTON_HEIGHT)
	# 按钮不抢焦点，免得键盘快捷键被它吃掉
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button


# --------------------------------------------------------------------------
# 刷新
# --------------------------------------------------------------------------

func _on_session_changed() -> void:
	if _canvas != null:
		_canvas.refresh()
	_refresh_palette()
	_refresh_scenes()
	_refresh()


func _on_scene_switched(_index: int) -> void:
	if _canvas != null:
		_canvas.refresh()
	_refresh()


func _refresh() -> void:
	if session == null or session.project == null:
		return
	var mark := " •" if session.dirty else ""
	_title_label.text = "%s%s" % [session.project.name, mark]
	_undo_button.disabled = not session.can_undo()
	_redo_button.disabled = not session.can_redo()
	_delete_button.disabled = session.selected_instance_id.is_empty()
	_refresh_status()


func _refresh_status() -> void:
	if _flash_message != "":
		_status_label.text = _flash_message
		return
	var selected := session.find_instance(session.selected_instance_id)
	var type_def := session.selected_entity()
	if type_def != null:
		# 选中"这一类"时，状态栏说清影响范围 —— 和右边面板的标语对应
		_status_label.text = "已选中「%s」这一类：场上 %d 个，改动会影响它们" \
			% [type_def.name, session.instance_count_of(type_def.id)] + _project_warning_note()
		return
	if selected == null:
		_status_label.text = "把下面的对象拖到画布上；点击选中、拖动移动；双指或滚轮缩放，拖动空白处平移" \
			+ _project_warning_note()
		return
	var def := session.project.find_entity(selected.entity_id)
	var name := def.name if def != null else selected.entity_id
	# 叠了好几个对象时补一句提示：否则用户点来点去只看到同一个选中框，
	# 会以为底下那个不见了 —— 而它一直都在
	var overlap := _canvas.overlap_note()
	_status_label.text = ("已选中：%s    位置 %d, %d    %s按 Delete 删除，按 Ctrl+Z 撤销" \
		% [name, int(selected.x), int(selected.y), overlap]) + _project_warning_note()


## 工程级别的提醒显示在状态栏里（规则自己的问题在逻辑界面里逐条显示）。
##
## 用户报过一个很典型的：老工程里的「地面」没标成"地面"，掉落物穿过一切
## 掉出画面 —— 校验器其实早就认得出，但提醒以前只写在自动化测试里，
## 界面上一个字都没有。**认得出却看不见，等于没认出来。**
func _project_warning_note() -> String:
	var messages: Array[String] = []
	for issue in ProjectValidator.validate(session.project):
		if issue.path.begins_with("rules/") or issue.level != ProjectValidator.LEVEL_WARNING:
			continue
		messages.append(issue.message)
	if messages.is_empty():
		return ""
	var more := "" if messages.size() == 1 else "（还有 %d 条）" % (messages.size() - 1)
	return "        ⚠ %s%s" % [messages[0], more]


func _refresh_scenes() -> void:
	var signature := ""
	for scene in session.scenes():
		signature += scene.id + "|"
	if signature == _scene_signature:
		return
	_scene_signature = signature
	_scene_picker.clear()
	for i in session.scenes().size():
		_scene_picker.add_item(session.scenes()[i].name, i)
	_scene_picker.selected = session.current_scene_index()


func _refresh_palette() -> void:
	if session == null or session.project == null:
		return
	var signature := ""
	for def in session.project.entities:
		signature += def.id + "|"
	if signature == _palette_signature:
		return
	_palette_signature = signature

	for child in _palette_box.get_children():
		child.queue_free()
	for def in session.project.entities:
		var item := PaletteItem.new(def.id, def.name, Color(def.color))
		item.pressed.connect(_on_palette_pressed.bind(def.id, item))
		_palette_box.add_child(item)


## 点素材栏里的一项 = 选中"这一类"（拖到画布上仍然是放置一个）。
## 拖完的那一下不算"点击"，否则每次放置都会顺手把面板切到类型面板。
func _on_palette_pressed(entity_id: String, item: PaletteItem) -> void:
	if item.dragged:
		item.dragged = false
		return
	if session == null:
		return
	session.select_entity(entity_id)
	var def := session.project.find_entity(entity_id)
	if def != null:
		_flash("正在编辑「%s」这一类" % def.name)


func _flash(message: String) -> void:
	_flash_message = message
	_flash_until = Time.get_ticks_msec() + 3000
	_refresh_status()


func _process(_delta: float) -> void:
	if _flash_message != "" and Time.get_ticks_msec() > _flash_until:
		_flash_message = ""
		_refresh_status()


# --------------------------------------------------------------------------
# 操作
# --------------------------------------------------------------------------

func _on_selection_changed(_instance_id: String) -> void:
	if _inspector != null and is_instance_valid(_inspector):
		_inspector.rebuild()
	_refresh()


func _on_instance_placed(entity_id: String, world_pos: Vector2) -> void:
	var placed := session.add_instance(entity_id, world_pos)
	if placed == null:
		return
	var def := session.project.find_entity(entity_id)
	var name := def.name if def != null else entity_id
	_flash("已放置「%s」于 %d, %d" % [name, int(world_pos.x), int(world_pos.y)])


func _on_scene_selected(index: int) -> void:
	session.select_scene(index)


func _on_undo() -> void:
	if session.undo() and _canvas != null:
		_canvas.refresh()


func _on_redo() -> void:
	if session.redo() and _canvas != null:
		_canvas.refresh()


func _on_delete() -> void:
	if session.selected_instance_id.is_empty():
		return
	if session.remove_instance(session.selected_instance_id):
		_canvas.refresh()
		_flash("已删除")


func _on_save() -> void:
	var was_sample := session.is_bundled_sample()
	var saved_to := session.save_project(default_save_path)
	if saved_to.is_empty():
		_flash("保存失败：%s" % session.last_error)
	elif was_sample:
		_flash("这是内置示例，不能覆盖；已另存为 %s" % saved_to.get_file())
	else:
		_flash("已保存到 %s" % saved_to.get_file())


func _on_play() -> void:
	request_play.emit()


## 在「编辑关卡 / 编辑逻辑 / AI」三块界面之间切换。
##
## 一次只显示一块：这三件事对应三种心态，混在一起两边都做不好。
func _set_mode(mode: String) -> void:
	_mode = mode
	var level := mode == MODE_LEVEL
	_middle.visible = level
	_palette_bar.visible = level
	_rule_editor.visible = mode == MODE_RULES
	_ai_panel.visible = mode == MODE_AI
	_logic_button.text = "← 关卡" if mode == MODE_RULES else "逻辑"
	_ai_button.text = "← 关卡" if mode == MODE_AI else "✨ AI"
	if mode == MODE_RULES:
		_rule_editor.rebuild()
	elif mode == MODE_AI:
		_ai_panel.rebuild()
	else:
		_canvas.refresh()
	_refresh()


func _set_rule_mode(on: bool) -> void:
	_set_mode(MODE_RULES if on else MODE_LEVEL)


func _set_ai_mode(on: bool) -> void:
	_set_mode(MODE_AI if on else MODE_LEVEL)


func _is_ai_mode() -> bool:
	return _mode == MODE_AI


## 快捷键处理。
##
## 已知的取舍：焦点在输入框（属性面板里的数字框）里时，Ctrl+Z 会被输入框
## 当成"文字撤销"先吃掉 —— 打了 1.1 直接按 Ctrl+Z，结果是刚打的字符被撤掉、
## 数字变成半截。先按回车或点一下别处让输入框交出焦点就正常。
##
## 曾经把 Ctrl+Z 挪到输入链第一站去解决这个问题，但改动引入了更难解释的行为
## （输入框里全选删除后再打字、撤销时保留新值并丢失选中），
## 而且在没有真实键盘的环境里无法验证。权衡之后退回原样：
## 这点小毛病有天然绕法，不值得我们拿稳定性去换。
##
## Delete 同理：在输入框里按 Delete 应该是删字符，不是删掉画布上选中的对象。
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: InputEventKey = event
	if key.ctrl_pressed and key.keycode == KEY_Z:
		if key.shift_pressed:
			_on_redo()
		else:
			_on_undo()
		accept_event()
	elif key.ctrl_pressed and key.keycode == KEY_Y:
		_on_redo()
		accept_event()
	elif key.ctrl_pressed and key.keycode == KEY_S:
		_on_save()
		accept_event()
	elif key.keycode == KEY_DELETE:
		_on_delete()
		accept_event()
	elif key.keycode == KEY_F5:
		_on_play()
		accept_event()


# --------------------------------------------------------------------------
# 素材栏里的一格
# --------------------------------------------------------------------------

class PaletteItem:
	extends Button

	var entity_id: String = ""
	## 这一下是"拖去放置"还是"点一下选中这一类"。
	## 拖动时 Godot 仍会发 pressed，所以得自己记一笔，否则每次放置
	## 都会顺手把右边的面板切到"这一类"去。
	var dragged: bool = false

	func _init(p_entity_id: String, p_name: String, p_color: Color) -> void:
		entity_id = p_entity_id
		text = "  " + p_name
		custom_minimum_size = Vector2(132, 60)
		focus_mode = Control.FOCUS_NONE
		tooltip_text = "按住拖到画布上放下"
		add_theme_stylebox_override("normal", _style(p_color, 0.10))
		add_theme_stylebox_override("hover", _style(p_color, 0.24))
		add_theme_stylebox_override("pressed", _style(p_color, 0.34))

	## 左边一条实体本色，右边淡淡的同色底——一眼能对上画布上的形状
	func _style(tint: Color, alpha: float) -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(tint.r, tint.g, tint.b, alpha)
		style.border_width_left = 6
		style.border_color = tint
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		style.content_margin_left = 8.0
		style.content_margin_right = 8.0
		return style

	func _get_drag_data(_at_position: Vector2) -> Variant:
		dragged = true
		var preview := Label.new()
		preview.text = "  " + text.strip_edges() + "  "
		preview.add_theme_color_override("font_color", Color.WHITE)
		var backdrop := StyleBoxFlat.new()
		backdrop.bg_color = Color(0.1, 0.13, 0.2, 0.9)
		backdrop.corner_radius_top_left = 6
		backdrop.corner_radius_top_right = 6
		backdrop.corner_radius_bottom_left = 6
		backdrop.corner_radius_bottom_right = 6
		preview.add_theme_stylebox_override("normal", backdrop)
		set_drag_preview(preview)
		return {"type": "entity", "entity_id": entity_id}
