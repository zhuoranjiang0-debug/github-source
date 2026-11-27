## 离线生成器：不联网、不花钱，同一个问题永远给同一个答案。
##
## 它干的事说白了是"认句子里的关键词，然后照着模板拼一份草稿"。
## 它不聪明——只认几种说法，认不出来会老实说认不出来。
## 但它永远不会给你一份用不了的东西，也永远不因为没网而罢工。
##
## 答辩现场断网时，顶在最前面的就是它；联网时真模型接在同一个接口后面
## （见 AIService），两者对上层来说没有区别。
class_name OfflineProvider
extends RefCounted

## 颜色词 → 占位色。命中哪个用哪个；一个都没命中就按提示词挑一个固定的
const COLOR_WORDS := {
	"红": "#f87171",
	"橙": "#fb923c",
	"黄": "#fbbf24",
	"绿": "#4ade80",
	"青": "#22d3ee",
	"蓝": "#60a5fa",
	"紫": "#c084fc",
	"粉": "#f472b6",
	"黑": "#475569",
	"白": "#e2e8f0",
}
## 没写颜色时按这个顺序挑，保证同一个提示词每次得到同一个颜色
const FALLBACK_COLORS := ["#c084fc", "#60a5fa", "#f472b6", "#fb923c", "#4ade80"]

## 大小词 → 碰撞体缩放
const SIZE_WORDS := {
	"巨大": 2.0,
	"大": 1.5,
	"小": 0.75,
	"迷你": 0.5,
}

## 认得出"这是个敌人"的词
const ENEMY_WORDS := ["敌人", "敌", "怪", "boss", "BOSS", "守卫", "危险", "障碍", "刺"]
## 认得出"让天上掉金币"的词
const RAIN_WORDS := ["金币雨", "掉金币", "掉钱", "下金币", "天上", "掉落", "生成金币", "刷金币"]

const DEFAULT_ENEMY_COLOR := "#c084fc"


## 唯一的入口：一句人话 + 当前的工程 → 一份草稿。
##
## 要传 project 进来，是因为它得先看看工程里已经有什么：
## 能复用的规则就复用（比如工程里已经有"碰到危险物扣血"，
## 新敌人才不用再配一条一模一样的）。
func draft(prompt: String, project: GameProject) -> AIDraft:
	var text := prompt.strip_edges()
	if text.is_empty():
		return AIDraft.failure("还没写想要什么。\n\n试试这两句：\n· 一个会飞的紫色小怪\n· 每 2 秒掉一个金币")

	if _looks_like_coin_rain(text):
		return _coin_rain_draft(text, project)
	if _matches(text, ENEMY_WORDS) or _matches_any_color(text) or _matches_any_size(text):
		return _enemy_draft(text, project)

	return AIDraft.failure(
		"「%s」这句我没听懂。\n\n我现在会做两件事：\n· 生成一个敌人 —— 试试「一个会飞的紫色小怪」\n· 让天上定期掉金币 —— 试试「每 2 秒掉一个金币」" % text)


# --------------------------------------------------------------------------
# 一、生成一个敌人
# --------------------------------------------------------------------------

func _enemy_draft(text: String, project: GameProject) -> AIDraft:
	var draft := AIDraft.new()
	var pick := _enemy_pick(text)

	draft.title = pick["name"]
	var entity := _enemy_entity(pick, project)
	draft.entities.append(entity)

	# 摆到当前关卡里，用户才看得见。飞行怪摆在空中，地面上的摆在玩家右边。
	var spot := _grab_spot(project, bool(pick["fly"]))
	draft.placements.append({"entity_id": String(entity["id"]), "x": spot.x, "y": spot.y})
	draft.steps.append("新建一种对象「%s」（%s）" % [pick["name"], pick["size_label"]])
	draft.steps.append("在当前关卡里摆一个，位置：%d, %d" % [int(spot.x), int(spot.y)])

	# 危险物要能扣血。工程里已经有"碰到危险物"的规则就直接复用 ——
	# 这是"AI 先看一眼你的工程"最实在的一个例子，也省得规则清单里
	# 出现两条一模一样的规则。
	var reuse := _find_hazard_rule(project)
	if reuse.is_empty():
		draft.rules.append(_hazard_rule(project, draft.title))
		draft.steps.append("加一条规则：小恐龙碰到它就掉 1 点血，并被弹开")
	else:
		draft.steps.append("不会再加规则：工程里已经有「%s」，它会自动管到新敌人" % reuse)

	if bool(pick["fly"]):
		draft.steps.append("它是会动的（飘着、不往下掉）：配一条「设置速度」的规则就能让它飞")
	return draft


