## 工程文件的语义校验。
##
## 除了结构是否合法，更重要的是**引用完整性**：实体引用的素材是否存在、
## 场景引用的实体是否存在、规则引用的场景是否存在。
## 这些错误在运行期往往表现为「什么都没发生」，极难排查，必须在编辑期就拦住。
class_name ProjectValidator
extends RefCounted

const LEVEL_ERROR := "error"
const LEVEL_WARNING := "warning"


class Issue:
	extends RefCounted
	var level: String
	var code: String
	var message: String
	var path: String

	func _init(p_level: String, p_code: String, p_message: String, p_path: String = "") -> void:
		level = p_level
		code = p_code
		message = p_message
		path = p_path

	## 注意：不能命名为 to_string()，那会覆盖 Object 的原生方法并触发编译错误。
	func describe() -> String:
		var tag := "[错误]" if level == LEVEL_ERROR else "[警告]"
		return "%s %s %s" % [tag, code, message] if path.is_empty() else "%s %s %s (%s)" % [tag, code, message, path]


static func validate(project: GameProject) -> Array[Issue]:
	var issues: Array[Issue] = []

	_check_schema_version(project, issues)
	_check_duplicate_ids(project, issues)
	_check_start_scene(project, issues)
	_check_assets(project, issues)
	_check_entities(project, issues)
	_check_scenes(project, issues)
	_check_rules(project, issues)
	_check_selector_tags(project, issues)
	_check_selector_reachability(project, issues)
	_check_pickup_landing(project, issues)
	_check_touch_controls(project, issues)

	return issues


## 一个工程要是没有任何屏幕按键，它在手机上就没法操作 ——
## 只能靠键盘，而手机没有键盘。
##
## 这是提醒不是错误：可能这个人做的就是电脑上的原型。
## 工具该做的是把话说清楚，而不是替他决定要放几个按键。
static func _check_touch_controls(project: GameProject, issues: Array[Issue]) -> void:
	var has_button := false
	var has_button_rule := false
	for e in project.entities:
		if e.is_button():
			has_button = true
	for r in project.rules:
		var kind := String(r.trigger.get("type", ""))
		if kind == "tap":
			has_button_rule = true
	if has_button or has_button_rule:
		return
	issues.append(Issue.new(LEVEL_WARNING, "project.no_touch_controls",
		"这个工程没有任何屏幕按键，也没有用触屏相关的事件，在手机上会没法操作", "entities"))


## 只关心会阻止正常运行的问题
static func has_errors(issues: Array[Issue]) -> bool:
	for i in issues:
		if i.level == LEVEL_ERROR:
			return true
	return false


static func format_all(issues: Array[Issue]) -> String:
	if issues.is_empty():
		return "校验通过，未发现问题。"
	var lines: Array[String] = []
	for i in issues:
		lines.append(i.describe())
	return "\n".join(lines)


# --------------------------------------------------------------------------
# 各项检查
# --------------------------------------------------------------------------

static func _check_schema_version(project: GameProject, issues: Array[Issue]) -> void:
	if project.schema_version != GameProject.SCHEMA_VERSION:
		issues.append(Issue.new(LEVEL_WARNING, "schema.version",
			"工程文件版本为 %s，当前程序支持 %s，可能存在兼容问题"
			% [project.schema_version, GameProject.SCHEMA_VERSION]))


static func _check_duplicate_ids(project: GameProject, issues: Array[Issue]) -> void:
	_report_duplicates(project.assets.map(func(a: AssetDef) -> String: return a.id), "素材", "assets", issues)
	_report_duplicates(project.entities.map(func(e: EntityDef) -> String: return e.id), "实体", "entities", issues)
	_report_duplicates(project.scenes.map(func(s: SceneDef) -> String: return s.id), "场景", "scenes", issues)
	_report_duplicates(project.rules.map(func(r: RuleDef) -> String: return r.id), "规则", "rules", issues)
	for scene in project.scenes:
		_report_duplicates(
			scene.instances.map(func(p: PlacedEntity) -> String: return p.instance_id),
			"场景「%s」中的实例" % scene.name, "scenes/%s/instances" % scene.id, issues)


static func _report_duplicates(ids: Array, what: String, path: String, issues: Array[Issue]) -> void:
	var seen := {}
	for id in ids:
		var s := String(id)
		if s.is_empty():
			issues.append(Issue.new(LEVEL_ERROR, "id.empty", "%s存在空 ID" % what, path))
			continue
		if seen.has(s):
			issues.append(Issue.new(LEVEL_ERROR, "id.duplicate", "%s中存在重复 ID：%s" % [what, s], path))
		seen[s] = true


