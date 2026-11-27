## 运行时的实体。
##
## 采用 CharacterBody2D 统一承载「静止」与「运动」两类对象。
## 这是一个刻意的设计取舍：本产品的逻辑系统是事件—条件—动作，
## 规则直接设定速度（set_velocity / apply_impulse / jump），
## 而刚体（RigidBody）由物理引擎掌控速度，两套语义会互相打架。
## 因此刚体留到后续版本，用一套独立的力量型动作来支持。
class_name Actor
extends CharacterBody2D

const MAX_FALL_SPEED := 4000.0
const DEFAULT_VISUAL_SIZE := 48.0
## 触发区相对实体碰撞体外扩的像素数。
##
## 这个常量解决一个很容易踩的坑：Godot 的 Area2D 只在形状**相交**时报告，
## 而两个固体碰在一起时只是相切，不会相交，于是「玩家碰到敌人」这类规则
## 永远不会触发。把触发区外扩几像素，实体一贴上规则就能感知到。
const HITBOX_MARGIN := 4.0
## 椭圆碰撞体用多少条边逼近。24 段对物理来说已经足够圆滑。
const ELLIPSE_SEGMENTS := 24
## 物理层的编号：普通对象在第 1 层，拾取物（金币这类）在第 2 层。
##
## 分成两层之后，"拾取物不挡玩家、也不互相挡"就是免费的：
##   玩家（第 1 层，掩码只有第 1 层）压根不会和金币发生实体碰撞
##   金币的掩码里只有第 1 层，所以它照样落在地面上
## 而**触发区（Area2D）两层都检测** —— 判定"碰到没有"、执行规则靠的是
## 触发区而不是实体碰撞，这条线不能跟着一起变，否则金币就吃不到了。
##
## 第 3 层是后来补的：**会动的对象单独一层**。
## 起因是用户报"金币会粘在小怪身上跟小怪一起走" —— 金币和小怪之间本来
## 有实体碰撞，而 Godot 会把"脚下的东西"当成移动平台带着走，
## 于是小怪一跑，站在它上面的金币就跟着跑。
## 现在拾取物的掩码里只有第 1 层（不动的地形），它只落在真正不动的东西上。
const LAYER_SOLID := 1
const LAYER_PICKUP := 2
const LAYER_MOVING := 4
## 第 4 层：地面。**只有它接得住掉落物。**
## 用户的要求是"金币只跟地面碰撞"——所以尖刺、静止的怪这些"普通障碍"
## 归 solid 那一层，金币会从它们身上穿过去，落到真正的地面上。
const LAYER_GROUND := 8

signal property_changed_signal(actor: Actor, key: String, old_value: Variant, new_value: Variant)
signal touched(actor: Actor, other: Actor)
signal untouched(actor: Actor, other: Actor)

var definition: EntityDef
var instance_id: String = ""
var tags: PackedStringArray = PackedStringArray()
var properties: Dictionary = {}
var alive: bool = true

var _gravity: float = 0.0
## 这个对象最终用的物理模式与重力倍率（实例可以覆盖类型，见 PlacedEntity.motion）
var _physics_mode: String = EntityDef.PHYSICS_NONE
var _gravity_scale: float = 1.0
var _visual: PlaceholderVisual
var _hitbox: Area2D
var _body_shape: CollisionShape2D
var _overlaps: Dictionary = {}
var _current_animation: String = ""
## 实例缩放对碰撞体的影响。视觉会缩放，碰撞体也必须跟着缩放，
## 否则"把平台拉宽"只变了样子、没有真的变宽，玩起来对不上。
var _collider_scale: Vector2 = Vector2.ONE


