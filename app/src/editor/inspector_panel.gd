## 属性面板：改选中对象的颜色、位置、大小和自定义属性。
##
## 这里的每一项都改的是「这一个对象」，不是「这一类对象」。
## 用户心里的模型是「我改的是这枚金币」，不是「我改的是金币这个类型」，
## 界面必须跟着这个直觉走。
class_name InspectorPanel
extends PanelContainer

const PANEL_WIDTH := 300.0
## 连续调节（拖滑块、连点上下箭头）合并成一步撤销，否则撤销栈会被灌满
const UNDO_COALESCE_MS := 700

var session: EditSession = null

var _content: VBoxContainer = null
var _name_label: Label = null
var _pos_x: SpinBox = null
var _pos_y: SpinBox = null
var _scale_x: SpinBox = null
var _scale_y: SpinBox = null
var _color_button: ColorPickerButton = null
var _props_box: VBoxContainer = null

var _last_selected_id: String = ""
var _last_selected_entity_id: String = ""
var _last_props_signature: String = ""
var _last_undo_ms: int = 0
var _property_row_count: int = 0


func setup(p_session: EditSession) -> void:
	session = p_session
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	add_theme_stylebox_override("panel", _panel_style())

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	add_child(_content)

	session.changed.connect(_on_session_changed)
	rebuild()


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1b2130")
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	return style


func _on_session_changed() -> void:
	# 换了选中对象就重建；只是数值变了就原地刷新，
	# 否则用户正在拖的滑块会被重建掉，手感全无。
	#
	# 另外，属性的「行」变了（增删改名、或者撤销把某个属性收回去）也必须重建，
	# 否则面板上会留着已经不存在的那一行。
	if session.selected_instance_id != _last_selected_id \
		or session.selected_entity_id != _last_selected_entity_id \
		or _props_signature(_selected()) != _last_props_signature:
		rebuild()
	else:
		refresh_values()


## 自定义属性的名字拼在一起，用来判断"行"有没有变化
static func _props_signature(placed: PlacedEntity) -> String:
	if placed == null:
		return ""
	var keys: Array[String] = []
	for key in placed.properties:
		keys.append(str(key))
	return ",".join(keys)


## 供自动化测试使用：当前显示了几行自定义属性
func property_row_count() -> int:
	return _property_row_count


func _selected() -> PlacedEntity:
	if session == null:
		return null
	return session.find_instance(session.selected_instance_id)


func _rebuild_content() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()


func rebuild() -> void:
	if _content == null:
		return
	_rebuild_content()
	_last_selected_id = session.selected_instance_id
	_last_selected_entity_id = session.selected_entity_id
	_last_props_signature = _props_signature(_selected())
	_property_row_count = 0
	_last_undo_ms = 0

	# 选中"这一类"时显示类型面板；选中"这一个"时显示实例面板。
	# 两者互斥，面板一次只讲一件事。
	var def := session.selected_entity()
	if def != null:
		_build_type_panel(def)
		return

	var placed := _selected()
	if placed == null:
		_build_empty_hint()
		return
	# 分四组，和类型面板用同一套分组标题 —— 两边风格一致，
	# 用户才不会觉得"这是两套东西"。组里的每一项都只讲"这一个"。
	_build_header(placed)
	_content.add_child(_group_label("变换"))
	_build_transform(placed)
	_content.add_child(_group_label("外观"))
	_build_color(placed)
	_content.add_child(_group_label("物理"))
	_build_motion(placed)
	_build_collision(placed)
	_build_button_binding(placed)
	_content.add_child(_group_label("数据"))
	_build_properties(placed)
	_build_delete(placed)


