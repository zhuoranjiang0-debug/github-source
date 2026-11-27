# 数据模型

一个游戏原型就是一份 JSON 文档，扩展名 `.ai2d`，UTF-8 编码。

本文是**唯一的契约**：`app/src/core/model/` 里的模型类、`app/src/core/model/rule_vocabulary.gd` 里的词汇表、`app/samples/` 里的示例，三者必须与本文保持一致。改任何一处都要同步改另外两处，并双击 `运行测试.bat` 确认没坏。

## 顶层结构

```jsonc
{
  "schema_version": "1.1",
  "id": "prj_demo_jump",
  "name": "跳跃小恐龙",
  "created_at": "2026-09-16T10:00:00",
  "updated_at": "2026-09-16T10:00:00",
  "config":   { ... },   // 工程级设置
  "assets":   [ ... ],   // 素材
  "entities": [ ... ],   // 实体定义（相当于预制体）
  "scenes":   [ ... ],   // 场景（关卡）
  "rules":    [ ... ]    // 可视化逻辑
}
```

### 版本与升级

`schema_version` 是工程文件的格式版本，当前 **`1.1`**。

**改数据含义时必须加版本号，并在 `GameProject._upgrade()` 里补一笔升级。**
不然用户打开旧工程会撞上"看着没事、跑起来不对"的怪事 —— 已经吃过一次亏：

| 版本 | 变化 | 老文件怎么升 |
| --- | --- | --- |
| 1.1 | 碰撞组新增「地面」一档（掉落物只和它碰） | 加载 1.0 文件时，带 `ground` 标签的实体自动从 `solid` 改成 `ground` |
| 1.0 | 初版 | — |

## config —— 工程设置

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `canvas.width` / `canvas.height` | int | 设计分辨率，编辑器画布与运行窗口都按它来 |
| `orientation` | `landscape` \| `portrait` | 屏幕方向。MVP 只保证横屏 |
| `gravity` | number | 全局重力加速度，像素/秒² |
| `background_color` | string | 默认背景色，`#RRGGBB` |
| `start_scene_id` | string | 起始场景 ID，留空则用第一个场景 |

## assets —— 素材

| 字段 | 说明 |
| --- | --- |
| `id` | 唯一标识 |
| `name` | 显示名 |
| `type` | `sprite` / `tileset` / `audio` / `font` |
| `source` | `builtin` / `generated`（AI 生成）/ `uploaded`（用户上传） |
| `path` | 文件路径。**留空表示还没有实体文件，运行时用占位图形渲染** |
| `meta` | 类型相关的附加信息，如图集帧尺寸 |

`path` 留空是一个被明确支持的正常状态，不是错误。用户第一次拖出角色时手上一张图都没有，此时必须能立刻看到东西并开始试玩。

## entities —— 实体定义

描述「一个角色长什么样、怎么动」。场景里摆放的是它的实例。

| 字段 | 说明 |
| --- | --- |
| `id` / `name` | 标识与显示名 |
| `asset_id` | 使用的素材。留空则用 `color` 画占位图形 |
| `color` | 占位图形颜色 |
| `tags` | 标签数组，规则通过 `tag:xxx` 选中它。**没有标签的实体无法被规则引用** |
| `collider.shape` | `none` / `rect` / `circle` |
| `collider.width` `height` `radius` | 碰撞尺寸 |
| `collider.offset_x` `offset_y` | 碰撞体相对实体原点的偏移 |
| `physics.mode` | `none` / `static` / `kinematic` / `rigid` |
| `physics.gravity_scale` | 重力倍率，仅对 `kinematic` 有效 |
| `physics.bounce` `friction` | 预留，当前版本未使用 |
| `collision_group` | `ground`（地面：挡得住会动的东西，也接得住掉落物）/ `solid`（默认：挡得住会动的东西，但掉落物会穿过去）/ `pickup`（拾取物：不挡任何人，**只落在「地面」上**） |
| `animations` | 动画名 → `{ "frames": [int], "fps": number, "loop": bool }` |
| `default_animation` | 初始播放的动画 |
| `initial_properties` | 初始属性表，如 `{ "score": 0, "hp": 3 }` |