func setup(p_def: EntityDef, p_inst: PlacedEntity, p_gravity: float) -> void:
	definition = p_def
	instance_id = p_inst.instance_id
	_gravity = p_gravity
	tags = p_def.tags.duplicate()

	# 物理模式和重力都走"实例覆盖类型"那一套：用户在属性面板里把某个对象
	# 改成"会动"之后，运行器必须听他的，而不是听类型上写的。
	var motion := PlacedEntity.resolve_motion(p_def, p_inst)
	_physics_mode = String(motion["mode"])
	_gravity_scale = float(motion["gravity_scale"])

	position = Vector2(p_inst.x, p_inst.y)
	rotation = p_inst.rotation

	properties = p_def.initial_properties.duplicate(true)
	for key in p_inst.properties:
		properties[key] = p_inst.properties[key]

	# 谁能挡住谁，全在这里定：
	#   地面        第 4 层（8）：接得住会动的东西，也接得住掉落物
	#   普通障碍    第 1 层（1）：挡得住会动的东西，掉落物会穿过去
	#   拾取物      第 2 层（2）：不挡任何人，**只和地面碰**
	#   会动的对象  第 3 层（4）：撞得动地面和普通障碍，也撞得动彼此
	var group := PlacedEntity.resolve_collision_group(p_def, p_inst)
	if group == EntityDef.COLLISION_PICKUP:
		collision_layer = LAYER_PICKUP
		collision_mask = LAYER_GROUND
	elif _is_dynamic():
		collision_layer = LAYER_MOVING
		collision_mask = LAYER_SOLID | LAYER_MOVING | LAYER_GROUND
	elif group == EntityDef.COLLISION_GROUND:
		collision_layer = LAYER_GROUND
		collision_mask = LAYER_SOLID | LAYER_MOVING
	else:
		collision_layer = LAYER_SOLID
		collision_mask = LAYER_SOLID | LAYER_MOVING
	motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	floor_snap_length = 8.0
	up_direction = Vector2.UP

	var visual_size := _resolve_visual_size()
	_collider_scale = Vector2(absf(p_inst.scale_x), absf(p_inst.scale_y))

	_visual = PlaceholderVisual.new()
	# 实例自己设了颜色就用它的，否则跟随实体定义
	var tint := Color(p_def.color) if p_inst.color.is_empty() else Color(p_inst.color)
	_visual.configure(_visual_shape(), visual_size, tint)
	_visual.scale = Vector2(
		-p_inst.scale_x if p_inst.flip_h else p_inst.scale_x,
		p_inst.scale_y)
	add_child(_visual)

	# 只有真正参与物理的对象才拿到实体碰撞体。
	# 物理类型为 none 的对象（金币、检查点、拾取物）只保留触发区，
	# 否则它会挡住玩家 —— 这是最容易被忽略、又最影响手感的一个坑。
	if p_def.collider_shape != EntityDef.SHAPE_NONE and _physics_mode != EntityDef.PHYSICS_NONE:
		_body_shape = CollisionShape2D.new()
		_body_shape.shape = _make_shape(visual_size)
		_body_shape.position = Vector2(p_def.collider_offset_x, p_def.collider_offset_y)
		add_child(_body_shape)

	if p_def.collider_shape != EntityDef.SHAPE_NONE:
		_hitbox = Area2D.new()
		_hitbox.collision_layer = LAYER_SOLID
		_hitbox.collision_mask = LAYER_SOLID | LAYER_PICKUP
		_hitbox.monitoring = true
		_hitbox.monitorable = true
		var hit_shape := CollisionShape2D.new()
		hit_shape.shape = _make_hitbox_shape(visual_size)
		hit_shape.position = Vector2(p_def.collider_offset_x, p_def.collider_offset_y)
		_hitbox.add_child(hit_shape)
		add_child(_hitbox)
		_hitbox.area_entered.connect(_on_area_entered)
		_hitbox.area_exited.connect(_on_area_exited)

	_current_animation = p_def.default_animation
	# 只有运动对象需要参与物理步进。静止对象和触发物若也调用 move_and_slide()，
	# 引擎会在解穿插时把它们推开，出现「地面被玩家压着一起下沉」的现象。
	set_physics_process(_is_dynamic())


func _is_dynamic() -> bool:
	return _physics_mode == EntityDef.PHYSICS_KINEMATIC


## 统一控制这个对象是否参与物理。暂停时必须尊重对象本身的类型，
## 不能简单地一刀切打开。
func set_paused(paused: bool) -> void:
	set_physics_process(_is_dynamic() and not paused)


func _resolve_visual_size() -> Vector2:
	match definition.collider_shape:
		EntityDef.SHAPE_RECT:
			return Vector2(definition.collider_width, definition.collider_height)
		EntityDef.SHAPE_CIRCLE:
			return Vector2(definition.collider_radius * 2.0, definition.collider_radius * 2.0)
		_:
			return Vector2(DEFAULT_VISUAL_SIZE, DEFAULT_VISUAL_SIZE)


func _visual_shape() -> String:
	return PlaceholderVisual.SHAPE_CIRCLE if definition.collider_shape == EntityDef.SHAPE_CIRCLE \
		else PlaceholderVisual.SHAPE_RECT


func _make_shape(size: Vector2) -> Shape2D:
	if definition.collider_shape == EntityDef.SHAPE_CIRCLE:
		return _make_ellipse_shape(
			definition.collider_radius * _collider_scale.x,
			definition.collider_radius * _collider_scale.y)
	var r := RectangleShape2D.new()
	r.size = size * _collider_scale
	return r


