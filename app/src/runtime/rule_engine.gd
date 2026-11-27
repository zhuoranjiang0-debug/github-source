## 事件—条件—动作规则引擎。
##
## 求值语义（有意保持简单可预测，宁可牺牲表达力也不要让用户猜）：
##   · 条件之间是「并且」，全部成立才执行动作。
##   · 带对象选择器的条件，只要选中的对象里**有任意一个**满足即算成立。
##   · 动作按顺序执行，未指定目标时对选中的全部对象生效。
##   · 事件在对象之间只触发一次（成对碰撞不会重复计分）。
class_name RuleEngine
extends RefCounted

## 防止「改属性 → 触发规则 → 又改属性」无限递归
const MAX_CASCADE_DEPTH := 8

var runtime: Node = null

var _rules: Array[RuleDef] = []
var _timers: Array[Timer] = []
var _depth: int = 0
var _dead: bool = false


func setup(p_runtime: Node, project: GameProject, scene_id: String) -> void:
	runtime = p_runtime
	_rules = []
	_clear_timers()
	for rule in project.rules:
		if not rule.enabled:
			continue
		if not rule.scene_id.is_empty() and rule.scene_id != scene_id:
			continue
		_rules.append(rule)
	_start_timers(project)


func shutdown() -> void:
	_dead = true
	_clear_timers()
	_rules = []


# --------------------------------------------------------------------------
# 事件入口
# --------------------------------------------------------------------------

func emit_event(kind: String, payload: Dictionary = {}) -> void:
	if _dead:
		return
	if _depth >= MAX_CASCADE_DEPTH:
		push_warning("规则连锁触发超过 %d 层，已中断。请检查是否存在循环规则。" % MAX_CASCADE_DEPTH)
		return

	_depth += 1
	for rule in _rules:
		if String(rule.trigger.get("type", "")) != kind:
			continue
		if not _trigger_matches(rule, kind, payload):
			continue
		_try_run(rule, kind, payload)
	_depth -= 1


## 事件本身带参数时，必须按参数过滤。
##
## 少了这一步：一条「按下 E 键就……」的规则会在按任何键时触发，
## 一条「金币被销毁时……」的规则会在任何东西消失时触发。
## 用户看到的是"这规则怎么乱触发"，而代码看起来一切正常 ——
## 和「相切不算相交」是同一类问题。
func _trigger_matches(rule: RuleDef, kind: String, payload: Dictionary) -> bool:
	match kind:
		"timer":
			return String(payload.get("rule_id", "")) == rule.id

		"key_press":
			var wanted := String(rule.trigger.get("key", ""))
			if wanted.is_empty():
				return true
			var pressed := String(payload.get("key", ""))
			# 既支持直接写键名（E、Space），也支持输入动作名（ui_accept）
			if pressed == wanted:
				return true
			return InputMap.has_action(wanted) and Input.is_action_pressed(wanted)

		"entity_created", "entity_destroyed":
			var actor: Variant = payload.get("actor")
			if actor == null:
				return true
			return _selector_hits(rule.trigger.get("target", ""), actor, {})

	return true


func _try_run(rule: RuleDef, kind: String, payload: Dictionary) -> void:
	var ctx := {"self": null, "other": null}

	if kind == "collision":
		if not _match_collision(rule, payload, ctx):
			return
	elif kind == "property_change":
		var actor: Variant = payload.get("actor")
		if actor == null or not _selector_hits(rule.trigger.get("target", ""), actor, ctx):
			return
		if String(rule.trigger.get("property", "")) != String(payload.get("property", "")):
			return
		ctx["self"] = actor
	elif kind == "key_press":
		var wanted := String(rule.trigger.get("key", ""))
		var pressed := String(payload.get("key", ""))
		if not wanted.is_empty() and wanted.to_lower() != pressed.to_lower():
			return
		ctx["self"] = payload.get("actor")
	else:
		ctx["self"] = payload.get("actor")

	if not _conditions_met(rule, ctx):
		return

	_run_actions(rule, ctx)


