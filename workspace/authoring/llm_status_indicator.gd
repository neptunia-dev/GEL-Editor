extends HBoxContainer

## 全局 LLM 状态指示器：Material Design 风格圆弧，无输出时慢速常转，
## 每次 llm_progress（检测到新输出）在当前速度基础上按比例加速，
## 指数衰减回落——转得快 = 正在出 token，只剩慢转 = 无产出。
## 仅在 working/error 时可见。

const ACCENT_BLUE := Color(0.341176, 0.588235, 0.901961, 1)
const TEXT_BRIGHT := Color(0.835294, 0.835294, 0.835294, 1)
const TEXT_RED := Color(0.95, 0.58, 0.54, 1)
const BASE_SPEED := 1.5
const BOOST := 0.5
const MAX_SPEED := 12.0
const DECAY := 1.5
const TRIM_RATIO := 0.75
const MIN_ARC := 0.35
const MAX_ARC := 4.7

var _state := "idle"
var _phase := 0.0
var _speed := BASE_SPEED
var _icon: Control
var _label: Label

class ArcIcon:
	extends Control
	var color := Color.WHITE
	var start := 0.0
	var arc_len := 0.35
	var error := false

	func _init() -> void:
		custom_minimum_size = Vector2(16, 16)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var center := size * 0.5
		if error:
			var r := 5.0
			draw_line(center + Vector2(-r, -r), center + Vector2(r, r), color, 2.0, true)
			draw_line(center + Vector2(-r, r), center + Vector2(r, -r), color, 2.0, true)
		else:
			draw_arc(center, 6.0, start, start + arc_len, 24, color, 2.0, true)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	alignment = ALIGNMENT_BEGIN
	_icon = ArcIcon.new()
	add_child(_icon)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.clip_text = true
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_label)
	visible = false
	set_process(false)

func set_state(state: String, message: String) -> void:
	var resume := _state == state
	_state = state
	match state:
		"working":
			visible = true
			if not resume:
				_speed = BASE_SPEED
			_icon.error = false
			_icon.color = ACCENT_BLUE
			_label.add_theme_color_override("font_color", TEXT_BRIGHT)
			_label.text = message
			set_process(true)
		"error":
			visible = true
			_icon.error = true
			_icon.color = TEXT_RED
			_label.add_theme_color_override("font_color", TEXT_RED)
			_label.text = message
			set_process(false)
		_:
			visible = false
			set_process(false)
	_icon.queue_redraw()

func advance() -> void:
	_speed = minf(_speed * (1.0 + BOOST), MAX_SPEED)

func _process(delta: float) -> void:
	_speed = BASE_SPEED + (_speed - BASE_SPEED) * exp(-DECAY * delta)
	_phase += _speed * delta
	_icon.start = _phase
	_icon.arc_len = MIN_ARC + (MAX_ARC - MIN_ARC) * (0.5 - 0.5 * cos(_phase * TRIM_RATIO))
	_icon.queue_redraw()
