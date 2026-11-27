## 运行器：把一份 GameProject 变成真正能玩的场景。
##
## 职责边界很清楚：只管「把数据变成游戏并跑起来」，
## 不涉及任何编辑界面，因此可以在无界面模式下被完整测试。
class_name GameRuntime
extends Node2D

signal scene_started(scene_id: String)
signal game_ended(result: String, message: String)

var project: GameProject = null
var current_scene_def: SceneDef = null
var actors: Array[Actor] = []

var _by_instance: Dictionary = {}
var _engine: RuleEngine = null
var _running: bool = false
var _dyn_serial: int = 0
var _camera: Camera2D = null
var _backdrop: CanvasLayer = null
## 屏幕按键。每个元素：{ action, label, color, rect, pressed }
var _buttons: Array[Dictionary] = []
## 每根手指按在了哪个按键上：触摸编号 → 输入动作
var _touch_buttons: Dictionary = {}
var _button_layer: CanvasLayer = null
var _button_visual: ScreenButtons = null


func setup(p_project: GameProject) -> void:
	project = p_project


# --------------------------------------------------------------------------
# 生命周期
# --------------------------------------------------------------------------

func start(scene_id: String = "") -> void:
	if project == null:
		push_error("GameRuntime 尚未 setup(project)")
		return
	var scene: SceneDef = project.find_scene(scene_id) if not scene_id.is_empty() else project.start_scene()
	if scene == null:
		push_error("找不到要运行的场景：%s" % scene_id)
		return
	_build(scene)


func stop() -> void:
	_running = false
	_set_actors_paused(true)


## 彻底关闭：停掉规则、卸掉所有对象、断开碰撞区。
##
## 重开一局时必须走这里，而不是直接 queue_free()。
## 因为 queue_free 是延后到帧末执行的，中间会有一帧新旧两套对象同时存在于场景树里；
## 而 Area2D 之间的重叠检测是全局的，不认父子关系 ——
## 那一帧里上一关的尖刺完全可能把新一局的玩家扎到。
func shutdown() -> void:
	_running = false
	_clear_world()
	queue_free()


func is_running() -> bool:
	return _running


func _build(scene: SceneDef) -> void:
	_clear_world()
	current_scene_def = scene

	for placed in scene.instances:
		var def := project.find_entity(placed.entity_id)
		if def == null:
			push_warning("场景 %s 中的实例 %s 引用了不存在的实体 %s"
				% [scene.id, placed.instance_id, placed.entity_id])
			continue
		# 屏幕按键不放进游戏世界，单独收集起来
		if def.is_button():
			_add_button(def, placed)
			continue
		_instantiate(def, placed, Vector2(placed.x, placed.y))

	_apply_background(scene)
	_setup_camera(scene)
	_show_buttons()

	_engine = RuleEngine.new()
	_engine.setup(self, project, scene.id)

	_running = true
	_set_actors_paused(false)
	engine_emit("game_start", {})
	scene_started.emit(scene.id)


func _clear_world() -> void:
	if _engine != null:
		_engine.shutdown()
		_engine = null
	for actor in actors.duplicate():
		if is_instance_valid(actor):
			actor.teardown()
			actor.queue_free()
	actors.clear()
	_by_instance.clear()
	_dyn_serial = 0
	_camera = null
	_release_all_buttons()
	for button in _buttons:
		button["pressed"] = false
	_buttons.clear()
	if _button_layer != null and is_instance_valid(_button_layer):
		_button_layer.queue_free()
	_button_layer = null
	_button_visual = null
	if _backdrop != null and is_instance_valid(_backdrop):
		_backdrop.queue_free()
	_backdrop = null
	current_scene_def = null