func refresh_values() -> void:
	var placed := _selected()
	if placed == null:
		return
	if _pos_x == null or not is_instance_valid(_pos_x):
		return
	_pos_x.set_value_no_signal(placed.x)
	_pos_y.set_value_no_signal(placed.y)
	_scale_x.set_value_no_signal(placed.scale_x)
	_scale_y.set_value_no_signal(placed.scale_y)
	if _color_button != null and is_instance_valid(_color_button):
		var wanted := session.effective_color(placed)
		# 只在真的不同才写，避免和用户正在操作的取色器打架
		if _color_button.color != wanted:
			_color_button.set_block_signals(true)
			_color_button.color = wanted
			_color_button.set_block_signals(false)


# --------------------------------------------------------------------------
# 内容
# --------------------------------------------------------------------------

func _build_empty_hint() -> void:
	var title := _title_label("属性")
	_content.add_child(title)
	var hint := Label.new()
	hint.text = "在画布上点选一个对象，\n这里就能改它的颜色、大小和数值。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	_content.add_child(hint)


func _build_header(placed: PlacedEntity) -> void:
	_content.add_child(_title_label("属性"))
	var def := session.project.find_entity(placed.entity_id)
	_name_label = Label.new()
	_name_label.text = def.name if def != null else placed.entity_id
	_name_label.add_theme_font_size_override("font_size", 18)
	_name_label.add_theme_color_override("font_color", Color("#38bdf8"))
	_content.add_child(_name_label)
	# 交叉指引：想改"这一类"的人，从这里走
	var to_type := Button.new()
	to_type.text = "改这一类（%s）" % _name_label.text
	to_type.tooltip_text = "改所有这一类对象共有的东西：名字、颜色、原始大小、碰撞……"
	to_type.focus_mode = Control.FOCUS_NONE
	to_type.pressed.connect(func() -> void: session.select_entity(placed.entity_id))
	_content.add_child(to_type)
	_content.add_child(_cross_hint("想一次改一整类（名字、颜色、原始大小、碰撞）？点上面的「改这一类」。"))


func _build_transform(placed: PlacedEntity) -> void:
	_content.add_child(HSeparator.new())
	_content.add_child(_section_label("位置"))
	var pos := GridContainer.new()
	pos.columns = 2
	pos.add_theme_constant_override("h_separation", 8)
	pos.add_theme_constant_override("v_separation", 6)
	_content.add_child(pos)
	_pos_x = _spin(-20000.0, 20000.0, 1.0, placed.x)
	_pos_y = _spin(-20000.0, 20000.0, 1.0, placed.y)
	_add_row(pos, "横坐标", _pos_x)
	_add_row(pos, "纵坐标", _pos_y)
	_pos_x.value_changed.connect(_on_position_changed)
	_pos_y.value_changed.connect(_on_position_changed)

	# 这里叫「缩放」而不是「大小」：类型面板那边叫「原始大小」。
	# 两处都能让对象变大，但含义完全不同 —— 用词必须分开，
	# 否则用户永远分不清自己改的是"它本来多大"还是"这一个被放大了多少"。
	_content.add_child(_section_label("缩放"))
	var scale_box := GridContainer.new()
	scale_box.columns = 2
	scale_box.add_theme_constant_override("h_separation", 8)
	scale_box.add_theme_constant_override("v_separation", 6)
	_content.add_child(scale_box)
	_scale_x = _spin(0.1, 8.0, 0.1, placed.scale_x)
	_scale_y = _spin(0.1, 8.0, 0.1, placed.scale_y)
	_add_row(scale_box, "横向倍数", _scale_x)
	_add_row(scale_box, "纵向倍数", _scale_y)
	_scale_x.value_changed.connect(_on_scale_changed)
	_scale_y.value_changed.connect(_on_scale_changed)


# --------------------------------------------------------------------------
# 「这一类」的面板（实体类型）
# --------------------------------------------------------------------------
#
# 用户点底部素材栏里的一项就进到这里。六项按三组排：基本 / 外观 / 物理。
#
# 两条防误操作的规矩，都是"改类型会影响一整类"逼出来的：
#   1. 顶部一条醒目的标语 + "场上几个、其中几个自己设过不受影响"
#   2. 每个容易和实例搞混的项旁边写一句交叉指引（"只想改这一个？…"）