static func _check_start_scene(project: GameProject, issues: Array[Issue]) -> void:
	if project.scenes.is_empty():
		issues.append(Issue.new(LEVEL_ERROR, "scene.empty", "工程里没有任何场景，无法运行", "scenes"))
		return
	if not project.config.start_scene_id.is_empty() and project.find_scene(project.config.start_scene_id) == null:
		issues.append(Issue.new(LEVEL_ERROR, "scene.start_missing",
			"起始场景 %s 不存在" % project.config.start_scene_id, "config/start_scene_id"))


static func _check_assets(project: GameProject, issues: Array[Issue]) -> void:
	for a in project.assets:
		var path := "assets/%s" % a.id
		if not AssetDef.VALID_TYPES.has(a.type):
			issues.append(Issue.new(LEVEL_ERROR, "asset.type",
				"素材「%s」的类型 %s 不受支持" % [a.name, a.type], path))
		if not AssetDef.VALID_SOURCES.has(a.source):
			issues.append(Issue.new(LEVEL_WARNING, "asset.source",
				"素材「%s」的来源 %s 不是标准取值" % [a.name, a.source], path))
		if a.path.is_empty():
			issues.append(Issue.new(LEVEL_WARNING, "asset.path_empty",
				"素材「%s」没有关联文件，运行时将使用占位图形" % a.name, path))
		elif not FileAccess.file_exists(a.path) and not a.path.begins_with("res://") and not a.path.begins_with("user://"):
			issues.append(Issue.new(LEVEL_WARNING, "asset.file_missing",
				"素材「%s」的文件不存在：%s" % [a.name, a.path], path))


static func _check_entities(project: GameProject, issues: Array[Issue]) -> void:
	for e in project.entities:
		var path := "entities/%s" % e.id
		if not e.asset_id.is_empty() and project.find_asset(e.asset_id) == null:
			issues.append(Issue.new(LEVEL_ERROR, "entity.asset_missing",
				"实体「%s」引用了不存在的素材 %s" % [e.name, e.asset_id], path))
		if not EntityDef.VALID_SHAPES.has(e.collider_shape):
			issues.append(Issue.new(LEVEL_ERROR, "entity.collider_shape",
				"实体「%s」的碰撞形状 %s 不受支持" % [e.name, e.collider_shape], path))
		if not EntityDef.VALID_PHYSICS.has(e.physics_mode):
			issues.append(Issue.new(LEVEL_ERROR, "entity.physics_mode",
				"实体「%s」的物理类型 %s 不受支持" % [e.name, e.physics_mode], path))
		# 有碰撞体但物理类型为 none 是合法且常见的用法：它相当于一个触发区，
		# 不阻挡任何东西，只用来产生碰撞事件（金币、拾取物、检查点都是这样）。
		# 屏幕按键不需要标签 —— 规则不会去选中一个按键
		if e.tags.is_empty() and not e.is_button():
			issues.append(Issue.new(LEVEL_WARNING, "entity.no_tags",
				"实体「%s」没有任何标签，规则将无法用「tag:」选中它" % e.name, path))
		for anim_name in e.animations:
			var anim: Variant = e.animations[anim_name]
			if not (anim is Dictionary):
				issues.append(Issue.new(LEVEL_ERROR, "entity.animation_malformed",
					"实体「%s」的动画「%s」格式不正确" % [e.name, anim_name], path))
		if not e.default_animation.is_empty() and not e.animations.has(e.default_animation):
			issues.append(Issue.new(LEVEL_WARNING, "entity.animation_missing",
				"实体「%s」的默认动画「%s」未定义" % [e.name, e.default_animation], path))


static func _check_scenes(project: GameProject, issues: Array[Issue]) -> void:
	for s in project.scenes:
		var base := "scenes/%s" % s.id
		if not s.background_asset_id.is_empty() and project.find_asset(s.background_asset_id) == null:
			issues.append(Issue.new(LEVEL_ERROR, "scene.background_missing",
				"场景「%s」引用了不存在的背景素材 %s" % [s.name, s.background_asset_id], base))
		if not s.tilemap_asset_id.is_empty() and project.find_asset(s.tilemap_asset_id) == null:
			issues.append(Issue.new(LEVEL_ERROR, "scene.tilemap_missing",
				"场景「%s」引用了不存在的地块素材 %s" % [s.name, s.tilemap_asset_id], base))
		if s.camera_mode == SceneDef.CAMERA_FOLLOW and s.camera_target.is_empty():
			issues.append(Issue.new(LEVEL_ERROR, "scene.camera_target_missing",
				"场景「%s」的相机设置为跟随，但没有指定跟随对象" % s.name, base))
		if s.instances.is_empty():
			issues.append(Issue.new(LEVEL_WARNING, "scene.no_instances",
				"场景「%s」里没有摆放任何对象" % s.name, base))
		for p in s.instances:
			if project.find_entity(p.entity_id) == null:
				issues.append(Issue.new(LEVEL_ERROR, "instance.entity_missing",
					"场景「%s」中的实例 %s 引用了不存在的实体 %s"
					% [s.name, p.instance_id, p.entity_id], "%s/instances/%s" % [base, p.instance_id]))


