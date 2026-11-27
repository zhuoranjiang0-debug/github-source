## 可视化逻辑的「词汇表」。
##
## 这是本项目最关键的设计之一：事件、条件、动作三种语句的类型与参数
## 全部以数据形式声明在这里。编辑器的逻辑面板直接读取本表自动生成表单，
## 运行器的规则引擎也以本表为白名单。新增一种动作只需在这里加一条，
## 不需要改任何界面代码。
##
## 参数类型（param "type"）取值：
##   string / number / int / bool / color  —— 基础控件
##   selector  —— 对象选择器，编辑器渲染成标签下拉框
##   property  —— 属性名，编辑器按选择器推断可选属性
##   enum      —— 固定选项，需提供 options
##   entity    —— 实体定义 ID
##   asset     —— 素材 ID
##   scene     —— 场景 ID
##   animation —— 动画名
##
## 另外，**任何条件都可以加 "negate": true 表示取反**，
## 编辑器把它渲染成一个「反向」勾选框，句子也要跟着念成「没有…」——
## 否则界面上写着"正按住左、正按住右"，实际执行的是"两个都没按住"，
## 这种"看着相反"的规则比看不懂更糟。有了它，用户不必再为
## 「没有按住任何方向键」这类说法去找专门的语句类型。
class_name RuleVocabulary
extends RefCounted

# --------------------------------------------------------------------------
# 对象选择器：所有 target / a / b 参数都用这套语法
# --------------------------------------------------------------------------

const SELECTOR_SELF := "self"
const SELECTOR_OTHER := "other"
const SELECTOR_TAG_PREFIX := "tag:"
const SELECTOR_INSTANCE_PREFIX := "instance:"

const SELECTOR_HELP := "self=自身，other=对方，tag:玩家=所有带该标签的对象，instance:xxx=指定实例"


## 这个事件会不会给出"触发它的那个对象"。
##
## 「自身」只有在给出触发对象的事件里才解析得到东西：碰撞、属性变化、
## 对象出现 / 消失。像「每一帧」「点击屏幕」「每隔一段时间」这类事件
## 根本没有触发对象 —— 在那里面写「自身」，动作会静静地什么都不做。
## 所以界面不该把它列出来，校验器还得再拦一道。
static func trigger_provides_actor(type: String) -> bool:
	match type:
		"collision", "property_change", "entity_created", "entity_destroyed":
			return true
	return false


## "对方"只在碰撞里存在 —— 碰撞才有"另一方"。
static func trigger_provides_other(type: String) -> bool:
	return type == "collision"


## 新建条件 / 动作时的默认类型。
## 挑最常用的那个，让用户少改一次下拉框 —— 取字典里的第一个键
## 会得到「按住按键」这种偏门选项，对刚上手的人不友好。
const DEFAULT_CONDITION := "compare"
const DEFAULT_ACTION := "change_property"


# --------------------------------------------------------------------------
# 规则参数里的「按键」候选项
# --------------------------------------------------------------------------
#
# 规则里要引用"按住哪个键"时，给的是一个下拉框而不是一个空输入框。
# 原因很具体：手打的那个框填错了**不会有任何提示**，规则只是永远不成立，
# 排查起来像是"按键坏了"。给成下拉框，想打错都难。
#
# 两张表各管一类东西，别混在一起看：
#   ACTION_PARAM_*   输入动作。屏幕按键按下去就是这些；键盘上的方向键、
#                    空格也算同一个动作（引擎的输入表把它们绑在一起了）
#   KEYBOARD_KEY_*   键盘上的实体键。玩家按键盘才会触发，屏幕按键不会
#
# 动作那一张和屏幕按键（本文件下半部分的 BUTTON_ACTIONS）共用同一套说法：
# 属性面板里选「往左走」，规则句子里念出来也是「往左走」，不会各说各的。
# 名字只写在这里一处，两处用法都从这里取，漂了就由测试立刻报出来。

