## 编辑会话：编辑器背后的那份"文档"。
##
## 刻意不碰任何界面。它只管一件事——维护一份 GameProject，
## 并记录用户对它做了哪些修改。这样编辑逻辑可以脱离界面单独测试，
## 界面怎么改都不会影响数据正确性。
class_name EditSession
extends RefCounted

signal changed
signal scene_switched(index: int)

## 撤销栈上限。快照式撤销，简单可靠；原型工程很小，内存不是问题。
const MAX_UNDO := 50
const DEFAULT_HALF_EXTENT := 24.0

var project: GameProject = null
var path: String = ""
var dirty: bool = false
var selected_instance_id: String = ""
## 选中的"这一类"（实体定义）。和 selected_instance_id 互斥：
## 面板一次只显示一个东西 —— 要么是这一类，要么是这一个。
##
## 为什么要有这一层：颜色、碰撞、会动吗这些**写在类型上**，
## 而界面上一直改不了类型，用户只能去手改 JSON。现在点素材栏里的一项
## 就能选中"这一类"来改。
var selected_entity_id: String = ""
var last_error: String = ""

var _scene_index: int = 0
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []


# --------------------------------------------------------------------------
# 打开与保存
# --------------------------------------------------------------------------

func open(file_path: String) -> bool:
	var result := ProjectIO.load_from_file(file_path)
	if not result.ok:
		last_error = result.error
		return false
	return _adopt(result.project, file_path)


func create_new(project_name: String) -> bool:
	var p := ProjectIO.create_empty(project_name)
	return _adopt(p, "")


func _adopt(p: GameProject, file_path: String) -> bool:
	# 校验不通过的工程直接拒绝打开。放进来之后再让编辑器改坏，
	# 用户会很难分清"本来就有问题"还是"我改坏的"。
	var issues := ProjectValidator.validate(p)
	if ProjectValidator.has_errors(issues):
		last_error = ProjectValidator.format_all(issues)
		return false

	project = p
	path = file_path
	dirty = false
	selected_instance_id = ""
	_scene_index = 0
	_undo.clear()
	_redo.clear()
	last_error = ""
	changed.emit()
	scene_switched.emit(_scene_index)
	return true


## 直接写入指定位置。
## 注意：这是底层操作，不挡内置示例。编辑器界面请用 save_project()，
## 那里带了「不覆盖内置示例」的保护。
func save(file_path: String = "") -> bool:
	if project == null:
		last_error = "还没有打开任何工程"
		return false
	var target := file_path if not file_path.is_empty() else path
	if target.is_empty():
		last_error = "还没有指定保存位置"
		return false
	var error := ProjectIO.save_to_file(project, target)
	if not error.is_empty():
		last_error = error
		return false
	path = target
	dirty = false
	last_error = ""
	changed.emit()
	return true


## 这份工程是不是应用自带的内置示例？
##
## 示例同时是自动化测试的基准，用户随手按一次保存就会把它改掉，
## 所以示例一律按只读处理，保存时自动另存到别处。
func is_bundled_sample() -> bool:
	if path.is_empty():
		return false
	var normalized := path.replace("\\", "/")
	if normalized.begins_with("res://samples/"):
		return true
	var samples_dir := ProjectSettings.globalize_path("res://samples/").replace("\\", "/")
	return normalized.begins_with(samples_dir)


## 保存工程。如果打开的是内置示例，就写到 fallback_path 去，不覆盖示例本身。
## 返回实际写入的路径；失败时返回空字符串，原因在 last_error。
func save_project(fallback_path: String) -> String:
	var target := ""
	if is_bundled_sample():
		target = fallback_path
		if target.is_empty():
			last_error = "内置示例不可覆盖，但没有指定另存位置"
			return ""
	if not save(target):
		return ""
	return path


func to_json() -> String:
	return ProjectIO.to_json_string(project, true) if project != null else ""


# --------------------------------------------------------------------------
# 场景
# --------------------------------------------------------------------------

func scenes() -> Array[SceneDef]:
	return project.scenes if project != null else []


func current_scene() -> SceneDef:
	if project == null or project.scenes.is_empty():
		return null
	return project.scenes[clampi(_scene_index, 0, project.scenes.size() - 1)]