static func _check_rules(project: GameProject, issues: Array[Issue]) -> void:
	for r in project.rules:
		var base := "rules/%s" % r.id
		var label := r.name if not r.name.is_empty() else r.id
		if not r.scene_id.is_empty() and project.find_scene(r.scene_id) == null:
			issues.append(Issue.new(LEVEL_ERROR, "rule.scene_missing",
				"规则「%s」指定了不存在的场景 %s" % [label, r.scene_id], base))

		var ttype := String(r.trigger.get("type", ""))
		if ttype.is_empty():
			issues.append(Issue.new(LEVEL_ERROR, "rule.trigger_empty",
				"规则「%s」没有设置事件" % label, base))
		elif not RuleVocabulary.TRIGGERS.has(ttype):
			issues.append(Issue.new(LEVEL_ERROR, "rule.trigger_unknown",
				"规则「%s」使用了未知事件 %s" % [label, ttype], base))
		else:
			_check_params(r.trigger, RuleVocabulary.trigger_def(ttype), "规则「%s」的事件" % label, base, issues)

		for idx in r.conditions.size():
			var c: Variant = r.conditions[idx]
			if not (c is Dictionary):
				continue
			var ctype := String(c.get("type", ""))
			if not RuleVocabulary.CONDITIONS.has(ctype):
				issues.append(Issue.new(LEVEL_ERROR, "rule.condition_unknown",
					"规则「%s」的第 %d 个条件使用了未知类型 %s" % [label, idx + 1, ctype], base))
			else:
				_check_params(c, RuleVocabulary.condition_def(ctype),
					"规则「%s」的第 %d 个条件" % [label, idx + 1], base, issues)

		if r.actions.is_empty():
			issues.append(Issue.new(LEVEL_WARNING, "rule.no_actions",
				"规则「%s」没有配置任何动作，它不会产生效果" % label, base))
		for idx in r.actions.size():
			var a: Variant = r.actions[idx]
			if not (a is Dictionary):
				continue
			var atype := String(a.get("type", ""))
			if not RuleVocabulary.ACTIONS.has(atype):
				issues.append(Issue.new(LEVEL_ERROR, "rule.action_unknown",
					"规则「%s」的第 %d 个动作使用了未知类型 %s" % [label, idx + 1, atype], base))
			else:
				_check_params(a, RuleVocabulary.action_def(atype),
					"规则「%s」的第 %d 个动作" % [label, idx + 1], base, issues)


static func _check_params(stmt: Dictionary, def: Dictionary, where: String, path: String, issues: Array[Issue]) -> void:
	var params: Dictionary = def.get("params", {})
	for key in params:
		var required: bool = params[key].get("required", true)
		if required and not stmt.has(key):
			issues.append(Issue.new(LEVEL_ERROR, "rule.param_missing",
				"%s 缺少参数「%s」" % [where, RuleVocabulary.param_label(def, key)], path))


## 用了「自身」或「对方」，但那个事件根本给不出来 —— 规则会静静地什么都不做。
##
## 这是用户报出来的："我看不出来「自身」指的是哪个对象"。查下去发现：
## 在「每一帧」「点击屏幕」这类事件里，引擎没有触发对象，`self` 解析出来是空，
## 动作就一声不吭地跳过了。界面已经不再列这些选项，这里再兜一道 ——
## 手改 JSON 的、以及以前存下来的工程，也躲不过。
static func _check_selector_reachability(project: GameProject, issues: Array[Issue]) -> void:
	for r in project.rules:
		var trigger_type := String(r.trigger.get("type", ""))
		var trigger_label := RuleVocabulary.trigger_label(trigger_type)
		var rule_label := r.name if not r.name.is_empty() else r.id
		# 事件自己的参数是拿来"匹配"的，那时候还没有自身/对方可言
		_check_statement_selectors(r.trigger, RuleVocabulary.trigger_def(trigger_type),
			"规则「%s」的事件" % rule_label, trigger_label, false, false,
			"rules/%s/trigger" % r.id, issues)
		for i in r.conditions.size():
			var c: Variant = r.conditions[i]
			if not (c is Dictionary):
				continue
			var ctype := String((c as Dictionary).get("type", ""))
			_check_statement_selectors(c, RuleVocabulary.condition_def(ctype),
				"规则「%s」的第 %d 个条件" % [rule_label, i + 1], trigger_label,
				RuleVocabulary.trigger_provides_actor(trigger_type),
				RuleVocabulary.trigger_provides_other(trigger_type),
				"rules/%s/conditions/%d" % [r.id, i], issues)
		for i in r.actions.size():
			var a: Variant = r.actions[i]
			if not (a is Dictionary):
				continue
			var atype := String((a as Dictionary).get("type", ""))
			_check_statement_selectors(a, RuleVocabulary.action_def(atype),
				"规则「%s」的第 %d 个动作" % [rule_label, i + 1], trigger_label,
				RuleVocabulary.trigger_provides_actor(trigger_type),
				RuleVocabulary.trigger_provides_other(trigger_type),
				"rules/%s/actions/%d" % [r.id, i], issues)