## 碰撞事件的配对：规则里写了 A 和 B 两个对象，
## 事件可能从任意一方发出，两种情况都要能匹配上。
## 匹配成功后把 self 固定为 A、other 固定为 B，
## 这样规则作者写「删除 other」时心里的对象是一致的。
func _match_collision(rule: RuleDef, payload: Dictionary, ctx: Dictionary) -> bool:
	var emitter: Variant = payload.get("self")
	var counterpart: Variant = payload.get("other")
	if emitter == null or counterpart == null:
		return false

	var side_a := _selector_hits(rule.trigger.get("a", ""), emitter, {})
	var side_b := _selector_hits(rule.trigger.get("b", ""), counterpart, {})
	if side_a and side_b:
		ctx["self"] = emitter
		ctx["other"] = counterpart
		return true

	var swapped_a := _selector_hits(rule.trigger.get("a", ""), counterpart, {})
	var swapped_b := _selector_hits(rule.trigger.get("b", ""), emitter, {})
	if swapped_a and swapped_b:
		ctx["self"] = counterpart
		ctx["other"] = emitter
		return true
	return false


# --------------------------------------------------------------------------
# 对象选择器
# --------------------------------------------------------------------------

func resolve(selector: String, ctx: Dictionary = {}) -> Array:
	var parsed := RuleVocabulary.parse_selector(selector)
	match parsed["kind"]:
		"self":
			var s: Variant = ctx.get("self")
			return [] if s == null else [s]
		"other":
			var o: Variant = ctx.get("other")
			return [] if o == null else [o]
		"tag":
			return runtime.actors_with_tag(parsed["value"])
		"instance":
			var hit: Variant = runtime.actor_by_instance(parsed["value"])
			return [] if hit == null else [hit]
	return []


func _selector_hits(selector: String, actor: Variant, ctx: Dictionary) -> bool:
	if actor == null:
		return false
	var parsed := RuleVocabulary.parse_selector(selector)
	match parsed["kind"]:
		"self":
			var s: Variant = ctx.get("self")
			return s == null or s == actor
		"other":
			var o: Variant = ctx.get("other")
			return o == null or o == actor
		"tag":
			return actor.tags.has(parsed["value"])
		"instance":
			return actor.instance_id == parsed["value"]
	return false


# --------------------------------------------------------------------------
# 条件
# --------------------------------------------------------------------------

func _conditions_met(rule: RuleDef, ctx: Dictionary) -> bool:
	for condition in rule.conditions:
		if not (condition is Dictionary):
			continue
		if not _condition_met(condition, ctx):
			return false
	return true


func _condition_met(condition: Dictionary, ctx: Dictionary) -> bool:
	var result := _evaluate_condition(condition, ctx)
	return not result if bool(condition.get("negate", false)) else result


func _evaluate_condition(condition: Dictionary, ctx: Dictionary) -> bool:
	var type := String(condition.get("type", ""))
	match type:
		"key_held":
			return _key_is_held(String(condition.get("key", "")))

		"grounded":
			for actor in resolve(String(condition.get("target", "self")), ctx):
				if actor.is_grounded():
					return true
			return false

		"compare":
			var prop := String(condition.get("property", ""))
			var op := String(condition.get("op", "=="))
			var value: Variant = condition.get("value", 0)
			for actor in resolve(String(condition.get("target", "self")), ctx):
				if _compare(actor.get_property(prop), op, value):
					return true
			return false

		"chance":
			var percent := float(condition.get("percent", 50.0))
			return randf() * 100.0 < percent

		"has_tag":
			var tag := String(condition.get("tag", ""))
			for actor in resolve(String(condition.get("target", "self")), ctx):
				if actor.tags.has(tag):
					return true
			return false

		"count":
			var n := resolve(String(condition.get("target", "")), ctx).size()
			return _compare(n, String(condition.get("op", "==")), condition.get("value", 0))

		"touching":
			var side_a := resolve(String(condition.get("a", "")), ctx)
			var side_b := resolve(String(condition.get("b", "")), ctx)
			for x in side_a:
				for y in side_b:
					if x != y and x.is_touching(y):
						return true
			return false

	push_warning("未知条件类型：%s" % type)
	return false


## 支持两种写法：输入动作名（如 ui_left，Godot 内置且可改键），
## 或直接写键名（如 A、Space）。前者更稳，后者更直观，两种都放行。
static func _key_is_held(key: String) -> bool:
	if key.is_empty():
		return false
	if InputMap.has_action(key) and Input.is_action_pressed(key):
		return true
	var code := OS.find_keycode_from_string(key)
	return code != KEY_NONE and Input.is_key_pressed(code)