func current_scene_index() -> int:
	return _scene_index


# --------------------------------------------------------------------------
# 选中的是"这一类"还是"这一个"
# --------------------------------------------------------------------------

## 选中一类对象（点素材栏里的一项）。会清掉实例的选中 —— 面板一次只显示一个。
func select_entity(entity_id: String) -> void:
	if project == null or project.find_entity(entity_id) == null:
		return
	selected_instance_id = ""
	selected_entity_id = entity_id
	changed.emit()


func selected_entity() -> EntityDef:
	if project == null or selected_entity_id.is_empty():
		return null
	return project.find_entity(selected_entity_id)


## 选中一个实例（画布上点了一下）。同样清掉"这一类"的选中。
##
## 这里也要发 changed：界面（属性面板、状态栏）靠它刷新。
## 一开始只有画布在调用它、由画布自己发信号，所以漏了这一步；
## 结果"从别处选中一个实例"时面板不换 —— 这类不对称最容易埋坑。
func select_instance(instance_id: String) -> void:
	selected_entity_id = ""
	selected_instance_id = instance_id
	changed.emit()


## 场上这一类摆了几个 —— 类型面板用来说清"改动会影响谁"
func instance_count_of(entity_id: String) -> int:
	var count := 0
	for scene in scenes():
		for placed in scene.instances:
			if placed.entity_id == entity_id:
				count += 1
	return count


## 这一类里，有多少个自己单独设过某项（颜色 / 会动吗 / 碰撞）。
## 改类型时这些实例不受影响，得先告诉用户，免得他改完发现"有几个没变"。
func overridden_count_of(entity_id: String, field: String) -> int:
	var count := 0
	for scene in scenes():
		for placed in scene.instances:
			if placed.entity_id != entity_id:
				continue
			match field:
				"color":
					if not placed.color.is_empty():
						count += 1
				"motion":
					if not placed.motion.is_empty():
						count += 1
				"collision":
					if not placed.collision_group.is_empty():
						count += 1
	return count


func select_scene(index: int) -> void:
	if project == null or index < 0 or index >= project.scenes.size():
		return
	if index == _scene_index:
		return
	_scene_index = index
	selected_instance_id = ""
	changed.emit()
	scene_switched.emit(_scene_index)


func add_scene(scene_name: String) -> SceneDef:
	if project == null:
		return null
	_push_undo("新增关卡")
	var scene := SceneDef.new()
	scene.id = ProjectIO.new_id("scn")
	scene.name = scene_name
	project.scenes.append(scene)
	_mark_dirty()
	select_scene(project.scenes.size() - 1)
	return scene


# --------------------------------------------------------------------------
# 实例
# --------------------------------------------------------------------------

func add_instance(entity_id: String, world_pos: Vector2) -> PlacedEntity:
	var scene := current_scene()
	if scene == null or project.find_entity(entity_id) == null:
		return null
	_push_undo("放置对象")
	var placed := PlacedEntity.new()
	placed.instance_id = ProjectIO.new_id("i")
	placed.entity_id = entity_id
	placed.x = world_pos.x
	placed.y = world_pos.y
	scene.instances.append(placed)
	selected_instance_id = placed.instance_id
	_mark_dirty()
	return placed


func remove_instance(instance_id: String) -> bool:
	var scene := current_scene()
	if scene == null:
		return false
	for i in scene.instances.size():
		if scene.instances[i].instance_id == instance_id:
			_push_undo("删除对象")
			scene.instances.remove_at(i)
			if selected_instance_id == instance_id:
				selected_instance_id = ""
			_mark_dirty()
			return true
	return false


func duplicate_instance(instance_id: String, offset: Vector2) -> PlacedEntity:
	var scene := current_scene()
	if scene == null:
		return null
	var source := find_instance(instance_id)
	if source == null:
		return null
	_push_undo("复制对象")
	var copy := PlacedEntity.from_dict(source.to_dict())
	copy.instance_id = ProjectIO.new_id("i")
	copy.x += offset.x
	copy.y += offset.y
	scene.instances.append(copy)
	selected_instance_id = copy.instance_id
	_mark_dirty()
	return copy


