## 无素材时的占位图形。
##
## 这个类看起来不起眼，但它决定了产品能否「零美术资源起步」。
## 用户第一次打开工具、拖出一个角色时手上一张图都没有，
## 此时必须立刻看到东西并且能玩，否则第一印象就崩了。
class_name PlaceholderVisual
extends Node2D

const SHAPE_RECT := "rect"
const SHAPE_CIRCLE := "circle"

var shape: String = SHAPE_RECT
var size: Vector2 = Vector2(48, 48)
var color: Color = Color("#4ade80")
var outline_color: Color = Color(0, 0, 0, 0.25)
var corner_radius: float = 8.0


func configure(p_shape: String, p_size: Vector2, p_color: Color) -> void:
	shape = p_shape
	size = p_size
	color = p_color
	queue_redraw()


func _draw() -> void:
	match shape:
		SHAPE_CIRCLE:
			var r := minf(size.x, size.y) * 0.5
			draw_circle(Vector2.ZERO, r, color)
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, outline_color, 2.0, true)
		_:
			var rect := Rect2(-size * 0.5, size)
			draw_rect(rect, color, true)
			draw_rect(rect, outline_color, false, 2.0)
			# 顶部高光条，让占位方块看起来更像一个「角色」而不是一块色斑
			var highlight := Rect2(rect.position + Vector2(0, 0), Vector2(rect.size.x, maxf(4.0, rect.size.y * 0.12)))
			draw_rect(highlight, Color(1, 1, 1, 0.18), true)