const ACTION_PARAM_OPTIONS := [
	"ui_left", "ui_right", "ui_up", "ui_down", "ui_accept", "ui_cancel", "ui_select",
]
const ACTION_PARAM_LABELS := {
	"ui_left": "往左走",
	"ui_right": "往右走",
	"ui_up": "往上走",
	"ui_down": "往下走",
	"ui_accept": "跳跃",
	"ui_cancel": "返回",
	"ui_select": "选择",
}

const KEYBOARD_KEY_OPTIONS := ["Space", "Enter", "Escape", "A", "D", "W", "S", "E", "Q"]
const KEYBOARD_KEY_LABELS := {
	"Space": "空格",
	"Enter": "回车",
	"Escape": "Esc",
	"A": "A", "D": "D", "W": "W", "S": "S", "E": "E", "Q": "Q",
}


# --------------------------------------------------------------------------
# 事件
# --------------------------------------------------------------------------

const TRIGGERS := {
	"every_frame": {
		"label": "每一帧（持续执行）",
		"desc": "只要游戏在运行就重复执行，用来做持续性的事情，例如按住方向键移动",
		"params": {},
	},
	"game_start": {
		"label": "游戏开始时",
		"desc": "场景加载完成、游戏正式开始的那一刻，触发一次",
		"params": {},
	},
	"tap": {
		"label": "点击屏幕时",
		"desc": "玩家点击或触摸屏幕任意位置",
		"params": {},
	},
	"key_press": {
		"label": "按下按键时",
		"desc": "按下键盘按键（桌面端调试用）",
		"params": {
			"key": {
				"type": "enum", "label": "哪个键", "default": "Space",
				"options": KEYBOARD_KEY_OPTIONS, "option_labels": KEYBOARD_KEY_LABELS,
			},
		},
	},
	"collision": {
		"label": "发生碰撞时",
		"desc": "两个对象碰到一起。任一方的碰撞体会触发一次",
		"params": {
			"a": {"type": "selector", "label": "对象 A", "default": "tag:player"},
			"b": {"type": "selector", "label": "对象 B", "default": "tag:coin"},
		},
	},
	"timer": {
		"label": "每隔一段时间",
		"desc": "按固定间隔反复触发，可设置只触发一次",
		"params": {
			"interval": {"type": "number", "label": "间隔（秒）", "default": 1.0, "min": 0.01},
			"repeat": {"type": "bool", "label": "重复触发", "default": true},
			"delay": {"type": "number", "label": "首次延迟（秒）", "default": 0.0, "min": 0.0},
		},
	},
	"property_change": {
		"label": "属性变化时",
		"desc": "某个对象的某个属性数值发生了变化",
		"params": {
			"target": {"type": "selector", "label": "监视对象", "default": "tag:player"},
			"property": {"type": "property", "label": "属性名", "default": "score"},
		},
	},
	"entity_created": {
		"label": "对象被创建时",
		"desc": "有新对象出现在场景里",
		"params": {
			"target": {"type": "selector", "label": "对象", "default": "tag:enemy"},
		},
	},
	"entity_destroyed": {
		"label": "对象被销毁时",
		"desc": "有对象从场景里消失",
		"params": {
			"target": {"type": "selector", "label": "对象", "default": "tag:enemy"},
		},
	},
}


# --------------------------------------------------------------------------
# 条件
# --------------------------------------------------------------------------