func find_instance(instance_id: String) -> PlacedEntity:
	var scene := current_scene()
	if scene == null:
		return null
	for placed in scene.instances:
		if placed.instance_id == instance_id:
			return placed
	return null


func move_instance(instance_id: String, world_pos: Vector2) -> void:
	var placed := find_instance(instance_id)
	if placed == null:
		return
	placed.x = world_pos.x
	placed.y = world_pos.y
	_mark_dirty()


func set_instance_scale(instance_id: String, scale_x: float, scale_y: float) -> void:
	var placed := find_instance(instance_id)
	if placed == null:
		return
	placed.scale_x = scale_x
	placed.scale_y = scale_y
	_mark_dirty()


## 传空字符串表示恢复成"跟随实体定义的颜色"
func set_instance_color(instance_id: String, color: String) -> void:
	var placed := find_instance(instance_id)
	if placed == null:
		return
	placed.color = color
	_mark_dirty()


## 改这一个按键绑定的输入动作。传空字符串表示跟随实体定义。
func set_instance_button_action(instance_id: String, action: String) -> void:
	var placed := find_instance(instance_id)
	if placed == null:
		return
	placed.button_action = action
	_mark_dirty()


## 这个按键实际绑定的是哪个动作：自己设了就用自己的，否则跟随实体定义。
func effective_button_action(placed: PlacedEntity) -> String:
	if placed == null or project == null:
		return ""
	if not placed.button_action.is_empty():
		return placed.button_action
	var def := project.find_entity(placed.entity_id)
	return def.button_action if def != null else ""


## 改这一个对象"会不会动、会不会掉"。传空字符串表示跟随类型。
##
## 用户的原话："我用规则给 AI 生成的小怪设了速度，它纹丝不动。"
## 根因是那只小怪的物理类型是"静止"，而静止对象不参与物理步进 ——
## 这条通道就是让他能自己把它改成"会动"。
func set_instance_motion(instance_id: String, motion: String) -> void:
	var placed := find_instance(instance_id)
	if placed == null:
		return
	placed.motion = motion
	_mark_dirty()


## 这个对象现在实际是什么状态，一句话给用户看。
## 把"跟随类型"之后落到哪一档也写出来，否则用户不知道自己在跟随什么。
func describe_motion(placed: PlacedEntity) -> String:
	if placed == null or project == null:
		return ""
	var def := project.find_entity(placed.entity_id)
	var resolved := PlacedEntity.resolve_motion(def, placed)
	var actual := _motion_word(String(resolved["mode"]), float(resolved["gravity_scale"]))
	if placed.motion.is_empty():
		return "跟随类型：%s" % actual
	return "已单独设置：%s" % actual


static func _motion_word(mode: String, gravity_scale: float) -> String:
	if mode == EntityDef.PHYSICS_KINEMATIC:
		if gravity_scale > 0.0:
			return "会动、会往下掉"
		return "会动、不往下掉（飘着的）"
	if mode == EntityDef.PHYSICS_STATIC:
		return "静止不动（会挡住别的对象）"
	if mode == EntityDef.PHYSICS_NONE:
		return "不参与物理（能穿过去）"
	return "静止不动"


## 改这一个对象的碰撞身份（地面 / 普通障碍 / 拾取物）。传空串表示跟随类型。
func set_instance_collision_group(instance_id: String, group: String) -> void:
	var placed := find_instance(instance_id)
	if placed == null:
		return
	placed.collision_group = group
	_mark_dirty()


## 这个对象现在实际属于哪一组，一句话给用户看。
func describe_collision_group(placed: PlacedEntity) -> String:
	if placed == null or project == null:
		return ""
	var def := project.find_entity(placed.entity_id)
	var actual := _collision_word(PlacedEntity.resolve_collision_group(def, placed))
	if placed.collision_group.is_empty():
		return "跟随类型：%s" % actual
	return "已单独设置：%s" % actual


static func _collision_word(group: String) -> String:
	if group == EntityDef.COLLISION_GROUND:
		return "地面（接得住掉落的东西）"
	if group == EntityDef.COLLISION_PICKUP:
		return "拾取物（不挡人，只落在地面上）"
	return "普通障碍（挡得住人，掉落物会穿过去）"