func _build_type_panel(def: EntityDef) -> void:
	_content.add_child(_type_banner(def))

	_content.add_child(_group_label("基本"))
	_build_type_name(def)
	_build_type_tags(def)

	_content.add_child(_group_label("外观"))
	_build_type_color(def)
	_build_type_size(def)

	_content.add_child(_group_label("物理"))
	_build_type_motion(def)
	_build_type_collision(def)

	_content.add_child(HSeparator.new())
	var footer := Label.new()
	footer.text = "这里改的是「%s」这一类（场上所有这种对象）。还不能新建或删除类型；想给这一类添属性，等「属性清单」那一块（排在后面）。" % def.name
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", Color(1, 1, 1, 0.38))
	_content.add_child(footer)


## 顶部标语：一眼看出"我在改一整类"，以及会影响几个
func _type_banner(def: EntityDef) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#2a1e46")
	style.border_width_left = 6
	style.border_color = Color("#c084fc")
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)

	var title := Label.new()
	title.text = "正在编辑「%s」这一类" % def.name
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#e9d5ff"))
	box.add_child(title)

	var count := session.instance_count_of(def.id)
	var note := Label.new()
	var affected: Array[String] = []
	for field in [["color", "颜色"], ["motion", "会动吗"], ["collision", "碰撞"]]:
		var n := session.overridden_count_of(def.id, String(field[0]))
		if n > 0:
			affected.append("%d 个自己设过%s" % [n, String(field[1])])
	var tail := "，其中%s不受影响" % "、".join(affected) if not affected.is_empty() else ""
	note.text = "场上摆了 %d 个%s" % [count, tail]
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	box.add_child(note)

	var internal := Label.new()
	internal.text = "内部名：%s（规则和 JSON 里用它）" % def.id
	internal.add_theme_font_size_override("font_size", 10)
	internal.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	box.add_child(internal)
	return panel


func _build_type_name(def: EntityDef) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_content.add_child(row)
	row.add_child(_field_label("名字"))
	var edit := LineEdit.new()
	edit.text = def.name
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_submitted.connect(func(text: String) -> void:
		session.set_entity_name(def.id, text)
		rebuild())
	edit.focus_exited.connect(func() -> void:
		session.set_entity_name(def.id, edit.text)
		rebuild())
	row.add_child(edit)


## 标签：规则里那些「所有「金币」」就是按标签找对象的
func _build_type_tags(def: EntityDef) -> void:
	var note := Label.new()
	note.text = "规则里写「所有「金币」」时，找的就是这个标签"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	_content.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_content.add_child(row)
	row.add_child(_field_label("标签"))
	var edit := LineEdit.new()
	edit.text = ", ".join(Array(def.tags))
	edit.placeholder_text = "多个标签用逗号分开，例如 coin, pickup"
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var apply := func() -> void:
		session.set_entity_tags(def.id, _parse_tags(edit.text))
		rebuild()
	edit.text_submitted.connect(func(_text: String) -> void: apply.call())
	edit.focus_exited.connect(func() -> void: apply.call())
	row.add_child(edit)


static func _parse_tags(text: String) -> PackedStringArray:
	var tags := PackedStringArray()
	for part in text.split(","):
		var tag := part.strip_edges()
		if not tag.is_empty() and not tags.has(tag):
			tags.append(tag)
	return tags


func _build_type_color(def: EntityDef) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_content.add_child(row)
	row.add_child(_field_label("颜色"))
	var picker := ColorPickerButton.new()
	picker.color = Color(def.color)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.focus_mode = Control.FOCUS_NONE
	picker.color_changed.connect(func(color: Color) -> void:
		_begin_edit()
		session.set_entity_color(def.id, "#" + color.to_html(false)))
	row.add_child(picker)
	_content.add_child(_cross_hint("这里改的是这一类。只想改某一个？在画布上选中它，用上面那个面板改。"))


