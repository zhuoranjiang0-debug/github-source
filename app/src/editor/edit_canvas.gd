## 编辑画布：把工程里的对象画出来，并接住鼠标。
##
## 这里刻意不实例化运行时的 Actor 节点，而是自己用 _draw() 画占位图形。
## 原因很简单：编辑器里不需要物理、不需要碰撞、不需要重力，
## 拿一整套运行时的东西来做编辑，只会让画面和交互都变难控制。
class_name EditCanvas
extends Control

signal selection_changed(instance_id: String)
signal instance_placed(entity_id: String, world_pos: Vector2)

const MARGIN := 24.0
const GRID_STEP := 64.0
const MIN_SCALE := 0.15
const MAX_SCALE := 4.0
const SELECT_COLOR := Color("#38bdf8")
## 椭圆用多少条边逼近。40 段在缩放之后也看不出棱角。
const ELLIPSE_SEGMENTS := 40
## 触屏上点选额外放宽的屏幕像素。手指的接触面大约 9 毫米，
## 换成屏幕像素是几十个，全放开会误选，取其中一小部分刚刚好。
const TOUCH_HIT_MARGIN_PX := 14.0
## 两次点击相隔多少屏幕像素以内，算"点了同一个地方"。
## 用它来决定要不要往下钻：钻得太容易会误伤正常点击，太难点就钻不动。
const SAME_SPOT_PX := 8.0

var session: EditSession = null

var _scale: float = 1.0
var _offset: Vector2 = Vector2.ZERO
var _drag_offset: Vector2 = Vector2.ZERO
var _drag_undo_pushed: bool = false

## 当前指针在做什么。用一个状态代替一堆布尔量，
## 免得出现"既在拖动又在平移"这种自相矛盾的组合。
enum Pointer { NONE, OBJECT, PAN, PINCH }
var _pointer: Pointer = Pointer.NONE
## 上一次指针的位置，用来算平移的位移
var _last_pointer_pos: Vector2 = Vector2.ZERO

## 正在按下的手指：index → 位置。只有出现两根及以上时才用来做捏合。
var _touches: Dictionary = {}
var _pinch_distance: float = 1.0
var _pinch_scale: float = 1.0

## 上一次点中的那一摞对象，以及点的是第几个（最上面是第 0 个）。
## 同一个地方再点一下，就往下钻一层 —— 两个对象完全叠住时，
## 底下那个否则永远选不到。
var _stack: Array[String] = []
var _stack_index: int = 0
var _last_press_pos: Vector2 = Vector2.ZERO
var _pinch_anchor: Vector2 = Vector2.ZERO
## 捏合期间把单指操作锁住，直到所有手指都离开
var _ignore_pointer: bool = false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	resized.connect(_fit_to_view)


func set_session(p_session: EditSession) -> void:
	session = p_session
	_fit_to_view()
	queue_redraw()


func refresh() -> void:
	queue_redraw()


## 当前的缩放与平移（供测试与后续功能查询）
func view_scale() -> float:
	return _scale


func view_offset() -> Vector2:
	return _offset


## 点选要放宽多少（世界单位）。只在真的有触摸屏的设备上放宽，
## 纯鼠标的电脑保持精确，免得点两个挨着的对象时总选错。
func _hit_margin() -> float:
	if not DisplayServer.is_touchscreen_available():
		return 0.0
	return TOUCH_HIT_MARGIN_PX / maxf(_scale, 0.01)


# --------------------------------------------------------------------------
# 坐标换算
# --------------------------------------------------------------------------

func world_to_screen(world: Vector2) -> Vector2:
	return _offset + world * _scale


func screen_to_world(screen: Vector2) -> Vector2:
	if _scale <= 0.0:
		return Vector2.ZERO
	return (screen - _offset) / _scale


func _canvas_size() -> Vector2:
	if session == null or session.project == null:
		return Vector2(1280, 720)
	return Vector2(session.project.config.canvas_width, session.project.config.canvas_height)


## 让整个画布正好铺满可见区域
func _fit_to_view() -> void:
	var canvas := _canvas_size()
	if canvas.x <= 0.0 or canvas.y <= 0.0:
		return
	var available := size - Vector2(MARGIN, MARGIN) * 2.0
	if available.x <= 1.0 or available.y <= 1.0:
		return
	_scale = minf(available.x / canvas.x, available.y / canvas.y)
	_offset = (size - canvas * _scale) * 0.5
	queue_redraw()


# --------------------------------------------------------------------------
# 绘制
# --------------------------------------------------------------------------

func _draw() -> void:
	if session == null or session.project == null:
		return
	var canvas := _canvas_size()
	var rect := Rect2(_offset, canvas * _scale)

	draw_rect(rect, Color(session.project.config.background_color), true)
	_draw_grid(rect, canvas)

	var scene := session.current_scene()
	if scene != null:
		for placed in scene.instances:
			_draw_instance(placed)

	draw_rect(rect, Color(1, 1, 1, 0.20), false, 1.0)