## 背景用一个铺满视口的 ColorRect 放在最底层，而不是去改全局清屏色。
## 全局清屏色是引擎级的单例状态，一旦编辑器要把运行器塞进 SubViewport 预览，
## 两边会互相覆盖。自带背景层则天然支持多实例并存。
func _apply_background(scene: SceneDef) -> void:
	var hex := scene.background_color
	if hex.is_empty():
		hex = project.config.background_color
	if not Color.html_is_valid(hex):
		return

	_backdrop = CanvasLayer.new()
	_backdrop.layer = -100
	var rect := ColorRect.new()
	rect.color = Color(hex)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.add_child(rect)
	add_child(_backdrop)

	if scene.background_asset_id.is_empty():
		return
	var asset := project.find_asset(scene.background_asset_id)
	if asset == null or asset.path.is_empty() or not ResourceLoader.exists(asset.path):
		return
	var tex := load(asset.path)
	if tex is Texture2D:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.centered = false
		rect.add_child(sprite)


func _set_actors_paused(paused: bool) -> void:
	for actor in actors:
		if is_instance_valid(actor):
			actor.set_paused(paused)


# --------------------------------------------------------------------------
# 实体
# --------------------------------------------------------------------------

func _instantiate(def: EntityDef, placed: PlacedEntity, pos: Vector2) -> Actor:
	var actor := Actor.new()
	actor.name = placed.instance_id
	actor.setup(def, placed, project.config.gravity)
	actor.position = pos
	add_child(actor)

	actor.property_changed_signal.connect(_on_property_changed)
	actor.touched.connect(_on_touched)

	actors.append(actor)
	_by_instance[placed.instance_id] = actor
	return actor


## 供规则调用：按实体定义在指定位置生成一个对象。
func spawn_actor(entity_id: String, pos: Vector2, extra_tag: String = "") -> Actor:
	if project == null:
		return null
	var def := project.find_entity(entity_id)
	if def == null:
		push_warning("规则试图创建不存在的实体：%s" % entity_id)
		return null

	_dyn_serial += 1
	var placed := PlacedEntity.new()
	placed.instance_id = "dyn_%d" % _dyn_serial
	placed.entity_id = entity_id
	placed.x = pos.x
	placed.y = pos.y

	var actor := _instantiate(def, placed, pos)
	if not extra_tag.is_empty():
		actor.tags.append(extra_tag)
	engine_emit("entity_created", {"actor": actor})
	return actor


func destroy_actor(actor: Variant) -> void:
	if actor == null or not is_instance_valid(actor) or not actor.alive:
		return
	# 必须在物理回调里也能安全调用：先立刻让它从逻辑世界里消失，
	# 真正释放节点交给 queue_free 延后处理。
	actor.teardown()
	actors.erase(actor)
	_by_instance.erase(actor.instance_id)
	actor.queue_free()
	if _engine != null:
		engine_emit("entity_destroyed", {"actor": actor})


func actors_with_tag(tag: String) -> Array:
	var out: Array = []
	for actor in actors:
		if is_instance_valid(actor) and actor.alive and actor.tags.has(tag):
			out.append(actor)
	return out


func actor_by_instance(instance_id: String) -> Variant:
	return _by_instance.get(instance_id)


# --------------------------------------------------------------------------
# 事件
# --------------------------------------------------------------------------

func engine_emit(kind: String, payload: Dictionary) -> void:
	if _engine != null:
		_engine.emit_event(kind, payload)


func _physics_process(_delta: float) -> void:
	if _running:
		engine_emit("every_frame", {})


func _on_property_changed(actor: Actor, key: String, old_value: Variant, new_value: Variant) -> void:
	engine_emit("property_change", {
		"actor": actor,
		"property": key,
		"old": old_value,
		"new": new_value,
	})


func _on_touched(actor: Actor, other: Actor) -> void:
	# 两个对象的触发区会各报告一次同样的接触，
	# 只让 instance_id 较小的一方转发，保证一条规则一次碰撞只跑一遍。
	if not actor.alive or not other.alive:
		return
	if actor.instance_id > other.instance_id:
		return
	engine_emit("collision", {"self": actor, "other": other})