const CONDITIONS := {
	"key_held": {
		"label": "按住按键",
		"desc": "某个输入动作当前处于按下状态。屏幕按键按下去也算",
		"params": {
			"key": {
				"type": "enum", "label": "哪个键", "default": "ui_right",
				"options": ACTION_PARAM_OPTIONS, "option_labels": ACTION_PARAM_LABELS,
			},
		},
	},
	"grounded": {
		"label": "在地面上",
		"desc": "对象站在某个固体上，没有悬空",
		"params": {
			"target": {"type": "selector", "label": "对象", "default": "self"},
		},
	},
	"compare": {
		"label": "属性满足条件",
		"desc": "读取对象的一个属性，和给定数值做比较",
		"params": {
			"target": {"type": "selector", "label": "对象", "default": "tag:player"},
			"property": {"type": "property", "label": "属性名", "default": "score"},
			"op": {
				"type": "enum", "label": "比较方式", "default": ">=",
				"options": ["==", "!=", ">", ">=", "<", "<="],
			},
			"value": {"type": "number", "label": "数值", "default": 0},
		},
	},
	"chance": {
		"label": "按概率",
		"desc": "有百分之多少的几率成立",
		"params": {
			"percent": {"type": "number", "label": "概率（%）", "default": 50.0, "min": 0.0, "max": 100.0},
		},
	},
	"has_tag": {
		"label": "具有标签",
		"desc": "对象身上带有某个标签",
		"params": {
			"target": {"type": "selector", "label": "对象", "default": "self"},
			"tag": {"type": "string", "label": "标签", "default": ""},
		},
	},
	"count": {
		"label": "对象数量满足条件",
		"desc": "统计场景中符合条件的对象个数，和给定数值比较",
		"params": {
			"target": {"type": "selector", "label": "对象", "default": "tag:coin"},
			"op": {
				"type": "enum", "label": "比较方式", "default": "==",
				"options": ["==", "!=", ">", ">=", "<", "<="],
			},
			"value": {"type": "number", "label": "数量", "default": 0},
		},
	},
	"touching": {
		"label": "正在接触",
		"desc": "两个对象当前是否贴在一起",
		"params": {
			"a": {"type": "selector", "label": "对象 A", "default": "tag:player"},
			"b": {"type": "selector", "label": "对象 B", "default": "tag:ground"},
		},
	},
}


# --------------------------------------------------------------------------
# 动作
# --------------------------------------------------------------------------

const ACTIONS := {
	"set_property": {
		"label": "设置属性",
		"desc": "把对象的某个属性设为固定值",
		"params": {
			"target": {"type": "selector", "label": "对象", "default": "self"},
			"property": {"type": "string", "label": "属性名", "default": "score"},
			"value": {"type": "number", "label": "设为", "default": 0},
		},
	},
	"change_property": {
		"label": "增减属性",
		"desc": "把对象的某个属性加上或减去一个数值",
		"params": {
			"target": {"type": "selector", "label": "对象", "default": "tag:player"},
			"property": {"type": "string", "label": "属性名", "default": "score"},
			"delta": {"type": "number", "label": "增减量", "default": 1},
		},
	},
	"move": {
		"label": "移动",
		"desc": "把对象朝某个方向挪动一段距离，立即生效",
		"params": {
			"target": {"type": "selector", "label": "对象", "default": "self"},
			"dx": {"type": "number", "label": "水平距离", "default": 0},
			"dy": {"type": "number", "label": "垂直距离", "default": 0},
		},
	},
	"set_velocity": {
		"label": "设置速度",
		"desc": "直接设定对象的运动速度。只填一个方向时，另一个方向保持不变",
		"params": {
			"target": {"type": "selector", "label": "对象", "default": "self"},
			"vx": {"type": "number", "label": "水平速度", "default": 0, "required": false},
			"vy": {"type": "number", "label": "垂直速度", "default": 0, "required": false},
		},
	},
	"apply_impulse": {
		"label": "施加速度冲量",
		"desc": "在当前速度上额外叠加一个速度，常用于跳跃和击退",
		"params": {
			"target": {"type": "selector", "label": "对象", "default": "self"},
			"vx": {"type": "number", "label": "水平增量", "default": 0},
			"vy": {"type": "number", "label": "垂直增量", "default": -700},
		},
	},
	"jump": {
		"label": "跳跃",
		"desc": "按跳跃高度向上跳，自动换算成合适的速度",
		"params": {
			"target": {"type": "selector", "label": "对象", "default": "tag:player"},
			"height": {"type": "number", "label": "跳跃高度（像素）", "default": 180.0, "min": 1.0},
		},
	},
	"set_visible": {
		"label": "显示 / 隐藏",
		"desc": "控制对象是否可见",
		"params": {
			"target": {"type": "selector", "label": "对象", "default": "self"},
			"value": {"type": "bool", "label": "可见", "default": true},
		},
	},
	"spawn": {
		"label": "创建对象",
		"desc": "在指定位置生成一个新对象",
		"params": {
			"entity_id": {"type": "entity", "label": "对象类型", "default": ""},
			"x": {"type": "number", "label": "横坐标", "default": 640},
			"y": {"type": "number", "label": "纵坐标", "default": 100},
			"tag": {"type": "string", "label": "附加标签", "default": ""},
		},
	},
	"destroy": {
		"label": "删除对象",
		"desc": "把对象从场景里移除",
		"params": {
			"target": {"type": "selector", "label": "对象", "default": "other"},
		},
	},
	"switch_scene": {
		"label": "切换关卡",
		"desc": "跳转到另一个场景",
		"params": {
			"scene_id": {"type": "scene", "label": "目标场景", "default": ""},
		},
	},
	"end_game": {
		"label": "结束游戏",
		"desc": "游戏以胜利或失败结束",
		"params": {
			"result": {
				"type": "enum", "label": "结果", "default": "win",
				"options": ["win", "lose"],
				"option_labels": {"win": "胜利", "lose": "失败"},
			},
			"message": {"type": "string", "label": "提示文字", "default": ""},
		},
	},
	"wait": {
		"label": "等待",
		"desc": "暂停指定秒数后再执行后续动作",
		"params": {
			"seconds": {"type": "number", "label": "等待（秒）", "default": 0.5, "min": 0.0},
		},
	},
}