func _draw_grid(rect: Rect2, canvas: Vector2) -> void:
	var color := Color(1, 1, 1, 0.05)
	var x := GRID_STEP
	while x < canvas.x:
		var sx := _offset.x + x * _scale
		draw_line(Vector2(sx, rect.position.y), Vector2(sx, rect.end.y), color, 1.0)
		x += GRID_STEP
	var y := GRID_STEP
	while y < canvas.y:
		var sy := _offset.y + y * _scale
		draw_line(Vector2(rect.position.x, sy), Vector2(rect.end.x, sy), color, 1.0)
		y += GRID_STEP


func _draw_instance(placed: PlacedEntity) -> void:
	var def := session.project.find_entity(placed.entity_id)
	if def == null:
		# 引用了不存在的实体：画一个醒目的问号框，比默默不画好得多
		var missing := world_to_screen(Vector2(placed.x, placed.y))
		var half := Vector2(24, 24) * _scale
		draw_rect(Rect2(missing - half, half * 2.0), Color("#7f1d1d"), true)
		draw_rect(Rect2(missing - half, half * 2.0), Color("#f87171"), false, 2.0)
		return

	var center := world_to_screen(Vector2(placed.x, placed.y))
	var color := session.effective_color(placed)
	var selected := placed.instance_id == session.selected_instance_id
	# 取绝对值：负缩放表示翻转，不该把形状算成负数大小
	var scale_x := absf(placed.scale_x)
	var scale_y := absf(placed.scale_y)

	if def.collider_shape == EntityDef.SHAPE_CIRCLE:
		# 画成椭圆。横纵分别缩放本来就该得到椭圆 ——
		# 之前这里只乘了横向缩放，于是"纵向调大"在画布上毫无反应，
		# 和运行器里的表现对不上。
		var radius := maxf(def.collider_radius, 4.0) * _scale
		var points := _ellipse_points(center, radius * scale_x, radius * scale_y)
		draw_colored_polygon(points, color)
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, Color(0, 0, 0, 0.25), 1.5, true)
	else:
		var half := EditSession.half_extent(def) * _scale
		half.x *= scale_x
		half.y *= scale_y
		draw_rect(Rect2(center - half, half * 2.0), color, true)
		draw_rect(Rect2(center - half, half * 2.0), Color(0, 0, 0, 0.25), false, 1.5)

	if selected:
		var box_half := EditSession.half_extent(def) * _scale
		box_half.x *= scale_x
		box_half.y *= scale_y
		box_half += Vector2(4, 4)
		draw_rect(Rect2(center - box_half, box_half * 2.0), SELECT_COLOR, false, 2.0)
		# 四角小方块，暗示这个对象可以拖动
		var corners: Array[Vector2] = [
			Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1),
		]
		for corner in corners:
			var p: Vector2 = center + corner * box_half
			draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), SELECT_COLOR, true)