## 原始大小：和实例面板的「缩放」是两件事
func _build_type_size(def: EntityDef) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_content.add_child(row)
	row.add_child(_field_label("形状"))
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.focus_mode = Control.FOCUS_NONE
	var shapes: Array[String] = [EntityDef.SHAPE_RECT, EntityDef.SHAPE_CIRCLE, EntityDef.SHAPE_NONE]
	var shape_labels: Array[String] = ["方块", "圆形", "没有碰撞体"]
	for label in shape_labels:
		picker.add_item(label)
	picker.selected = maxi(shapes.find(def.collider_shape), 0)
	picker.item_selected.connect(func(picked: int) -> void:
		_begin_edit()
		session.set_entity_shape(def.id, shapes[picked])
		rebuild())
	row.add_child(picker)

	if def.collider_shape == EntityDef.SHAPE_NONE:
		return
	_content.add_child(_section_label("原始大小"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	_content.add_child(grid)
	if def.collider_shape == EntityDef.SHAPE_CIRCLE:
		var radius := _spin(1.0, 4000.0, 1.0, def.collider_radius)
		radius.value_changed.connect(func(value: float) -> void:
			_begin_edit()
			session.set_entity_size(def.id, def.collider_width, def.collider_height, value))
		_add_row(grid, "半径", radius)
	else:
		var width := _spin(1.0, 4000.0, 1.0, def.collider_width)
		var height := _spin(1.0, 4000.0, 1.0, def.collider_height)
		width.value_changed.connect(func(value: float) -> void:
			_begin_edit()
			session.set_entity_size(def.id, value, def.collider_height, def.collider_radius))
		height.value_changed.connect(func(value: float) -> void:
			_begin_edit()
			session.set_entity_size(def.id, def.collider_width, value, def.collider_radius))
		_add_row(grid, "宽", width)
		_add_row(grid, "高", height)
	_content.add_child(_cross_hint("这是它「本来多大」。某一个被放大缩小了多少倍，看上面那个面板的「缩放」。"))


func _build_type_motion(def: EntityDef) -> void:
	_build_choice_section("会动吗", PlacedEntity.MOTION_TYPE_OPTIONS,
		session.entity_motion_preset(def),
		func() -> String:
			var fresh := session.project.find_entity(def.id)
			return _motion_description(PlacedEntity.motion_of_preset(session.entity_motion_preset(fresh))),
		func(value: String) -> void:
			_begin_edit()
			session.set_entity_motion(def.id, value))


func _build_type_collision(def: EntityDef) -> void:
	_build_choice_section("碰撞", PlacedEntity.COLLISION_TYPE_OPTIONS, def.collision_group,
		func() -> String:
			var fresh := session.project.find_entity(def.id)
			return session.describe_collision_group_for_type(fresh),
		func(value: String) -> void:
			_begin_edit()
			session.set_entity_collision_group(def.id, value))


static func _motion_description(preset: Dictionary) -> String:
	var mode := String(preset.get("mode", EntityDef.PHYSICS_STATIC))
	if mode == EntityDef.PHYSICS_KINEMATIC:
		return "会动、会往下掉" if float(preset.get("gravity_scale", 0.0)) > 0.0 else "会动、不往下掉（飘着的）"
	if mode == EntityDef.PHYSICS_STATIC:
		return "静止不动（会挡住别的对象）"
	return "不参与物理（能穿过去）"


func _field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(72, 0)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	return label


## 交叉指引：在容易被当成"改这一个"的地方，告诉用户另一个方向怎么走
func _cross_hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.32))
	return label