## 类型自己的碰撞身份（没有"跟随类型"这一说）—— 类型面板用
func describe_collision_group_for_type(def: EntityDef) -> String:
	if def == null:
		return ""
	return _collision_word(def.collision_group)


func set_instance_property(instance_id: String, key: String, value: Variant) -> void:
	var placed := find_instance(instance_id)
	if placed == null or key.is_empty():
		return
	placed.properties[key] = value
	_mark_dirty()


func remove_instance_property(instance_id: String, key: String) -> void:
	var placed := find_instance(instance_id)
	if placed == null or not placed.properties.has(key):
		return
	placed.properties.erase(key)
	_mark_dirty()


## 改名。目标名字已存在时拒绝，免得把两个属性悄悄合并成一个。
func rename_instance_property(instance_id: String, old_key: String, new_key: String) -> bool:
	var placed := find_instance(instance_id)
	if placed == null or not placed.properties.has(old_key):
		return false
	if new_key.is_empty() or new_key == old_key or placed.properties.has(new_key):
		return false
	var value: Variant = placed.properties[old_key]
	var rebuilt := {}
	for key in placed.properties:
		if key == old_key:
			rebuilt[new_key] = value
		else:
			rebuilt[key] = placed.properties[key]
	placed.properties = rebuilt
	_mark_dirty()
	return true


## 这个对象实际显示成什么颜色：自己设了就用自己的，否则跟随实体定义。
func effective_color(placed: PlacedEntity) -> Color:
	if placed == null or project == null:
		return Color.WHITE
	if not placed.color.is_empty():
		return Color(placed.color)
	var def := project.find_entity(placed.entity_id)
	return Color(def.color) if def != null else Color.WHITE


# --------------------------------------------------------------------------
# 规则
# --------------------------------------------------------------------------

## 新建规则默认用什么事件。点击屏幕最直观，也最容易验证。
const DEFAULT_TRIGGER := "tap"


func add_rule() -> RuleDef:
	if project == null:
		return null
	_push_undo("新增规则")
	var rule := RuleDef.new()
	rule.id = ProjectIO.new_id("rule")
	rule.name = _unique_rule_name()
	rule.trigger = build_statement(RuleVocabulary.trigger_def(DEFAULT_TRIGGER), DEFAULT_TRIGGER)
	rule.actions = []
	project.rules.append(rule)
	_mark_dirty()
	return rule


func _unique_rule_name() -> String:
	var base := "新规则"
	var name := base
	var n := 2
	while _has_rule_named(name):
		name = "%s %d" % [base, n]
		n += 1
	return name


func _has_rule_named(rule_name: String) -> bool:
	for rule in project.rules:
		if rule.name == rule_name:
			return true
	return false


func find_rule(rule_id: String) -> RuleDef:
	if project == null:
		return null
	for rule in project.rules:
		if rule.id == rule_id:
			return rule
	return null


## 改"这一类"的属性：名字、颜色、形状与原始尺寸、碰撞身份、会不会动、标签。
##
## 这些都在**类型**上（`EntityDef`），所以一改就是场上所有同类对象一起变，
## 除非某个实例自己设过颜色 / 会动吗 / 碰撞（那几项有实例级覆盖）。
## 每一处改动都单独记一步撤销 —— 用户试坏了按 Ctrl+Z 就能回去。
func set_entity_name(entity_id: String, new_name: String) -> void:
	var def := project.find_entity(entity_id) if project != null else null
	if def == null or new_name.strip_edges().is_empty() or def.name == new_name:
		return
	_push_undo("改类型名字")
	def.name = new_name
	_mark_dirty()


func set_entity_color(entity_id: String, color: String) -> void:
	var def := project.find_entity(entity_id) if project != null else null
	if def == null or def.color == color:
		return
	_push_undo("改类型颜色")
	def.color = color
	_mark_dirty()


func set_entity_shape(entity_id: String, shape: String) -> void:
	var def := project.find_entity(entity_id) if project != null else null
	if def == null or def.collider_shape == shape:
		return
	_push_undo("改类型形状")
	def.collider_shape = shape
	_mark_dirty()