func end_game(result: String, message: String) -> void:
	if not _running:
		return
	_running = false
	_set_actors_paused(true)
	game_ended.emit(result, message)


func _unhandled_input(event: InputEvent) -> void:
	if not _running:
		return
	# project.godot 里开启了鼠标模拟触摸，因此这里只处理触摸事件，
	# 否则一次点击会被当成两次。
	if event is InputEventScreenTouch:
		if event.pressed:
			# 手指落在屏幕按键上：按下对应的输入动作，并且**不再算"点击屏幕"**。
			# 少了这一步，按左键移动的同时会触发"点击跳跃"——
			# 这正是"拿半块屏幕当方向键"那个土办法解决不了的问题。
			var action := _button_action_at(event.position)
			if not action.is_empty():
				_touch_buttons[event.index] = action
				_press_action(action)
				return
			engine_emit("tap", {})
		else:
			if _touch_buttons.has(event.index):
				_release_action(String(_touch_buttons[event.index]))
				_touch_buttons.erase(event.index)
	elif event is InputEventKey and event.pressed and not event.echo:
		engine_emit("key_press", {"key": OS.get_keycode_string(event.keycode)})


# --------------------------------------------------------------------------
# 查询（供 HUD 与测试使用）
# --------------------------------------------------------------------------

func query_property(selector: String, property: String) -> Variant:
	if _engine == null:
		return null
	var targets := _engine.resolve(selector, {})
	if targets.is_empty():
		return null
	return targets[0].get_property(property)


func alive_count(tag: String = "") -> int:
	if tag.is_empty():
		return actors.size()
	return actors_with_tag(tag).size()


## 当前生效的背景色。给测试用，也给编辑器的取色器回显用。
func background_color() -> Color:
	if _backdrop == null or not is_instance_valid(_backdrop) or _backdrop.get_child_count() == 0:
		return Color(0, 0, 0, 0)
	var rect := _backdrop.get_child(0) as ColorRect
	return rect.color if rect != null else Color(0, 0, 0, 0)


# --------------------------------------------------------------------------
# 相机
# --------------------------------------------------------------------------


# --------------------------------------------------------------------------
# 屏幕按键
# --------------------------------------------------------------------------
#
# 它解决的是一个很具体的问题：手机上没法"按住方向键"。
# 之前试过"按住屏幕左半边就向左走"，但触摸本身又会被当成"点击屏幕"，
# 于是每次开始移动都会先跳一下 —— 同一个触摸动作承载不了两种含义。
#
# 按键把这件事说清楚了：手指落在按键上就是这个按键，落在别处就不是。
# 而且按下去等于按着那个输入动作，键盘和触屏因此共用同一套规则。

func _add_button(def: EntityDef, placed: PlacedEntity) -> void:
	var width := maxf(def.collider_width, 64.0)
	var height := maxf(def.collider_height, 64.0)
	var center := Vector2(placed.x, placed.y)
	var tint := Color(def.color) if placed.color.is_empty() else Color(placed.color)
	var circle := def.collider_shape == EntityDef.SHAPE_CIRCLE

	# 把外观做成样式对象而不是每帧现画，按下时只改颜色即可。
	# 圆形用"圆角等于半径"来实现，比单独写一套画圆的路径简单得多。
	var style := StyleBoxFlat.new()
	var radius := int(minf(width, height) * 0.5) if circle else int(minf(width, height) * 0.3)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	_style_button(style, tint, false)

	var action := def.button_action if placed.button_action.is_empty() else placed.button_action
	_buttons.append({
		"action": action,
		# 按键上写的字跟的是**绑定的动作**，不是实体类型的名字。
		# 复制一个"左"键出来绑成跳跃，字必须跟着变 ——
		# 否则屏幕上写着左、按下去却是跳，用户会以为程序坏了。
		# 表里没有的动作退回实体自己的名字（创作者起的名总比空白强）。
		"label": _label_for(action, def.name),
		"arrow": RuleVocabulary.button_action_arrow(action),
		"color": tint,
		"style": style,
		"rect": Rect2(center - Vector2(width, height) * 0.5, Vector2(width, height)),
		"pressed": false,
	})