## 「会动吗」：这一个对象是静止、会飞、还是会掉。
##
## 这一节是用户逼出来的。他给 AI 生成的小怪配了一条"设置速度"的规则，
## 小怪纹丝不动 —— 因为那只小怪的物理类型是"静止"，而静止对象
## 根本不参与物理步进，速度写进去了没人用。
## 类型上的物理属性界面上改不了（那是"不能编辑实体类型"那笔老账），
## 所以先给他一条实例级的通道：选中这一个，直接改。
func _build_motion(placed: PlacedEntity) -> void:
	var def := session.project.find_entity(placed.entity_id)
	if def == null or def.is_button():
		return
	# 没有碰撞体的对象不参与物理，摆这一节等于给个点了没用的开关
	if def.collider_shape == EntityDef.SHAPE_NONE:
		return

	_build_choice_section("会动吗", PlacedEntity.MOTION_OPTIONS, placed.motion,
		func() -> String:
			return session.describe_motion(session.find_instance(placed.instance_id)),
		func(value: String) -> void:
			_begin_edit()
			session.set_instance_motion(placed.instance_id, value))


## 「碰撞」：这一个对象会不会挡住别人、会不会接住掉落的东西。
##
## 和「会动吗」是同一个套路：这些身份本来只写在**类型**上，而界面上改不了类型，
## 于是用户想让某块平台"接得住掉下来的金币"时，只能去手改 JSON。
## 现在选中它、在这里改一下就行 —— 不用管整类的其他对象。
func _build_collision(placed: PlacedEntity) -> void:
	var def := session.project.find_entity(placed.entity_id)
	if def == null or def.is_button():
		return
	# 没有碰撞体的对象压根不参与碰撞，摆这一节等于给个点了没用的开关
	if def.collider_shape == EntityDef.SHAPE_NONE:
		return

	_build_choice_section("碰撞", PlacedEntity.COLLISION_OPTIONS, placed.collision_group,
		func() -> String:
			return session.describe_collision_group(session.find_instance(placed.instance_id)),
		func(value: String) -> void:
			_begin_edit()
			session.set_instance_collision_group(placed.instance_id, value))


## 「一节 = 标题 + 说明行 + 下拉框」的通用做法。
##
## describe 每次现算（而不是取建控件时的旧值），所以改完之后那一行说明立刻跟着变；
## 只更新那一行、不整块重建，是因为重建会把刚点过的下拉框换掉，
## 手感上像是"点完跳了一下"。
func _build_choice_section(title: String, options: Array[Dictionary], current: String,
		describe: Callable, on_pick: Callable) -> void:
	_content.add_child(_section_label(title))
	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	hint.text = String(describe.call())
	_content.add_child(hint)

	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.focus_mode = Control.FOCUS_NONE
	var values: Array[String] = []
	for option in options:
		values.append(String(option["value"]))
		picker.add_item(String(option["label"]))
	picker.selected = maxi(values.find(current), 0)
	picker.item_selected.connect(func(picked: int) -> void:
		on_pick.call(values[picked])
		hint.text = String(describe.call()))
	_content.add_child(picker)