## 这类对象的"原始大小"。和实例上的"缩放"是两件事：
## 这里改的是它本来多大，那边改的是这一个被放大缩小了多少倍。
func set_entity_size(entity_id: String, width: float, height: float, radius: float) -> void:
	var def := project.find_entity(entity_id) if project != null else null
	if def == null:
		return
	if is_equal_approx(def.collider_width, width) and is_equal_approx(def.collider_height, height) \
		and is_equal_approx(def.collider_radius, radius):
		return
	_push_undo("改类型大小")
	def.collider_width = maxf(width, 1.0)
	def.collider_height = maxf(height, 1.0)
	def.collider_radius = maxf(radius, 1.0)
	_mark_dirty()


func set_entity_collision_group(entity_id: String, group: String) -> void:
	var def := project.find_entity(entity_id) if project != null else null
	if def == null or def.collision_group == group:
		return
	_push_undo("改类型碰撞")
	def.collision_group = group
	_mark_dirty()


## 用"会不会动、会不会掉"的说法改类型的物理属性。
## 类型这边多一档「不参与物理」—— 金币那种能穿过去的东西就是这一档。
func set_entity_motion(entity_id: String, preset: String) -> void:
	var def := project.find_entity(entity_id) if project != null else null
	if def == null:
		return
	var wanted := PlacedEntity.motion_of_preset(preset)
	if def.physics_mode == String(wanted["mode"]) \
		and is_equal_approx(def.gravity_scale, float(wanted["gravity_scale"])):
		return
	_push_undo("改类型会动吗")
	def.physics_mode = String(wanted["mode"])
	def.gravity_scale = float(wanted["gravity_scale"])
	_mark_dirty()


func entity_motion_preset(def: EntityDef) -> String:
	if def == null:
		return PlacedEntity.MOTION_NONE
	return PlacedEntity.motion_preset_of(def.physics_mode, def.gravity_scale)


## 标签：规则里那些「所有「金币」」就是按标签找对象的，所以这是"这一类属于哪一族"
func set_entity_tags(entity_id: String, tags: PackedStringArray) -> void:
	var def := project.find_entity(entity_id) if project != null else null
	if def == null or def.tags == tags:
		return
	_push_undo("改类型标签")
	def.tags = tags
	_mark_dirty()


# --------------------------------------------------------------------------
# AI 草稿
# --------------------------------------------------------------------------

## 把 AI 的草稿写进工程。成功返回空字符串，失败返回原因。
##
## 顺序很重要，两步走：
##
## 1. **先在一份副本上试装，并且跑校验。** 不合法的草稿根本碰不到真工程 ——
##    AI 生成的东西和手写的走同一套校验，这是"敢让它动手"的前提。
## 2. 过了校验才真写，而且只占**一步撤销**。用户按 Ctrl+Z 就能整份撤掉，
##    不需要记住 AI 到底动了几处。
func apply_ai_draft(draft: AIDraft) -> String:
	if project == null:
		return "还没有打开工程"
	if draft == null:
		return "这份草稿是空的"
	if not draft.ok():
		return draft.error if not draft.error.is_empty() else "这份草稿是空的"

	var candidate := GameProject.from_dict(project.to_dict())
	_attach_draft(candidate, draft)
	var issues := ProjectValidator.validate(candidate)
	if ProjectValidator.has_errors(issues):
		return "这份草稿没通过校验，没有写进工程：\n%s" % ProjectValidator.format_all(issues)

	_push_undo("AI 生成：%s" % draft.title)
	var placed := _attach_draft(project, draft)
	# 生成完自动选中新摆出来的那个对象：不然用户得自己在画布上找它在哪
	if not placed.is_empty():
		selected_instance_id = placed
	_mark_dirty()
	return ""