# --------------------------------------------------------------------------
# 屏幕按键能绑定的输入动作
# --------------------------------------------------------------------------
#
# 触屏上没有键盘，屏幕按键就是补这个的：手指按下去 = 按住对应的输入动作。
# 于是「按住左键就往左走」这类规则在键盘和触屏上共用同一套写法。
#
# 和上面几张表一样，这里也是**数据**：编辑器拿它生成下拉框，
# 运行器拿它决定按键上画什么、写什么字。两边读同一份，
# 才不会出现「面板上选的是一个动作、按键上写着另一个」这种事。
#
# 字段：
#   label —— 画在按键上的短字（方向键其实画箭头，用不上）
#   menu  —— 面板和规则里给人看的说法，统一从上面的 ACTION_PARAM_LABELS 取，
#            免得同一个动作在按键面板里叫一个名、在规则里又叫另一个名
#   arrow —— 方向键画哪个箭头，不是方向就留空
#   hint  —— 选中这项时底下的一行说明
#
# 只列做原型真会用到的几个，不是把 InputMap 里几十个内置动作全倒出来 ——
# 列表太长，用户反而找不到要的那一个。要绑别的动作仍然可以手改 JSON。

const BUTTON_ACTIONS := {
	"ui_left": {
		"label": "左", "menu": ACTION_PARAM_LABELS.ui_left, "arrow": "left",
		"hint": "按住这个键，等于一直按着键盘的左方向键",
	},
	"ui_right": {
		"label": "右", "menu": ACTION_PARAM_LABELS.ui_right, "arrow": "right",
		"hint": "按住这个键，等于一直按着键盘的右方向键",
	},
	"ui_up": {
		"label": "上", "menu": ACTION_PARAM_LABELS.ui_up, "arrow": "up",
		"hint": "按住这个键，等于一直按着键盘的上方向键",
	},
	"ui_down": {
		"label": "下", "menu": ACTION_PARAM_LABELS.ui_down, "arrow": "down",
		"hint": "按住这个键，等于一直按着键盘的下方向键",
	},
	"ui_accept": {
		"label": "跳", "menu": ACTION_PARAM_LABELS.ui_accept, "arrow": "",
		"hint": "等于按空格或回车。做跳跃键就绑这个",
	},
	"ui_cancel": {
		"label": "返回", "menu": ACTION_PARAM_LABELS.ui_cancel, "arrow": "",
		"hint": "等于按 Esc",
	},
	"ui_select": {
		"label": "选择", "menu": ACTION_PARAM_LABELS.ui_select, "arrow": "",
		"hint": "留给你自己定义的功能键，具体做什么由规则决定",
	},
}