static func _compare(lhs: Variant, op: String, rhs: Variant) -> bool:
	var numeric := _is_number(lhs) and _is_number(rhs)
	if numeric:
		var a := float(lhs)
		var b := float(rhs)
		match op:
			"==": return is_equal_approx(a, b)
			"!=": return not is_equal_approx(a, b)
			">": return a > b
			">=": return a >= b
			"<": return a < b
			"<=": return a <= b
	match op:
		"==": return lhs == rhs
		"!=": return lhs != rhs
	return false


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


# --------------------------------------------------------------------------
# 动作
# --------------------------------------------------------------------------

func _run_actions(rule: RuleDef, ctx: Dictionary) -> void:
	for action in rule.actions:
		if _dead:
			return
		if not (action is Dictionary):
			continue
		var type := String(action.get("type", ""))
		if type == "wait":
			await _wait(float(action.get("seconds", 0.0)))
			continue
		_apply_action(action, ctx)


func _wait(seconds: float) -> void:
	if seconds <= 0.0 or runtime == null or runtime.get_tree() == null:
		return
	await runtime.get_tree().create_timer(seconds).timeout


func _apply_action(action: Dictionary, ctx: Dictionary) -> void:
	var type := String(action.get("type", ""))

	match type:
		"set_property":
			for actor in resolve(String(action.get("target", "self")), ctx):
				actor.set_property(String(action.get("property", "")), action.get("value", 0))

		"change_property":
			for actor in resolve(String(action.get("target", "self")), ctx):
				actor.change_property(String(action.get("property", "")), float(action.get("delta", 0.0)))

		"move":
			var delta := Vector2(float(action.get("dx", 0.0)), float(action.get("dy", 0.0)))
			for actor in resolve(String(action.get("target", "self")), ctx):
				actor.position += delta

		"set_velocity":
			# 只填一个方向时另一个方向保持不变。
			# 这一点很关键：若把 vy 一并置 0，每帧执行的水平移动规则会顺手取消重力，
			# 角色会浮在空中。
			var has_vx := action.has("vx")
			var has_vy := action.has("vy")
			for actor in resolve(String(action.get("target", "self")), ctx):
				var v: Vector2 = actor.velocity
				if has_vx:
					v.x = float(action["vx"])
				if has_vy:
					v.y = float(action["vy"])
				actor.velocity = v

		"apply_impulse":
			var impulse := Vector2(float(action.get("vx", 0.0)), float(action.get("vy", 0.0)))
			for actor in resolve(String(action.get("target", "self")), ctx):
				actor.velocity += impulse

		"jump":
			for actor in resolve(String(action.get("target", "self")), ctx):
				actor.jump_with_height(float(action.get("height", 180.0)))

		"set_visible":
			var shown := bool(action.get("value", true))
			for actor in resolve(String(action.get("target", "self")), ctx):
				actor.visible = shown

		"spawn":
			var tag := String(action.get("tag", ""))
			runtime.spawn_actor(String(action.get("entity_id", "")),
				Vector2(float(action.get("x", 0.0)), float(action.get("y", 0.0))), tag)

		"destroy":
			# 先收集再执行：销毁会改动运行时对象列表，边遍历边删会漏掉目标。
			for actor in resolve(String(action.get("target", "other")), ctx).duplicate():
				runtime.destroy_actor(actor)

		"switch_scene":
			runtime.start(String(action.get("scene_id", "")))

		"end_game":
			runtime.end_game(String(action.get("result", "win")), String(action.get("message", "")))

		_:
			push_warning("未知动作类型：%s" % type)


# --------------------------------------------------------------------------
# 定时器事件
# --------------------------------------------------------------------------

func _start_timers(project: GameProject) -> void:
	for rule in _rules:
		if String(rule.trigger.get("type", "")) != "timer":
			continue
		var interval := float(rule.trigger.get("interval", 1.0))
		var repeat := bool(rule.trigger.get("repeat", true))
		var delay := float(rule.trigger.get("delay", 0.0))

		var timer := Timer.new()
		timer.wait_time = maxf(interval, 0.01)
		timer.one_shot = not repeat
		timer.autostart = false
		var rule_id := rule.id
		timer.timeout.connect(func() -> void: emit_event("timer", {"rule_id": rule_id}))
		runtime.add_child(timer)
		timer.start(maxf(delay, 0.001) if delay > 0.0 else maxf(interval, 0.01))
		_timers.append(timer)


func _clear_timers() -> void:
	for timer in _timers:
		if is_instance_valid(timer):
			timer.stop()
			timer.queue_free()
	_timers.clear()


func rule_count() -> int:
	return _rules.size()