## 把草稿里的实体 / 规则 / 摆放动作装进一份工程。返回最后摆出来的实例 id。
##
## 单独抽出来，是因为它要在两份工程上各跑一遍：
## 先装进副本试校验，通过了再装进真工程。
func _attach_draft(target: GameProject, draft: AIDraft) -> String:
	for item in draft.entities:
		target.entities.append(EntityDef.from_dict(item))
	for item in draft.rules:
		target.rules.append(RuleDef.from_dict(item))

	var scene: SceneDef = null
	if not target.scenes.is_empty():
		scene = target.scenes[clampi(_scene_index, 0, target.scenes.size() - 1)]

	var last := ""
	for item in draft.placements:
		if scene == null or target.find_entity(String(item.get("entity_id", ""))) == null:
			continue
		var placed := PlacedEntity.from_dict({
			"instance_id": ProjectIO.new_id("i"),
			"entity_id": String(item.get("entity_id", "")),
			"x": float(item.get("x", 0.0)),
			"y": float(item.get("y", 0.0)),
		})
		scene.instances.append(placed)
		last = placed.instance_id
	return last


func remove_rule(rule_id: String) -> bool:
	if project == null:
		return false
	for i in project.rules.size():
		if project.rules[i].id == rule_id:
			_push_undo("删除规则")
			project.rules.remove_at(i)
			_mark_dirty()
			return true
	return false


func set_rule_name(rule_id: String, rule_name: String) -> void:
	var rule := find_rule(rule_id)
	if rule == null or rule.name == rule_name:
		return
	rule.name = rule_name
	_mark_dirty()


func set_rule_enabled(rule_id: String, enabled: bool) -> void:
	var rule := find_rule(rule_id)
	if rule == null or rule.enabled == enabled:
		return
	rule.enabled = enabled
	_mark_dirty()


## 按词汇表生成一条语句：类型 + 该类型的全部默认参数。
##
## 用默认值预填有两个好处：存出来的 JSON 是完整可读的（不用去猜缺的参数是什么意思），
## 界面上的表单也一打开就有东西可显示。
static func build_statement(def: Dictionary, type: String) -> Dictionary:
	var statement := {"type": type}
	for key in RuleVocabulary.default_params(def):
		statement[key] = RuleVocabulary.default_params(def)[key]
	return statement


## 换事件类型时把旧参数整个丢掉。
## 不同事件的参数完全不一样，留着旧参数只会变成看不见的垃圾。
func set_rule_trigger_type(rule_id: String, type: String) -> void:
	var rule := find_rule(rule_id)
	if rule == null or not RuleVocabulary.TRIGGERS.has(type):
		return
	if String(rule.trigger.get("type", "")) == type:
		return
	rule.trigger = build_statement(RuleVocabulary.trigger_def(type), type)
	_mark_dirty()


func set_rule_trigger_param(rule_id: String, key: String, value: Variant) -> void:
	var rule := find_rule(rule_id)
	if rule == null:
		return
	rule.trigger[key] = value
	_mark_dirty()


func add_rule_condition(rule_id: String, type: String) -> int:
	var rule := find_rule(rule_id)
	if rule == null or not RuleVocabulary.CONDITIONS.has(type):
		return -1
	_push_undo("新增条件")
	rule.conditions.append(build_statement(RuleVocabulary.condition_def(type), type))
	_mark_dirty()
	return rule.conditions.size() - 1


func remove_rule_condition(rule_id: String, index: int) -> bool:
	var rule := find_rule(rule_id)
	if rule == null or index < 0 or index >= rule.conditions.size():
		return false
	_push_undo("删除条件")
	rule.conditions.remove_at(index)
	_mark_dirty()
	return true


func set_rule_condition_param(rule_id: String, index: int, key: String, value: Variant) -> void:
	var rule := find_rule(rule_id)
	if rule == null or index < 0 or index >= rule.conditions.size():
		return
	rule.conditions[index][key] = value
	_mark_dirty()


func add_rule_action(rule_id: String, type: String) -> int:
	var rule := find_rule(rule_id)
	if rule == null or not RuleVocabulary.ACTIONS.has(type):
		return -1
	_push_undo("新增动作")
	rule.actions.append(build_statement(RuleVocabulary.action_def(type), type))
	_mark_dirty()
	return rule.actions.size() - 1


func remove_rule_action(rule_id: String, index: int) -> bool:
	var rule := find_rule(rule_id)
	if rule == null or index < 0 or index >= rule.actions.size():
		return false
	_push_undo("删除动作")
	rule.actions.remove_at(index)
	_mark_dirty()
	return true