## 方向键画箭头、其它键写名字。箭头是通用的，不用认字也知道往哪走。
static func _label_for(action: String, fallback: String) -> String:
	var text := RuleVocabulary.button_action_label(action)
	return text if not text.is_empty() else fallback


static func _style_button(style: StyleBoxFlat, tint: Color, pressed: bool) -> void:
	var fill := tint.lightened(0.3) if pressed else tint
	# 没按的时候透一些，让游戏画面从底下透出来 —— 按键是盖在游戏上的，
	# 太实会把角色挡住。按下时变实，反馈也更明显。
	style.bg_color = Color(fill.r, fill.g, fill.b, 0.85 if pressed else 0.5)
	style.border_color = Color(1, 1, 1, 0.9 if pressed else 0.4)


func _show_buttons() -> void:
	if _buttons.is_empty():
		return
	_button_layer = CanvasLayer.new()
	_button_layer.layer = 1
	add_child(_button_layer)
	_button_visual = ScreenButtons.new()
	_button_visual.buttons = _buttons
	_button_layer.add_child(_button_visual)
	_button_visual.refresh()


## 手指落在哪个按键上？从后往前找，后放的压在上面。
func _button_action_at(point: Vector2) -> String:
	for i in range(_buttons.size() - 1, -1, -1):
		var rect: Rect2 = _buttons[i]["rect"]
		if rect.has_point(point):
			return String(_buttons[i]["action"])
	return ""


func _press_action(action: String) -> void:
	if not InputMap.has_action(action):
		push_warning("屏幕按键绑定了一个不存在的输入动作：%s" % action)
		return
	Input.action_press(action)
	_highlight_button(action, true)


func _release_action(action: String) -> void:
	if InputMap.has_action(action):
		Input.action_release(action)
	_highlight_button(action, false)


func _release_all_buttons() -> void:
	for index in _touch_buttons:
		_release_action(String(_touch_buttons[index]))
	_touch_buttons.clear()


func _highlight_button(action: String, pressed: bool) -> void:
	for button in _buttons:
		if String(button["action"]) == action:
			button["pressed"] = pressed
			_style_button(button["style"], button["color"], pressed)
	if _button_visual != null and is_instance_valid(_button_visual):
		_button_visual.refresh()


## 场景里所有屏幕按键的位置与绑定（给测试用）
func button_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for button in _buttons:
		out.append(button["rect"])
	return out


func button_actions() -> PackedStringArray:
	var out := PackedStringArray()
	for button in _buttons:
		out.append(String(button["action"]))
	return out


## 按键上分别写了什么字、画了哪个箭头（给测试用）
func button_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for button in _buttons:
		out.append(String(button["label"]))
	return out


func button_arrows() -> PackedStringArray:
	var out := PackedStringArray()
	for button in _buttons:
		out.append(String(button["arrow"]))
	return out


func _setup_camera(scene: SceneDef) -> void:
	if scene.camera_mode != SceneDef.CAMERA_FOLLOW:
		return
	var targets := actors_with_tag(_tag_of_selector(scene.camera_target))
	if targets.is_empty():
		push_warning("场景 %s 设置了相机跟随 %s，但找不到目标" % [scene.id, scene.camera_target])
		return
	var cam := Camera2D.new()
	cam.zoom = Vector2(scene.camera_zoom, scene.camera_zoom)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0
	targets[0].add_child(cam)
	cam.make_current()
	_camera = cam


static func _tag_of_selector(selector: String) -> String:
	var parsed := RuleVocabulary.parse_selector(selector)
	return String(parsed["value"]) if parsed["kind"] == "tag" else ""