## 这个动作在按键上写什么字。方向键用不上（画箭头），不认识的动作返回空串。
static func button_action_label(action: String) -> String:
	return String(BUTTON_ACTIONS.get(action, {}).get("label", ""))


## 这个动作在下拉框里显示成人话。
## 表里没有的动作就把 id 原样显示出来 —— 用户手改 JSON 绑了个别的动作时，
## 至少看得见它是什么，而不是一片空白让人以为没绑上。
static func button_action_menu(action: String) -> String:
	return String(BUTTON_ACTIONS.get(action, {}).get("menu", action))


## 方向动作画哪个箭头。"left" / "right" / "up" / "down"，不是方向就空串。
static func button_action_arrow(action: String) -> String:
	return String(BUTTON_ACTIONS.get(action, {}).get("arrow", ""))


## 这个动作是干什么的，一句话。用在属性面板的说明行里。
static func button_action_hint(action: String) -> String:
	return String(BUTTON_ACTIONS.get(action, {}).get("hint", ""))


## 下拉框里的选项，顺序和表里声明的一样。
static func button_action_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in BUTTON_ACTIONS:
		ids.append(String(id))
	return ids


# --------------------------------------------------------------------------
# 查询辅助
# --------------------------------------------------------------------------


# --------------------------------------------------------------------------
# 复述：把一条规则念成人话
# --------------------------------------------------------------------------
#
# 这是「非编程用户友好」最直接的体现 —— 用户配完之后，界面上能把配置
# 读回来念给他听，他一眼就知道自己配得对不对，不需要去理解 JSON。
#
# 和上面的事件、条件、动作一样，这里也是**数据**：给每种类型一句模板，
# 参数用 %{名字} 占位。新增一种动作时，补一句模板就行。

const TRIGGER_PHRASES := {
	"every_frame": "每一帧",
	"game_start": "游戏开始时",
	"tap": "点击屏幕时",
	"key_press": "按下「%{key}」键时",
	"collision": "%{a}碰到%{b}时",
	"timer": "每隔 %{interval} 秒",
	"property_change": "%{target}的「%{property}」变化时",
	"entity_created": "%{target}出现时",
	"entity_destroyed": "%{target}消失时",
}

const CONDITION_PHRASES := {
	"key_held": "正按住「%{key}」",
	"grounded": "%{target}站在地上",
	"compare": "%{target}的「%{property}」%{op}%{value}",
	"chance": "有 %{percent}% 的运气",
	"has_tag": "%{target}带有「%{tag}」标签",
	"count": "%{target}的数量%{op}%{value}",
	"touching": "%{a}正贴着%{b}",
}

## 条件被勾了「反向」之后怎么念。
##
## 不能统一套一个"不"字：「不正按住」不通顺，「不站在地上」也不像人话。
## 所以每种条件各写一句。compare 不在这张表里 —— 它靠把运算符翻过来念
## （「>= 0」的反面是「< 0」），见下面的 describe()。
##
## 和上面几张表一样，这里也是数据；少写一个会有测试立刻报出来。
const CONDITION_NEGATED_PHRASES := {
	"key_held": "没有按住「%{key}」",
	"grounded": "%{target}悬在空中",
	"chance": "运气没中（只有 %{percent}% 的把握）",
	"has_tag": "%{target}不带「%{tag}」标签",
	"count": "%{target}的数量不满足 %{op}%{value}",
	"touching": "%{a}没贴着%{b}",
}

## 比较运算符的反面。念成「不满足 >= 0」也能懂，但「< 0」更像人话。
const OP_OPPOSITE := {
	"==": "!=", "!=": "==",
	">": "<=", ">=": "<",
	"<": ">=", "<=": ">",
}