func set_rule_action_param(rule_id: String, index: int, key: String, value: Variant) -> void:
	var rule := find_rule(rule_id)
	if rule == null or index < 0 or index >= rule.actions.size():
		return
	rule.actions[index][key] = value
	_mark_dirty()


# --------------------------------------------------------------------------
# 对象选择器的候选项
# --------------------------------------------------------------------------

## 工程里出现过的所有标签，按实体定义收集
func known_tags() -> PackedStringArray:
	var tags := PackedStringArray()
	if project == null:
		return tags
	for def in project.entities:
		for tag in def.tags:
			if not tags.has(tag):
				tags.append(tag)
	return tags


## 供界面上的对象选择器使用。返回一串 {value, label}；
## 需要分组时插一条 {separator: "标题"}。
##
## place 说明这个选择器长在哪儿：trigger（事件自己的参数）/ condition / action。
## trigger_type 是这条规则的事件类型 —— 「自身」「对方」能不能用，完全取决于它。
##
## 只列用得上的选项。以前的列表里，「自身」永远在、「对方」永远在，
## 而同类对象每个实例都叫「金币（这一份）」—— 五枚金币就是五条一模一样的
## 选项，用户既挑不出来，也不知道「自身」究竟指谁。更糟的是：
## 在没有触发对象的事件里选「自身」，规则会永远不生效，而界面一声不吭。
func selector_options(place: String = "condition", trigger_type: String = "") -> Array[Dictionary]:
	var options: Array[Dictionary] = []

	# 事件自己的参数是拿来"匹配"的，那会儿还没有自身/对方可言
	if place != "trigger":
		if RuleVocabulary.trigger_provides_actor(trigger_type):
			options.append({
				"value": RuleVocabulary.SELECTOR_SELF,
				"label": "自身（触发这条规则的那个对象）",
			})
		else:
			# 说清楚为什么没有这一项，否则用户会以为工具丢了东西
			options.append({"separator": "这个事件没有触发对象，所以没有「自身」"})
		if RuleVocabulary.trigger_provides_other(trigger_type):
			options.append({
				"value": RuleVocabulary.SELECTOR_OTHER,
				"label": "对方（碰撞的另一方）",
			})

	options.append({"separator": "所有这一类（多数规则用这个）"})
	for tag in known_tags():
		options.append({
			"value": RuleVocabulary.SELECTOR_TAG_PREFIX + tag,
			"label": "所有「%s」" % RuleVocabulary.tag_display_name(tag, project),
		})

	var scene := current_scene()
	if scene == null:
		return options

	# 同类实例多于一个时才编号。给"位置"是为了让人对得上画布上那一枚 ——
	# 那是他刚摆的，位置比名字好认。
	var totals := {}
	for placed in scene.instances:
		totals[placed.entity_id] = int(totals.get(placed.entity_id, 0)) + 1
	var seen := {}
	var instances: Array[Dictionary] = []
	for placed in scene.instances:
		var def := project.find_entity(placed.entity_id)
		var name := def.name if def != null else placed.entity_id
		seen[placed.entity_id] = int(seen.get(placed.entity_id, 0)) + 1
		if int(totals.get(placed.entity_id, 1)) > 1:
			name = "%s #%d" % [name, int(seen[placed.entity_id])]
		instances.append({
			"value": RuleVocabulary.SELECTOR_INSTANCE_PREFIX + placed.instance_id,
			"label": "%s · %d, %d" % [name, int(placed.x), int(placed.y)],
			"tooltip": "就这一个对象，它的位置是 %d, %d" % [int(placed.x), int(placed.y)],
		})
	if not instances.is_empty():
		options.append({"separator": "就这一个对象"})
		options.append_array(instances)
	return options