### 物理类型怎么选

| 类型 | 行为 | 典型用途 |
| --- | --- | --- |
| `none` | 不参与物理，只有触发区，不阻挡任何对象 | 金币、检查点、拾取物、陷阱判定 |
| `static` | 固定不动，阻挡其他对象 | 地面、墙壁、平台 |
| `kinematic` | 受重力，可被规则直接设定速度 | 玩家、敌人、子弹 |
| `rigid` | 由物理引擎控制 | **当前版本尚未实现**，会被当作 `kinematic` 处理 |

关于 `rigid` 的说明：本产品的逻辑系统是事件—条件—动作，规则直接设定速度。而刚体的速度由物理引擎掌控，两套语义会互相冲突。因此刚体需要配套一套「施加力」型的动作，留待后续版本。

## scenes —— 场景

| 字段 | 说明 |
| --- | --- |
| `id` / `name` | 标识与显示名 |
| `background_color` | 覆盖工程默认背景色，留空则用工程的 |
| `background_asset_id` | 背景图素材 |
| `camera.mode` | `fixed`（固定） / `follow`（跟随） |
| `camera.target` | 跟随目标，选择器语法 |
| `camera.zoom` | 缩放倍率 |
| `tilemap.tile_size` | 地块尺寸 |
| `tilemap.asset_id` | 图集素材 |
| `tilemap.grid` | 二维数组，`-1` 表示空格 |
| `instances` | 摆放的实体实例列表 |

### instances —— 实体实例

| 字段 | 说明 |
| --- | --- |
| `instance_id` | 实例唯一标识，选择器 `instance:xxx` 用它 |
| `entity_id` | 引用的实体定义 |
| `x` / `y` | 位置 |
| `rotation` | 旋转弧度 |
| `scale_x` / `scale_y` | 缩放 |
| `flip_h` | 水平翻转 |
| `color` | **只改这一个对象**的颜色，`#RRGGBB`。留空表示跟随所属实体定义的颜色 |
| `button_action` | **只改这一个屏幕按键**绑定的输入动作。留空表示跟随所属实体定义 |
| `motion` | **只改这一个对象**"会不会动、会不会掉"：留空跟随类型 / `static` 静止不动 / `float` 会动不受重力 / `fall` 会动受重力 |
| `collision_group` | **只改这一个对象**的碰撞身份：留空跟随类型 / `ground` 地面 / `solid` 普通障碍 / `pickup` 拾取物 |
| `properties` | 属性覆盖，会盖在实体定义的 `initial_properties` 之上 |

`color` 是一个实例级覆盖：颜色原本只存在实体定义（类型）上，于是"把这枚金币改成红色"
在数据层面无法表达——一改就是所有金币一起变。加上这个字段之后，
界面上改的就是"这一个对象"。

## rules —— 可视化逻辑

一条规则 = **当【事件】发生，若【条件】全部成立，则执行【动作】**。

```jsonc
{
  "id": "rule_coin",
  "name": "吃到金币加分",
  "enabled": true,
  "scene_id": "",          // 留空表示对所有场景生效
  "trigger":    { "type": "collision", "a": "tag:player", "b": "tag:coin" },
  "conditions": [],
  "actions": [
    { "type": "change_property", "target": "tag:player", "property": "score", "delta": 1 },
    { "type": "destroy", "target": "other" }
  ]
}
```

### 求值语义

这四条语义是刻意保持简单的，宁可牺牲一点表达力，也不要让用户猜：

1. 条件之间是**并且**，全部成立才执行动作。
2. 带对象选择器的条件，选中的对象里**有任意一个**满足即算成立。
3. **任何条件都可以加 `"negate": true` 表示取反**，编辑器把它渲染成一个「反向」勾选框。
4. 动作按顺序执行，未指定目标时对选中的**全部**对象生效。
5. 事件在对象之间**只触发一次**。两个对象的触发区会各报告一次接触，但一条规则不会因此跑两遍。