const ACTION_PHRASES := {
	"set_property": "把%{target}的「%{property}」设为 %{value}",
	"change_property": "把%{target}的「%{property}」增减 %{delta}",
	"move": "把%{target}挪动 %{dx}, %{dy}",
	"set_velocity": "把%{target}的速度设为 %{vx}, %{vy}",
	"apply_impulse": "给%{target}一个 %{vx}, %{vy} 的冲劲",
	"jump": "让%{target}跳起来（高度 %{height}）",
	"set_visible": "让%{target} %{value}",
	"spawn": "在 %{x}, %{y} 生成%{entity_id}",
	"destroy": "删除%{target}",
	"switch_scene": "切换到「%{scene_id}」",
	"end_game": "游戏以「%{result}」结束",
	"wait": "等 %{seconds} 秒",
}


## 把一条规则念成一句话。
## project 用来把 id 换成名字（"ent_coin" → "金币"），传 null 时会直接显示 id。
static func describe(rule: RuleDef, project: GameProject = null) -> String:
	var trigger_type := String(rule.trigger.get("type", ""))
	if not TRIGGERS.has(trigger_type):
		return "（事件类型不认识，需要重新选一个）"

	var clauses: Array[String] = []
	clauses.append("当%s" % _fill(TRIGGER_PHRASES[trigger_type], rule.trigger,
		trigger_def(trigger_type), project))

	if not rule.conditions.is_empty():
		var parts: Array[String] = []
		for condition in rule.conditions:
			if not (condition is Dictionary):
				continue
			var type := String(condition.get("type", ""))
			if not CONDITIONS.has(type):
				continue
			parts.append(_condition_phrase(type, condition, project))
		if not parts.is_empty():
			clauses.append("如果%s" % "、".join(parts))

	var actions: Array[String] = []
	for action in rule.actions:
		if not (action is Dictionary):
			continue
		var type := String(action.get("type", ""))
		if not ACTIONS.has(type):
			continue
		actions.append(_fill(ACTION_PHRASES[type], action, action_def(type), project))
	if actions.is_empty():
		clauses.append("（还没有动作，这条规则不会产生效果）")
	else:
		clauses.append("就%s" % "，".join(actions))

	return "，".join(clauses)


## 把模板里的 %{参数名} 换成可读的值
## 一条条件念成半句话；勾了「反向」就念反面。
##
## 单独抽成函数，是为了别让 describe() 里堆一串 if：
## "反向怎么念"这件事只在这一个地方判断，改口吻也只改这里。
static func _condition_phrase(type: String, condition: Dictionary, project: GameProject) -> String:
	var def := condition_def(type)
	if not bool(condition.get("negate", false)):
		return _fill(CONDITION_PHRASES[type], condition, def, project)

	# 比较类：把运算符翻过来念（「>= 0」→「< 0」），比"不满足 >="顺口
	if type == "compare":
		var flipped := condition.duplicate()
		var op := String(condition.get("op", ""))
		flipped["op"] = OP_OPPOSITE.get(op, op)
		return _fill(CONDITION_PHRASES[type], flipped, def, project)

	# 其它类型各有各的说法；万一漏写了，退回"没有"，至少不会念反
	if CONDITION_NEGATED_PHRASES.has(type):
		return _fill(CONDITION_NEGATED_PHRASES[type], condition, def, project)
	return "没有「%s」" % _fill(CONDITION_PHRASES[type], condition, def, project)


static func _fill(template: String, statement: Dictionary, def: Dictionary, project: GameProject) -> String:
	var text := template
	var params: Dictionary = def.get("params", {})
	for key in params:
		var fallback: Variant = params[key].get("default", "")
		var value: Variant = statement.get(key, fallback)
		text = text.replace("%{" + key + "}", render_param(def, key, value, project))
	return text


static func render_param(def: Dictionary, key: String, value: Variant, project: GameProject) -> String:
	var params: Dictionary = def.get("params", {})
	if not params.has(key):
		return str(value)
	var spec: Dictionary = params[key]
	match String(spec.get("type", "string")):
		"selector":
			return render_selector(String(value), project)
		"entity":
			if project != null:
				var entity := project.find_entity(String(value))
				if entity != null:
					return entity.name
			return String(value)
		"scene":
			if project != null:
				var scene := project.find_scene(String(value))
				if scene != null:
					return scene.name
			return String(value)
		"asset":
			if project != null:
				var asset := project.find_asset(String(value))
				if asset != null:
					return asset.name
			return String(value)
		"enum":
			var labels: Dictionary = spec.get("option_labels", {})
			return String(labels.get(String(value), value))
		"bool":
			return "显示" if bool(value) else "隐藏"
		"number":
			return format_number(value)
	return String(value)