## 这个点上压着的所有实例，**最上层在前**。
##
## 列表末尾是最后放的（画在上层），所以从后往前找。
## margin 是额外放宽的世界单位距离。手指比鼠标粗得多，
## 触屏上必须放宽一点，否则一个半径 22 的对象在平板上只有 8 毫米，点不准。
##
## 返回全部而不是一个，是为了让界面能"往下钻"：
## 两个对象叠在一起时，只返回最上面那个的话，底下那个就永远选不到了。
func instances_at(world_pos: Vector2, margin: float = 0.0) -> Array[String]:
	var hits: Array[String] = []
	var scene := current_scene()
	if scene == null:
		return hits
	for i in range(scene.instances.size() - 1, -1, -1):
		var placed := scene.instances[i]
		if _contains_point(placed, world_pos, margin):
			hits.append(placed.instance_id)
	return hits


## 命中最上层的实例。给"点一下"这类只要一个结果的调用方用。
func instance_at(world_pos: Vector2, margin: float = 0.0) -> String:
	var hits := instances_at(world_pos, margin)
	return hits[0] if not hits.is_empty() else ""


func _contains_point(placed: PlacedEntity, world_pos: Vector2, margin: float = 0.0) -> bool:
	var def := project.find_entity(placed.entity_id)
	if def == null:
		return false
	var local := world_pos - Vector2(placed.x, placed.y)
	var scale_x := absf(placed.scale_x)
	var scale_y := absf(placed.scale_y)
	# 点选判定必须跟着缩放走，否则把一个对象拉宽之后，
	# 它看着很宽却只能在原来那一小块里点得中。
	if def.collider_shape == EntityDef.SHAPE_CIRCLE:
		var radius_x := maxf(def.collider_radius * scale_x, 4.0) + margin
		var radius_y := maxf(def.collider_radius * scale_y, 4.0) + margin
		var nx := local.x / radius_x
		var ny := local.y / radius_y
		return nx * nx + ny * ny <= 1.0
	var half := half_extent(def)
	half.x = half.x * scale_x + margin
	half.y = half.y * scale_y + margin
	return absf(local.x) <= half.x and absf(local.y) <= half.y


## 对象在画布上占多大。碰撞体形状决定外形，没有碰撞体就用默认方块。
static func half_extent(def: EntityDef) -> Vector2:
	match def.collider_shape:
		EntityDef.SHAPE_RECT:
			return Vector2(def.collider_width, def.collider_height) * 0.5
		EntityDef.SHAPE_CIRCLE:
			return Vector2(def.collider_radius, def.collider_radius)
	return Vector2(DEFAULT_HALF_EXTENT, DEFAULT_HALF_EXTENT)


# --------------------------------------------------------------------------
# 撤销 / 重做
# --------------------------------------------------------------------------

func push_undo(label: String) -> void:
	_push_undo(label)


func _push_undo(label: String) -> void:
	if project == null:
		return
	_undo.append({"label": label, "data": project.to_dict(), "scene": _scene_index})
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()
	_redo.clear()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo_label() -> String:
	return String(_undo.back().get("label", "")) if can_undo() else ""


func redo_label() -> String:
	return String(_redo.back().get("label", "")) if can_redo() else ""


func undo() -> bool:
	if not can_undo():
		return false
	var entry: Dictionary = _undo.pop_back()
	_redo.append({"label": entry["label"], "data": project.to_dict(), "scene": _scene_index})
	_restore(entry)
	return true


func redo() -> bool:
	if not can_redo():
		return false
	var entry: Dictionary = _redo.pop_back()
	_undo.append({"label": entry["label"], "data": project.to_dict(), "scene": _scene_index})
	_restore(entry)
	return true


func _restore(entry: Dictionary) -> void:
	var previous_selection := selected_instance_id
	project = GameProject.from_dict(entry["data"])
	_scene_index = clampi(int(entry["scene"]), 0, maxi(project.scenes.size() - 1, 0))
	# 撤销之后尽量保住选中状态。
	#
	# 用户按 Ctrl+Z 往往是想"改回去再接着调"，这时候如果连选中一起清掉，
	# 属性面板会关掉，想继续调还得重新点一遍对象 —— 撤销本来是帮忙的，
	# 结果反而多了一步。只有当那个对象在撤销后的工程里确实不存在了
	# （比如撤销的是"放置对象"），才清空选中。
	selected_instance_id = previous_selection if find_instance(previous_selection) != null else ""
	_mark_dirty()
	scene_switched.emit(_scene_index)


func _mark_dirty() -> void:
	dirty = true
	changed.emit()