## 按提示词决定：叫什么、什么颜色、多大、会不会飞
func _enemy_pick(text: String) -> Dictionary:
	var color_hex := _pick_color(text)
	var color_name := _color_name(text)
	var size_mult := _pick_size(text)
	var fly := _matches(text, ["飞", "飘", "浮", "空中", "悬"])
	var is_round := fly or _matches(text, ["圆", "球", "浮"])

	var parts: PackedStringArray = PackedStringArray()
	if not color_name.is_empty():
		parts.append(color_name)
	if fly:
		parts.append("飞行")
	parts.append("小怪" if _matches(text, ["小怪", "怪"]) else "敌人")
	var enemy_name := "".join(parts)

	var size_label := "普通大小"
	if size_mult >= 2.0:
		size_label = "很大"
	elif size_mult > 1.0:
		size_label = "偏大"
	elif size_mult <= 0.5:
		size_label = "很小"
	elif size_mult < 1.0:
		size_label = "偏小"

	return {
		"name": enemy_name,
		"color": color_hex,
		"size": size_mult,
		"size_label": size_label,
		"fly": fly,
		"shape": EntityDef.SHAPE_CIRCLE if is_round else EntityDef.SHAPE_RECT,
	}


## 拼一份实体定义。形状和尖刺那种"危险物"对齐：
## 用 static + 打开碰撞，玩家碰到才有反应。
func _enemy_entity(pick: Dictionary, project: GameProject) -> Dictionary:
	var size := float(pick["size"])
	var base := 48.0
	# 会飞的怪默认就是"会动、不往下掉"：用户拿到它之后想让它动，
	# 只要配一条"设置速度"的规则就行。第一版给的一律是"静止"，
	# 结果用户配了速度却纹丝不动 —— 静止对象不参与物理步进。
	var fly := bool(pick["fly"])
	return {
		"id": _unique_id(project, "ent_ai_enemy"),
		"name": String(pick["name"]),
		"asset_id": "",
		# hazard 这个标签是"危险物"的约定：工程里已有的
		# 「碰到危险物就扣血」规则就是按它来找目标的
		"tags": ["hazard"],
		"color": String(pick["color"]),
		"collider": {
			"shape": String(pick["shape"]),
			"width": base * size,
			"height": base * size,
			"radius": base * size * 0.46,
			"offset_x": 0,
			"offset_y": 0,
		},
		"physics": {
			"mode": EntityDef.PHYSICS_KINEMATIC if fly else EntityDef.PHYSICS_STATIC,
			"gravity_scale": 0.0,
			"bounce": 0.0,
			"friction": 0.6,
		},
		"animations": {},
		"default_animation": "",
		# 刻意不给它 hp：现在没有任何规则会让敌人受伤，
		# 写一个没人读的数值，和之前删掉的「播放动画」是同一种毛病 ——
		# 看起来有、实际什么也不影响，只会让后面接手的人白猜半天。
		"initial_properties": {},
	}


## 和示例里那条「碰到尖刺扣血」同款：扣 1 点血，弹开一下
func _hazard_rule(project: GameProject, enemy_name: String) -> Dictionary:
	return {
		"id": _unique_id(project, "rule_ai_hazard"),
		"name": "碰到%s扣血" % enemy_name,
		"enabled": true,
		"scene_id": "",
		"trigger": {"type": "collision", "a": "tag:player", "b": "tag:hazard"},
		"conditions": [],
		"actions": [
			{"type": "change_property", "target": "tag:player", "property": "hp", "delta": -1},
			{"type": "apply_impulse", "target": "tag:player", "vx": 0, "vy": -450},
		],
	}


## 工程里有没有现成的"碰到危险物就扣血"规则。有就不重复造一条，
## 免得规则清单里出现两条一模一样的规则、用户还得猜哪条在生效。
func _find_hazard_rule(project: GameProject) -> String:
	if project == null:
		return ""
	for rule in project.rules:
		var trigger: Dictionary = rule.trigger
		for key in ["a", "b"]:
			if String(trigger.get(key, "")) == "tag:hazard":
				return rule.name
	return ""