## 椭圆上的采样点。Godot 2D 没有现成的椭圆图元：
## 编辑器里用多边形画出来，运行器的碰撞体同样用多边形逼近，两边保持一致。
static func _ellipse_points(center: Vector2, radius_x: float, radius_y: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in ELLIPSE_SEGMENTS:
		var angle := TAU * float(i) / float(ELLIPSE_SEGMENTS)
		points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	return points


# --------------------------------------------------------------------------
# 交互
# --------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if session == null or session.project == null:
		return
	if event is InputEventMouseButton:
		_handle_button(event)
	elif event is InputEventMouseMotion:
		_handle_motion(event)
	elif event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_touch_drag(event)


func _handle_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_zoom_at(event.position, 1.15)
				accept_event()
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_zoom_at(event.position, 1.0 / 1.15)
				accept_event()
		MOUSE_BUTTON_MIDDLE:
			_pointer = Pointer.PAN if event.pressed else Pointer.NONE
			accept_event()
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_left_press(event.position)
			else:
				_end_left_press()
			accept_event()


func _begin_left_press(screen_pos: Vector2) -> void:
	# 捏合过程中要把单指操作完全锁住。第二根手指抬起、还剩一根时，
	# 系统可能重新把它当成鼠标，这时候如果放开限制，画面会突然跳一下。
	if _ignore_pointer:
		return
	var world := screen_to_world(screen_pos)
	var hits := session.instances_at(world, _hit_margin())
	var hit := ""
	if hits.is_empty():
		_stack = []
		_stack_index = 0
	else:
		# 同一个地方连着点：往下钻一层，钻到底就绕回最上面那个。
		# 这是画图软件里的老办法，触屏上尤其需要 —— 平板没有 Alt 键可用。
		var index := 0
		if not _stack.is_empty() and _last_press_pos.distance_to(screen_pos) <= SAME_SPOT_PX:
			var current := hits.find(session.selected_instance_id)
			if current >= 0:
				index = (current + 1) % hits.size()
		_stack = hits
		_stack_index = index
		_last_press_pos = screen_pos
		hit = hits[index]
	session.select_instance(hit)
	selection_changed.emit(hit)
	_last_pointer_pos = screen_pos

	if hit.is_empty():
		# 按在空白处：取消选中，同时准备平移画布。
		# 手机上这是唯一的平移方式（没有中键）；电脑上也比中键拖动顺手。
		_pointer = Pointer.PAN
	else:
		var placed := session.find_instance(hit)
		_pointer = Pointer.OBJECT
		_drag_undo_pushed = false
		if placed != null:
			_drag_offset = world - Vector2(placed.x, placed.y)
	queue_redraw()


## 给状态栏用：告诉用户"这里其实叠着好几个，再点一下选下面那个"。
##
## 没有这句提示的话，用户点来点去只看到同一个选中框（颜色还都一样），
## 会以为底下那个没了 —— 而它一直都在。
func overlap_note() -> String:
	if _stack.size() <= 1:
		return ""
	return "（这里叠着 %d 个，这是第 %d 个；再点一下选下面那个）" % [_stack.size(), _stack_index + 1]


func _end_left_press() -> void:
	_pointer = Pointer.NONE
	_drag_undo_pushed = false


func _handle_motion(event: InputEventMouseMotion) -> void:
	if _pointer == Pointer.PAN:
		# 用"当前位置减去上一次位置"算位移，而不是用 event.relative。
		# 触摸模拟出来的鼠标事件里 relative 不一定可靠，用坐标差最稳。
		_offset += event.position - _last_pointer_pos
		_last_pointer_pos = event.position
		queue_redraw()
		accept_event()
		return

	if _pointer != Pointer.OBJECT or session.selected_instance_id.is_empty():
		return

	# 拖动过程中只在第一次真正移动时记一次撤销，
	# 否则鼠标稍微一抖就会塞进一堆没有意义的撤销步骤。
	if not _drag_undo_pushed:
		session.push_undo("移动对象")
		_drag_undo_pushed = true

	var target := screen_to_world(event.position) - _drag_offset
	# 取整：让保存出来的 JSON 是干净的数字，而不是 812.3734 这种
	session.move_instance(session.selected_instance_id, Vector2(roundf(target.x), roundf(target.y)))
	queue_redraw()
	accept_event()


# --------------------------------------------------------------------------
# 触摸：只负责"两根手指"的捏合
# --------------------------------------------------------------------------
#
# 单指不用在这里处理 —— Godot 会把触摸模拟成鼠标事件，
# 上面那条路已经管了。这里只在出现第二根手指时才介入，
# 因此不会和鼠标那条路重复执行。

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			_begin_pinch()
	else:
		_touches.erase(event.index)
		if _pointer == Pointer.PINCH and _touches.size() < 2:
			_pointer = Pointer.NONE
		if _touches.is_empty():
			_ignore_pointer = false


func _handle_touch_drag(event: InputEventScreenDrag) -> void:
	_touches[event.index] = event.position
	if _pointer == Pointer.PINCH:
		_update_pinch()
		accept_event()


func _touch_pair() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for index in _touches:
		points.append(_touches[index])
		if points.size() == 2:
			break
	return points


func _begin_pinch() -> void:
	# 第二根手指一落下，立刻放弃正在进行的拖动。
	# 不这么做的话，你一边捏合缩放，被拖着的那个对象一边跟着手指飞。
	_pointer = Pointer.NONE
	_drag_undo_pushed = false
	_ignore_pointer = true

	var points := _touch_pair()
	if points.size() < 2:
		return
	_pinch_distance = maxf(points[0].distance_to(points[1]), 1.0)
	_pinch_scale = _scale
	# 记住"按下那一刻，两指中点指着画布上的哪个点"
	_pinch_anchor = screen_to_world((points[0] + points[1]) * 0.5)
	_pointer = Pointer.PINCH


func _update_pinch() -> void:
	var points := _touch_pair()
	if points.size() < 2:
		return
	var mid := (points[0] + points[1]) * 0.5
	var distance := maxf(points[0].distance_to(points[1]), 1.0)

	_scale = clampf(_pinch_scale * (distance / _pinch_distance), MIN_SCALE, MAX_SCALE)
	# 一行同时算完缩放和平移：让那个锚点始终待在当前两指中点下面。
	# 分两段算的话，会出现"一边缩放一边飘"的经典毛病。
	_offset = mid - _pinch_anchor * _scale
	queue_redraw()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := screen_to_world(screen_pos)
	_scale = clampf(_scale * factor, MIN_SCALE, MAX_SCALE)
	_offset = screen_pos - before * _scale
	queue_redraw()


# --------------------------------------------------------------------------
# 从素材栏拖进来
# --------------------------------------------------------------------------

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and String(data.get("type", "")) == "entity"


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var world := screen_to_world(at_position)
	instance_placed.emit(String(data["entity_id"]), Vector2(roundf(world.x), roundf(world.y)))