## 构造椭圆碰撞体。
##
## Godot 2D 没有现成的椭圆图元，所以：横纵半径相等时用真正的圆
## （精确、代价小），不相等时用多边形逼近一个椭圆。
## 在此之前这里取的是横纵缩放的平均值 —— 于是"把金币拉宽"
## 在画面上是椭圆、在碰撞上却只是个变大的圆，两者对不上。
func _make_ellipse_shape(radius_x: float, radius_y: float) -> Shape2D:
	if is_equal_approx(radius_x, radius_y):
		var circle := CircleShape2D.new()
		circle.radius = radius_x
		return circle
	var polygon := ConvexPolygonShape2D.new()
	var points := PackedVector2Array()
	for i in ELLIPSE_SEGMENTS:
		var angle := TAU * float(i) / float(ELLIPSE_SEGMENTS)
		points.append(Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	polygon.points = points
	return polygon


## 构造外扩后的触发区形状
func _make_hitbox_shape(size: Vector2) -> Shape2D:
	if definition.collider_shape == EntityDef.SHAPE_CIRCLE:
		return _make_ellipse_shape(
			definition.collider_radius * _collider_scale.x + HITBOX_MARGIN,
			definition.collider_radius * _collider_scale.y + HITBOX_MARGIN)
	var r := RectangleShape2D.new()
	r.size = size * _collider_scale + Vector2(HITBOX_MARGIN, HITBOX_MARGIN) * 2.0
	return r


# --------------------------------------------------------------------------
# 物理
# --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not alive or not _is_dynamic():
		return
	if not is_on_floor():
		velocity.y = minf(velocity.y + _gravity * _gravity_scale * delta, MAX_FALL_SPEED)
	elif velocity.y > 0.0:
		velocity.y = 0.0
	move_and_slide()


func is_grounded() -> bool:
	return is_on_floor()


func jump_with_height(height: float) -> void:
	var g := maxf(_gravity * _gravity_scale, 1.0)
	velocity.y = -sqrt(2.0 * g * maxf(height, 1.0))


func play_animation(animation_name: String) -> void:
	# 目前没有调用方：词汇表里那个「播放动画」动作已经删掉了 ——
	# 没有动画系统，用户选了也只是记个名字、画面毫无变化，
	# 摆在下拉栏里属于骗人。这个方法留着，是将来接帧动画时的接口。
	_current_animation = animation_name


func current_animation() -> String:
	return _current_animation


# --------------------------------------------------------------------------
# 属性
# --------------------------------------------------------------------------

func get_property(key: String) -> Variant:
	return properties.get(key, 0)


func has_property(key: String) -> bool:
	return properties.has(key)


func set_property(key: String, value: Variant) -> void:
	var old: Variant = properties.get(key, null)
	if old != null and _values_equal(old, value):
		return
	properties[key] = value
	property_changed_signal.emit(self, key, old, value)


func change_property(key: String, delta: float) -> void:
	var current: Variant = properties.get(key, 0)
	var base := float(current) if _is_number(current) else 0.0
	set_property(key, base + delta)


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func _values_equal(a: Variant, b: Variant) -> bool:
	if _is_number(a) and _is_number(b):
		return is_equal_approx(float(a), float(b))
	return a == b


# --------------------------------------------------------------------------
# 碰撞
# --------------------------------------------------------------------------

func _on_area_entered(area: Area2D) -> void:
	var other := _actor_of(area)
	if other == null or other == self:
		return
	_overlaps[other.instance_id] = true
	touched.emit(self, other)


func _on_area_exited(area: Area2D) -> void:
	var other := _actor_of(area)
	if other == null:
		return
	_overlaps.erase(other.instance_id)
	untouched.emit(self, other)


static func _actor_of(area: Area2D) -> Actor:
	var parent := area.get_parent()
	return parent if parent is Actor else null


func is_touching(other: Actor) -> bool:
	return _overlaps.has(other.instance_id)


func overlapping_actors() -> Array:
	return _overlaps.keys()


func teardown() -> void:
	alive = false
	_overlaps.clear()
	velocity = Vector2.ZERO
	set_physics_process(false)
	# 物理回调过程中不能直接改这些标志，必须延后一帧
	if _hitbox != null and is_instance_valid(_hitbox):
		_hitbox.set_deferred("monitoring", false)
		_hitbox.set_deferred("monitorable", false)