# --------------------------------------------------------------------------
# 二、让天上定期掉金币
# --------------------------------------------------------------------------

## 这句是在说"让天上掉金币"吗。
##
## 光靠词表不够用："掉金币"和"掉一个金币"差着两个字，
## 而中文里"一枚金币从天上落下来"这种说法有的是。
## 所以先查词表，再退回"同时提到金币和掉落"这个组合判断。
func _looks_like_coin_rain(text: String) -> bool:
	if _matches(text, RAIN_WORDS):
		return true
	var has_coin := text.find("金币") >= 0 or text.find("钱") >= 0
	var has_falling := _matches(text, ["掉", "落", "下", "雨", "生成", "刷", "来"])
	return has_coin and has_falling


func _coin_rain_draft(text: String, project: GameProject) -> AIDraft:
	var coin_id := _find_entity_with_tag(project, "coin")
	if coin_id.is_empty():
		return AIDraft.failure(
			"这个工程里还没有「金币」这种东西，所以我没法让天上掉它。\n\n先去底部素材栏拖一个金币到画布上，再回来让我做。")

	var seconds := _pick_seconds(text)
	var canvas_width := 1280.0
	var canvas_height := 720.0
	if project != null and project.config != null:
		canvas_width = float(project.config.canvas_width)
		canvas_height = float(project.config.canvas_height)

	var draft := AIDraft.new()
	draft.title = "天上掉金币"

	# 会掉下来的金币得**单独做成一种对象**，不能直接生成工程里那个金币。
	#
	# 原因是示例里的金币为了不挡住玩家，物理类型是 none、也不受重力 ——
	# 直接生成它，它会停在半空中一动不动。第一版就是这么干的，
	# 用户在平板上一点就看出来了："位置在屏幕外，而且不会往下掉"。
	# 复制一个长得一样、但受重力的版本出来，它才会真的掉下来。
	var falling := _falling_coin_entity(project, coin_id)
	draft.entities.append(falling)

	draft.rules.append({
		"id": _unique_id(project, "rule_ai_coin"),
		"name": "每隔 %s 秒掉一个金币" % _trim_number(seconds),
		"enabled": true,
		"scene_id": "",
		"trigger": {"type": "timer", "interval": seconds, "repeat": true, "delay": seconds},
		"conditions": [],
		"actions": [{
			"type": "spawn",
			"entity_id": String(falling["id"]),
			"x": roundi(canvas_width * 0.5),
			"y": -60,
			# 标签不用另外加：复制出来的金币本来就带着 coin 标签，
			# 工程里那条「吃到金币加分」自动就管得到它
			"tag": "",
		}],
	})
	draft.steps.append("新建一种对象「%s」（和金币长得一样，但会往下掉）" % String(falling["name"]))
	draft.steps.append("加一条规则：每隔 %s 秒，从画面正中的上方掉一个金币" % _trim_number(seconds))
	draft.steps.append("掉下来的金币会落在地面上停住，走过去就能捡到")
	draft.steps.append("想掉得快点或慢点：在「逻辑」里改那条规则的「间隔」")
	return draft


## 复制一份"会掉的金币"：长得和原金币一样，但受重力、会落在地面上。
##
## 为什么复制而不是改原金币：原金币是地面上的静态拾取物，
## 一旦给它加上重力，示例里摆好的那些金币会当场全部掉下去 ——
## AI 帮忙改东西，不该顺手把用户已经摆好的关卡改掉。
func _falling_coin_entity(project: GameProject, coin_id: String) -> Dictionary:
	var base := project.find_entity(coin_id) if project != null else null
	var data: Dictionary = base.to_dict() if base != null else {}
	data["id"] = _unique_id(project, "ent_ai_coin")
	data["name"] = "掉落的金币"
	data["physics"] = {
		"mode": EntityDef.PHYSICS_KINEMATIC,
		"gravity_scale": 1.0,
		"bounce": 0.0,
		"friction": 0.6,
	}
	# 拾取物：只和地面碰。否则金币会互相踩着往上堆，堆成一根柱子 ——
	# 用户看到那张截图之后说的原话是"金币应该可以和金币重叠"。
	data["collision_group"] = EntityDef.COLLISION_PICKUP
	return data