## 屏幕按键多一项：绑定到哪个输入动作。
##
## 按键要是不可编辑，这个工具就只能做我们预设的那几种玩法。
## 用户该能自己决定"这个键等于按什么"。
##
## 选项文字念人话（"往左走"），不念 InputMap 里的 id（"ui_left"）——
## 做原型的人不该为了做一个左移键去查引擎的动作表。
## 选项本身还是数据，写在词汇表里，运行器画按键时读的是同一份。
func _build_button_binding(placed: PlacedEntity) -> void:
	var def := session.project.find_entity(placed.entity_id)
	if def == null or not def.is_button():
		return

	_content.add_child(_section_label("按键绑定"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_content.add_child(row)

	var current := session.effective_button_action(placed)
	var values := RuleVocabulary.button_action_ids()
	var current_index := values.find(current)
	if current_index < 0:
		# 绑定了一个不在常用列表里的动作，补一项显示出来，
		# 免得用户原来选的东西凭空消失、被悄悄改成别的。
		values.append(current)
		current_index = values.size() - 1

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	hint.text = _button_binding_hint(values[current_index])
	_content.add_child(hint)

	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.focus_mode = Control.FOCUS_NONE
	for i in values.size():
		picker.add_item(RuleVocabulary.button_action_menu(values[i]))
		picker.set_item_tooltip(i, _button_binding_hint(values[i]))
	picker.selected = current_index
	picker.item_selected.connect(func(picked: int) -> void:
		_begin_edit()
		session.set_instance_button_action(placed.instance_id, values[picked])
		# 只更新说明那一行。整块重建会把刚点过的下拉框一起换掉，
		# 手感上像是点完就跳了一下。
		hint.text = _button_binding_hint(values[picked]))
	row.add_child(picker)

	var follow := Button.new()
	follow.text = "跟随类型"
	follow.tooltip_text = "取消单独设置，恢复成所属实体绑定的动作"
	follow.focus_mode = Control.FOCUS_NONE
	follow.pressed.connect(func() -> void:
		_begin_edit()
		session.set_instance_button_action(placed.instance_id, "")
		rebuild())
	row.add_child(follow)


## 这个动作是干什么的。表里没有的动作（手改过 JSON）就说清这一点，
## 比留一片空白好 —— 用户至少知道"它不是我选的，是被别人写进去的"。
func _button_binding_hint(action: String) -> String:
	var text := RuleVocabulary.button_action_hint(action)
	if not text.is_empty():
		return text
	if action.is_empty():
		return "还没有绑定任何动作，这个键按下去不会有反应"
	return "「%s」不在常用列表里（多半是手改过 JSON），按键上会直接显示这串 id" % action


func _build_color(placed: PlacedEntity) -> void:
	_content.add_child(_section_label("颜色"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_content.add_child(row)

	_color_button = ColorPickerButton.new()
	_color_button.color = session.effective_color(placed)
	_color_button.custom_minimum_size = Vector2(0, 34)
	_color_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_color_button.focus_mode = Control.FOCUS_NONE
	_color_button.color_changed.connect(_on_color_changed)
	row.add_child(_color_button)

	var follow := Button.new()
	follow.text = "跟随类型"
	follow.tooltip_text = "取消单独设置的颜色，恢复成所属类型的颜色"
	follow.focus_mode = Control.FOCUS_NONE
	follow.pressed.connect(_on_color_follow_type)
	row.add_child(follow)


func _build_properties(placed: PlacedEntity) -> void:
	_content.add_child(HSeparator.new())
	_content.add_child(_section_label("自定义属性"))

	_props_box = VBoxContainer.new()
	_props_box.add_theme_constant_override("separation", 4)
	_content.add_child(_props_box)

	if placed.properties.is_empty():
		var hint := Label.new()
		hint.text = "（还没有）例如 score、hp"
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
		_props_box.add_child(hint)
	else:
		for key in placed.properties:
			_props_box.add_child(_property_row(placed, key, placed.properties[key]))
		_property_row_count = placed.properties.size()

	var add := Button.new()
	add.text = "＋ 添加属性"
	add.focus_mode = Control.FOCUS_NONE
	add.pressed.connect(_on_add_property)
	_content.add_child(add)


func _property_row(placed: PlacedEntity, key: String, value: Variant) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var name_edit := LineEdit.new()
	name_edit.text = key
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.custom_minimum_size = Vector2(90, 0)
	name_edit.text_submitted.connect(func(new_name: String) -> void:
		if session.rename_instance_property(placed.instance_id, key, new_name):
			rebuild())
	name_edit.focus_exited.connect(func() -> void:
		if session.rename_instance_property(placed.instance_id, key, name_edit.text):
			rebuild())
	row.add_child(name_edit)

	if _is_number(value):
		var spin := _spin(-999999.0, 999999.0, 1.0, float(value))
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.custom_minimum_size = Vector2(80, 0)
		spin.value_changed.connect(func(new_value: float) -> void:
			_begin_edit()
			session.set_instance_property(placed.instance_id, key, new_value))
		row.add_child(spin)
	else:
		# 这个版本的自定义属性只支持数值（规则系统用的也是数值）。
		# 遇到别的类型就说明白，别悄悄显示成 0 —— 那等于骗人。
		var note := Label.new()
		note.text = "（非数值，此版本不可编辑）"
		note.add_theme_font_size_override("font_size", 11)
		note.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
		row.add_child(note)

	var remove := Button.new()
	remove.text = "×"
	remove.tooltip_text = "删除这个属性"
	remove.focus_mode = Control.FOCUS_NONE
	remove.pressed.connect(func() -> void:
		session.push_undo("删除属性")
		session.remove_instance_property(placed.instance_id, key)
		rebuild())
	row.add_child(remove)
	return row


func _build_delete(placed: PlacedEntity) -> void:
	_content.add_child(HSeparator.new())
	var duplicate := Button.new()
	duplicate.text = "复制一份"
	duplicate.tooltip_text = "原地复制一个，用来再做一个按键或同类对象"
	duplicate.focus_mode = Control.FOCUS_NONE
	duplicate.pressed.connect(func() -> void:
		# 往右下方错开一点，免得和原对象完全重叠、看不出来复制成功了
		if session.duplicate_instance(placed.instance_id, Vector2(60, 60)) != null:
			rebuild())
	_content.add_child(duplicate)

	var remove := Button.new()
	remove.text = "删除这个对象"
	remove.focus_mode = Control.FOCUS_NONE
	remove.pressed.connect(func() -> void:
		session.push_undo("删除对象")
		if session.remove_instance(placed.instance_id):
			rebuild())
	_content.add_child(remove)


# --------------------------------------------------------------------------
# 小工具
# --------------------------------------------------------------------------

func _title_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	return label


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	return label


## 分组标题（基本 / 外观 / 物理 / 数据…）。
## 类型面板和实例面板共用同一套，风格才不会各长各的。
func _group_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("#7dd3fc"))
	return label


func _spin(min_value: float, max_value: float, step: float, value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.focus_mode = Control.FOCUS_NONE
	return spin


func _add_row(grid: GridContainer, label_text: String, field: Control) -> void:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	grid.add_child(label)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(field)


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


## 连续调节合并成一步撤销
func _begin_edit() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_undo_ms > UNDO_COALESCE_MS:
		session.push_undo("修改属性")
	_last_undo_ms = now


# --------------------------------------------------------------------------
# 操作
# --------------------------------------------------------------------------

func _on_position_changed(_value: float) -> void:
	var placed := _selected()
	if placed == null or _pos_x == null:
		return
	_begin_edit()
	session.move_instance(placed.instance_id, Vector2(_pos_x.value, _pos_y.value))


func _on_scale_changed(_value: float) -> void:
	var placed := _selected()
	if placed == null or _scale_x == null:
		return
	_begin_edit()
	session.set_instance_scale(placed.instance_id, _scale_x.value, _scale_y.value)


func _on_color_changed(color: Color) -> void:
	var placed := _selected()
	if placed == null:
		return
	_begin_edit()
	# 存成 #rrggbb：工程文件是给人看的，带井号更顺眼
	session.set_instance_color(placed.instance_id, "#" + color.to_html(false))


func _on_color_follow_type() -> void:
	var placed := _selected()
	if placed == null:
		return
	_begin_edit()
	session.set_instance_color(placed.instance_id, "")
	rebuild()


func _on_add_property() -> void:
	var placed := _selected()
	if placed == null:
		return
	session.push_undo("新增属性")
	session.set_instance_property(placed.instance_id, _unique_key(placed, "新属性"), 0)
	rebuild()


func _unique_key(placed: PlacedEntity, base: String) -> String:
	var key := base
	var n := 2
	while placed.properties.has(key):
		key = "%s%d" % [base, n]
		n += 1
	return key