## 对象选择器在句子里的读法。
## 标签渲染成「玩家」而不是「所有「玩家」」—— 在句子里这样读才顺。
static func render_selector(selector: String, project: GameProject) -> String:
	var parsed := parse_selector(selector)
	match String(parsed["kind"]):
		"self":
			return "自己"
		"other":
			return "对方"
		"tag":
			return "「%s」" % tag_display_name(String(parsed["value"]), project)
		"instance":
			if project != null:
				var target := String(parsed["value"])
				for scene in project.scenes:
					for placed in scene.instances:
						if placed.instance_id == target:
							var def := project.find_entity(placed.entity_id)
							return def.name if def != null else placed.entity_id
	return selector


## 标签在句子里的叫法。
##
## 一个标签通常挂在某种实体上（player → 小恐龙）。直接念实体名字，
## 比念标签本身好懂得多 —— 标签是给程序看的，"player" 这种词
## 对一个做游戏原型的人来说毫无意义。
## 一个标签挂到多种实体上时，把这些名字都念出来。
static func tag_display_name(tag: String, project: GameProject) -> String:
	if project == null:
		return tag
	var names: Array[String] = []
	for def in project.entities:
		if def.has_tag(tag) and not names.has(def.name):
			names.append(def.name)
	if names.is_empty():
		return tag
	return "、".join(names)


## 去掉没有意义的小数尾巴：1600.0 念成 "1600"，1.5 保持 "1.5"
static func format_number(value: Variant) -> String:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return str(value)
	var number := float(value)
	if is_equal_approx(number, roundf(number)):
		return str(int(number))
	return str(number)

static func trigger_names() -> PackedStringArray:
	return PackedStringArray(TRIGGERS.keys())


static func condition_names() -> PackedStringArray:
	return PackedStringArray(CONDITIONS.keys())


static func action_names() -> PackedStringArray:
	return PackedStringArray(ACTIONS.keys())


static func trigger_def(type: String) -> Dictionary:
	return TRIGGERS.get(type, {})


static func condition_def(type: String) -> Dictionary:
	return CONDITIONS.get(type, {})


static func action_def(type: String) -> Dictionary:
	return ACTIONS.get(type, {})


static func trigger_label(type: String) -> String:
	return String(trigger_def(type).get("label", type))


static func condition_label(type: String) -> String:
	return String(condition_def(type).get("label", type))


static func action_label(type: String) -> String:
	return String(action_def(type).get("label", type))


## 生成一条语句的默认参数表，编辑器新增语句时调用。
static func default_params(def: Dictionary) -> Dictionary:
	var out := {}
	var params: Dictionary = def.get("params", {})
	for key in params:
		out[key] = params[key].get("default", null)
	return out


## 取出某个语句类型的参数定义表，供编辑器生成表单。
static func param_defs(def: Dictionary) -> Dictionary:
	return def.get("params", {})


static func param_label(def: Dictionary, param: String) -> String:
	var params: Dictionary = def.get("params", {})
	if not params.has(param):
		return param
	return String(params[param].get("label", param))


## 解析对象选择器："tag:coin" -> {"kind": "tag", "value": "coin"}
static func parse_selector(selector: String) -> Dictionary:
	var s := selector.strip_edges()
	if s.begins_with(SELECTOR_TAG_PREFIX):
		return {"kind": "tag", "value": s.substr(SELECTOR_TAG_PREFIX.length())}
	if s.begins_with(SELECTOR_INSTANCE_PREFIX):
		return {"kind": "instance", "value": s.substr(SELECTOR_INSTANCE_PREFIX.length())}
	if s == SELECTOR_SELF:
		return {"kind": "self", "value": ""}
	if s == SELECTOR_OTHER:
		return {"kind": "other", "value": ""}
	return {"kind": "unknown", "value": s}