### 持续性的行为怎么写

「按住方向键移动」这类行为由 `every_frame` 事件驱动，它每秒触发 60 次。配合 `key_held` 与 `negate`，三条件互斥的规则就能表达完整的移动：

```jsonc
{ "trigger": { "type": "every_frame" },
  "conditions": [ { "type": "key_held", "key": "ui_right" } ],
  "actions": [ { "type": "set_velocity", "target": "tag:player", "vx": 320 } ] }
```

注意 `set_velocity` 在这里只写了 `vx`。**未提供的轴保持不变**，这一点很关键：如果把 `vy` 一并写成 0，这条每帧执行的水平移动规则会顺手取消重力，角色会浮在空中。

### 对象选择器

所有 `target` / `a` / `b` 参数都用这套语法：

| 写法 | 含义 |
| --- | --- |
| `self` | 触发事件的对象。碰撞时固定为规则里的 A 方 |
| `other` | 事件的另一方。碰撞时固定为规则里的 B 方 |
| `tag:玩家` | 所有带该标签的对象 |
| `instance:i_coin_1` | 指定的那一个实例 |

### 事件

| 类型 | 名称 | 参数 |
| --- | --- | --- |
| `every_frame` | 每一帧（持续执行） | — |
| `game_start` | 游戏开始时 | — |
| `tap` | 点击屏幕时 | — |
| `key_press` | 按下按键时 | `key` |
| `collision` | 发生碰撞时 | `a`, `b` |
| `timer` | 每隔一段时间 | `interval`, `repeat`, `delay` |
| `property_change` | 属性变化时 | `target`, `property` |
| `entity_created` | 对象被创建时 | `target` |
| `entity_destroyed` | 对象被销毁时 | `target` |

### 条件

| 类型 | 名称 | 参数 |
| --- | --- | --- |
| `key_held` | 按住按键 | `key` |
| `grounded` | 在地面上 | `target` |
| `compare` | 属性满足条件 | `target`, `property`, `op`, `value` |
| `chance` | 按概率 | `percent` |
| `has_tag` | 具有标签 | `target`, `tag` |
| `count` | 对象数量满足条件 | `target`, `op`, `value` |
| `touching` | 正在接触 | `a`, `b` |

`op` 取值：`==` `!=` `>` `>=` `<` `<=`

### 动作

| 类型 | 名称 | 参数 |
| --- | --- | --- |
| `set_property` | 设置属性 | `target`, `property`, `value` |
| `change_property` | 增减属性 | `target`, `property`, `delta` |
| `move` | 移动 | `target`, `dx`, `dy` |
| `set_velocity` | 设置速度 | `target`, `vx`?, `vy`?（未提供的轴保持不变） |
| `apply_impulse` | 施加速度冲量 | `target`, `vx`, `vy` |
| `jump` | 跳跃 | `target`, `height` |
| `set_visible` | 显示 / 隐藏 | `target`, `value` |
| `spawn` | 创建对象 | `entity_id`, `x`, `y`, `tag` |
| `destroy` | 删除对象 | `target` |
| `switch_scene` | 切换关卡 | `scene_id` |
| `end_game` | 结束游戏 | `result`, `message` |
| `wait` | 等待 | `seconds` |

## 词汇表驱动的编辑器

上面三张表不是写在文档里的死表格，它们的**机器可读版本**在 [`rule_vocabulary.gd`](../app/src/core/model/rule_vocabulary.gd) 里，每个类型都带参数定义（类型、显示名、默认值、取值范围）。

编辑器的逻辑面板直接读取这份定义来生成表单。**新增一种动作只需要在词汇表里加一条，不需要改任何界面代码，也不需要改运行器。** 这是让「动作数量」能够持续增长而不拖垮开发速度的关键。

校验器 `ProjectValidator` 同样以词汇表为白名单，因此新增动作的校验也是自动的。