static func _check_statement_selectors(statement: Dictionary, def: Dictionary, where: String,
		trigger_label: String, allow_self: bool, allow_other: bool,
		path: String, issues: Array[Issue]) -> void:
	for key in def.get("params", {}):
		var spec: Dictionary = def["params"][key]
		if String(spec.get("type", "")) != "selector":
			continue
		var value := String(statement.get(key, spec.get("default", "")))
		if value == RuleVocabulary.SELECTOR_SELF and not allow_self:
			issues.append(Issue.new(LEVEL_WARNING, "rule.self_unreachable",
				"%s 里的「自身」指不到对象：事件是「%s」，它不会给出触发对象，所以这条规则不会生效。请改成按标签选（列表里「所有「…」」那几项），或者选「就这一个对象」" % [where, trigger_label], path))
		elif value == RuleVocabulary.SELECTOR_OTHER and not allow_other:
			issues.append(Issue.new(LEVEL_WARNING, "rule.other_unreachable",
				"%s 里的「对方」只有碰撞事件才有：这条规则的事件是「%s」，它没有「另一方」" % [where, trigger_label], path))


## 有拾取物，但整个工程里没有"地面"类对象 —— 掉落物会穿过一切掉出画面。
##
## 用户定的规则是"金币只和地面碰撞"（尖刺、静止的怪都不碰）。
## 代价是：工程里要是**没有任何**"地面"类对象，掉下来的金币就会穿过一切
## 直接掉出画面 —— 而且一声不吭。这类静默失败必须在编辑期提醒。
static func _check_pickup_landing(project: GameProject, issues: Array[Issue]) -> void:
	var pickups: Array[String] = []
	for e in project.entities:
		if e.is_pickup():
			pickups.append(e.name if not e.name.is_empty() else e.id)
	if pickups.is_empty():
		return

	# 有没有东西接得住掉落物，要按**实例**算：类型上是"地面"，用户也可能
	# 把某一块改成了"普通障碍"（属性面板里现在就能改）。
	var has_ground := false
	for scene in project.scenes:
		for placed in scene.instances:
			var def := project.find_entity(placed.entity_id)
			if PlacedEntity.resolve_collision_group(def, placed) == EntityDef.COLLISION_GROUND:
				has_ground = true
	if has_ground:
		return
	issues.append(Issue.new(LEVEL_WARNING, "project.no_ground",
		"工程里有拾取物（%s），但场景里没有任何「地面」：掉下来的东西会穿过一切掉出画面。选中接住它的那个对象，在「碰撞」里改成「地面」" % "、".join(pickups),
		"entities"))


static func _check_selector_tags(project: GameProject, issues: Array[Issue]) -> void:
	var known_tags := {}
	for e in project.entities:
		for t in e.tags:
			known_tags[t] = true

	var used: Array[String] = []
	for r in project.rules:
		_collect_selectors(r.trigger, used)
		for c in r.conditions:
			if c is Dictionary:
				_collect_selectors(c, used)
		for a in r.actions:
			if a is Dictionary:
				_collect_selectors(a, used)

	var reported := {}
	for sel in used:
		var parsed := RuleVocabulary.parse_selector(sel)
		if parsed["kind"] != "tag":
			continue
		var tag: String = parsed["value"]
		if known_tags.has(tag) or reported.has(tag):
			continue
		reported[tag] = true
		issues.append(Issue.new(LEVEL_WARNING, "rule.tag_unknown",
			"规则里用到了标签「%s」，但没有任何实体带这个标签，该规则永远不会触发" % tag, "rules"))


static func _collect_selectors(stmt: Dictionary, out: Array[String]) -> void:
	for key in ["target", "a", "b"]:
		if stmt.has(key):
			out.append(String(stmt[key]))