## 提示词里的秒数（"每 2 秒""每1.5秒""3 秒一次"），没有就用 2 秒
func _pick_seconds(text: String) -> float:
	var digits := ""
	var seen_dot := false
	for i in text.length():
		var ch := text.substr(i, 1)
		if ch >= "0" and ch <= "9":
			digits += ch
		elif ch == "." and not digits.is_empty() and not seen_dot:
			digits += ch
			seen_dot = true
		elif not digits.is_empty():
			break
	if digits.is_empty():
		return 2.0
	var value := float(digits)
	return value if value > 0.05 else 2.0


static func _trim_number(value: float) -> String:
	return RuleVocabulary.format_number(value)


# --------------------------------------------------------------------------
# 小工具
# --------------------------------------------------------------------------

func _matches(text: String, words: Array) -> bool:
	for word in words:
		if text.find(String(word)) >= 0:
			return true
	return false


func _matches_any_color(text: String) -> bool:
	for word in COLOR_WORDS:
		if text.find(String(word)) >= 0:
			return true
	return false


func _matches_any_size(text: String) -> bool:
	return _matches(text, SIZE_WORDS.keys())


## 提示词里写了颜色就用它，没写就按提示词挑一个固定颜色 ——
## 同一个提示词每次都得到同一个颜色，演示时不会"每次都不一样"。
func _pick_color(text: String) -> String:
	for word in COLOR_WORDS:
		if text.find(String(word)) >= 0:
			return String(COLOR_WORDS[word])
	var seed_value: int = text.hash()
	var index: int = absi(seed_value) % FALLBACK_COLORS.size()
	return String(FALLBACK_COLORS[index])


## 颜色词本身（"紫" → "紫色"），用来拼名字
func _color_name(text: String) -> String:
	for word in COLOR_WORDS:
		if text.find(String(word)) >= 0:
			var name := String(word)
			return name if name.length() > 1 else name + "色"
	return ""


func _pick_size(text: String) -> float:
	# "小怪"里的"小"是名字的一部分，不是尺寸 —— 不先摘掉的话，
	# 用户说"一个紫色小怪"会得到一只缩小到 0.75 倍的怪物，
	# 而他并没有说过要小号的。
	var cleaned := text.replace("小怪", "怪")
	for word in SIZE_WORDS:
		if cleaned.find(String(word)) >= 0:
			return float(SIZE_WORDS[word])
	return 1.0


## 新生成的对象摆在哪儿：飞行怪摆在玩家头顶侧上方，地面上的摆在玩家右边。
## 都放在看得见的地方 —— 生成完什么都看不到，用户会以为没生效。
func _grab_spot(project: GameProject, fly: bool) -> Vector2:
	var player := _player_instance_position(project)
	if player == Vector2.ZERO:
		return Vector2(700.0, 260.0) if fly else Vector2(700.0, 620.0)
	return Vector2(player.x + 220.0, player.y - 150.0) if fly else Vector2(player.x + 220.0, player.y)


func _player_instance_position(project: GameProject) -> Vector2:
	if project == null or project.scenes.is_empty():
		return Vector2.ZERO
	for scene in project.scenes:
		for placed in scene.instances:
			var def := project.find_entity(placed.entity_id)
			if def != null and def.has_tag("player"):
				return Vector2(placed.x, placed.y)
	return Vector2.ZERO


## 找一个带某个标签的实体类型，用来做"掉金币"这类对象引用
func _find_entity_with_tag(project: GameProject, tag: String) -> String:
	if project == null:
		return ""
	for def in project.entities:
		if def.has_tag(tag):
			return def.id
	return ""


## 造一个工程里还没有的 id。
##
## 故意用"数数"而不是随机数：同一份工程上跑两次，结果应该一模一样 ——
## 演示时"每次都不一样"会让人怀疑这东西到底稳不稳。
func _unique_id(project: GameProject, prefix: String) -> String:
	var used := {}
	if project != null:
		for def in project.entities:
			used[def.id] = true
		for rule in project.rules:
			used[rule.id] = true
	if not used.has(prefix):
		return prefix
	var n := 2
	while used.has("%s%d" % [prefix, n]):
		n += 1
	return "%s%d" % [prefix, n]
