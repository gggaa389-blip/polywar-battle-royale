class_name HUD
extends CanvasLayer
# واجهة اللعب: الإدخال (لمس/لوحة/فأرة)، الصحة، الذخيرة، الخريطة المصغّرة، سجل القتل، المنظار

var sens := 1.0
var touch_mode := false
var captured := false
var crouch_on := false
var fire_held := false
var ads_held := false
var acc_dyaw := 0.0
var acc_dpitch := 0.0
var pj := false
var pr := false
var pp := false
var ps := false
var pfe := false
var joy_idx := -1
var joy_origin := Vector2.ZERO
var joy_vec := Vector2.ZERO
var look_idx := -1
var look_last := Vector2.ZERO
var mpos := Vector2.ZERO

var root: Control
var alive_lbl: Label
var zone_lbl: Label
var banner: Label
var toast_lbl: Label
var toast_t := 0.0
var hp_bg: ColorRect
var hp_fill: ColorRect
var hp_lbl: Label
var wpn_lbl: Label
var ammo_lbl: Label
var feed: VBoxContainer
var flash: ColorRect
var mini: Control
var cross: Control
var scope: Control
var joy_draw: Control
var btn := {}
var hit_t := 0.0
var hit_head := false
var match_ref: BRMatch = null
var human_ref: Fighter = null
var spect_ref: Fighter = null
var sniper_ads := false
var ads_now := false
var zone_warn := false

func _ready() -> void:
	layer = 5
	touch_mode = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	alive_lbl = _label(18, HORIZONTAL_ALIGNMENT_CENTER)
	zone_lbl = _label(16, HORIZONTAL_ALIGNMENT_CENTER)
	banner = _label(22, HORIZONTAL_ALIGNMENT_CENTER)
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 6)
	toast_lbl = _label(22, HORIZONTAL_ALIGNMENT_CENTER)
	toast_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	toast_lbl.add_theme_constant_override("outline_size", 6)
	toast_lbl.visible = false
	hp_bg = ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.55)
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hp_bg)
	hp_fill = ColorRect.new()
	hp_fill.color = Color(0.3, 0.9, 0.35)
	hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hp_fill)
	hp_lbl = _label(15, HORIZONTAL_ALIGNMENT_LEFT)
	wpn_lbl = _label(18, HORIZONTAL_ALIGNMENT_LEFT)
	ammo_lbl = _label(18, HORIZONTAL_ALIGNMENT_LEFT)
	feed = VBoxContainer.new()
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(feed)
	mini = Control.new()
	mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini.draw.connect(_draw_mini)
	root.add_child(mini)
	flash = ColorRect.new()
	flash.color = Color(0.8, 0.0, 0.0, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(flash)
	cross = Control.new()
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	cross.draw.connect(_draw_cross)
	root.add_child(cross)
	scope = Control.new()
	scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	scope.draw.connect(_draw_scope)
	scope.visible = false
	root.add_child(scope)
	joy_draw = Control.new()
	joy_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	joy_draw.draw.connect(_draw_joy)
	joy_draw.visible = touch_mode
	root.add_child(joy_draw)
	if touch_mode:
		_make_buttons()
	get_viewport().size_changed.connect(_layout)
	_layout()

func _label(sz: int, align: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l

func _make_buttons() -> void:
	_btn("fire", "إطلاق", Vector2(150, 150))
	_btn("ads", "تصويب", Vector2(92, 92))
	_btn("jump", "قفز", Vector2(92, 92))
	_btn("reload", "تعبئة", Vector2(82, 82))
	_btn("pick", "التقاط", Vector2(82, 82))
	_btn("crouch", "جلوس", Vector2(82, 82))
	_btn("switch", "تبديل", Vector2(82, 82))
	var b: Button = btn["fire"]
	b.button_down.connect(func(): fire_held = true)
	b.button_up.connect(func(): fire_held = false)
	var a: Button = btn["ads"]
	a.button_down.connect(func(): ads_held = true)
	a.button_up.connect(func(): ads_held = false)
	(btn["jump"] as Button).pressed.connect(func(): pj = true)
	(btn["reload"] as Button).pressed.connect(func(): pr = true)
	(btn["pick"] as Button).pressed.connect(func(): pp = true)
	(btn["switch"] as Button).pressed.connect(func(): ps = true)
	(btn["crouch"] as Button).pressed.connect(func(): crouch_on = not crouch_on)

func _btn(key: String, text: String, sz: Vector2) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = sz
	b.size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.12, 0.55)
	sb.set_corner_radius_all(int(sz.x * 0.5))
	sb.set_border_width_all(3)
	sb.border_color = Color(1, 1, 1, 0.6)
	b.add_theme_stylebox_override("normal", sb)
	var sbp := sb.duplicate() as StyleBoxFlat
	sbp.bg_color = Color(0.9, 0.5, 0.1, 0.7)
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_color_override("font_color", Color.WHITE)
	root.add_child(b)
	btn[key] = b

func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	var W := s.x
	var H := s.y
	alive_lbl.position = Vector2(W * 0.5 - 200, 10)
	alive_lbl.size = Vector2(400, 28)
	zone_lbl.position = Vector2(W * 0.5 - 260, 38)
	zone_lbl.size = Vector2(520, 26)
	banner.position = Vector2(W * 0.5 - 360, H * 0.2)
	banner.size = Vector2(720, 40)
	toast_lbl.position = Vector2(W * 0.5 - 300, H * 0.3)
	toast_lbl.size = Vector2(600, 40)
	mini.position = Vector2(W - 200, 10)
	mini.size = Vector2(190, 190)
	feed.position = Vector2(W - 340, 210)
	feed.size = Vector2(330, 200)
	hp_bg.position = Vector2(20, H - 90)
	hp_bg.size = Vector2(260, 20)
	hp_fill.position = hp_bg.position + Vector2(2, 2)
	hp_lbl.position = Vector2(20, H - 118)
	hp_lbl.size = Vector2(260, 24)
	wpn_lbl.position = Vector2(20, H - 170)
	wpn_lbl.size = Vector2(340, 28)
	ammo_lbl.position = Vector2(20, H - 142)
	ammo_lbl.size = Vector2(340, 28)
	cross.queue_redraw()
	scope.queue_redraw()
	joy_draw.queue_redraw()
	if touch_mode:
		(btn["fire"] as Button).position = Vector2(W - 190, H - 190)
		(btn["ads"] as Button).position = Vector2(W - 300, H - 130)
		(btn["jump"] as Button).position = Vector2(W - 300, H - 240)
		(btn["reload"] as Button).position = Vector2(W - 400, H - 130)
		(btn["pick"] as Button).position = Vector2(W - 400, H - 230)
		(btn["crouch"] as Button).position = Vector2(W - 500, H - 130)
		(btn["switch"] as Button).position = Vector2(W - 500, H - 230)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		match k.keycode:
			KEY_SPACE: pj = true
			KEY_R: pr = true
			KEY_F, KEY_E: pp = true
			KEY_Q: ps = true
			KEY_C: crouch_on = not crouch_on
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				captured = false
	elif event is InputEventMouseButton and not touch_mode:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			fire_held = mb.pressed
			if mb.pressed:
				pfe = true
				if not captured:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
					captured = true
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			ads_held = mb.pressed
	elif event is InputEventMouseMotion and captured and not touch_mode:
		var mm := event as InputEventMouseMotion
		acc_dyaw -= mm.relative.x * 0.0028 * sens
		acc_dpitch -= mm.relative.y * 0.0028 * sens
	elif event is InputEventScreenTouch and touch_mode:
		var st := event as InputEventScreenTouch
		if st.pressed:
			if _on_button(st.position):
				return
			if st.position.x < get_viewport().get_visible_rect().size.x * 0.42 and joy_idx < 0:
				joy_idx = st.index
				joy_origin = st.position
				joy_vec = Vector2.ZERO
			elif look_idx < 0:
				look_idx = st.index
				look_last = st.position
		else:
			if st.index == joy_idx:
				joy_idx = -1
				joy_vec = Vector2.ZERO
			if st.index == look_idx:
				look_idx = -1
	elif event is InputEventScreenDrag and touch_mode:
		var sd := event as InputEventScreenDrag
		if sd.index == joy_idx:
			var v := (sd.position - joy_origin) / 70.0
			if v.length() > 1.0:
				v = v.normalized()
			joy_vec = Vector2(v.x, -v.y)
			joy_draw.queue_redraw()
		elif sd.index == look_idx:
			var dlt := sd.position - look_last
			look_last = sd.position
			acc_dyaw -= dlt.x * 0.0065 * sens
			acc_dpitch -= dlt.y * 0.0065 * sens

func _on_button(p: Vector2) -> bool:
	for k in btn:
		var b: Button = btn[k]
		if b.get_global_rect().grow(12).has_point(p):
			return true
	return false

func take_input() -> Dictionary:
	var mv := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		mv.y += 1.0
	if Input.is_key_pressed(KEY_S):
		mv.y -= 1.0
	if Input.is_key_pressed(KEY_D):
		mv.x += 1.0
	if Input.is_key_pressed(KEY_A):
		mv.x -= 1.0
	mv += joy_vec
	if mv.length() > 1.0:
		mv = mv.normalized()
	var sprint := Input.is_key_pressed(KEY_SHIFT) or joy_vec.length() > 0.92
	var ads := ads_held
	var out := {
		"move": mv, "fire": fire_held, "ads": ads, "crouch": crouch_on, "sprint": sprint,
		"dyaw": acc_dyaw, "dpitch": acc_dpitch, "jump": pj, "reload": pr, "pickup": pp,
		"switch": ps, "fire_edge": pfe,
	}
	acc_dyaw = 0.0
	acc_dpitch = 0.0
	pj = false
	pr = false
	pp = false
	ps = false
	pfe = false
	return out

func feed_add(t: String) -> void:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed.add_child(l)
	while feed.get_child_count() > 6:
		feed.get_child(0).queue_free()
	var tw := create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)

func toast(t: String, secs: float = 2.5) -> void:
	toast_lbl.text = t
	toast_lbl.visible = true
	toast_t = secs

func hit_marker(head: bool) -> void:
	hit_t = 0.22
	hit_head = head

func flash_hurt() -> void:
	flash.color.a = 0.35

func _process(delta: float) -> void:
	toast_t -= delta
	if toast_t <= 0.0:
		toast_lbl.visible = false
	hit_t = maxf(0.0, hit_t - delta)
	flash.color.a = maxf(0.0, flash.color.a - delta * 0.8)
	cross.queue_redraw()
	scope.queue_redraw()
	mini.queue_redraw()

func update_match(m: BRMatch, h: Fighter, spect: Fighter) -> void:
	match_ref = m
	human_ref = h
	spect_ref = spect
	alive_lbl.text = "الأحياء: %d / %d" % [m.alive, Cfg.TOTAL_PLAYERS]
	var zone_in := m.zone_contains(h.position) if h != null and h.alive() else true
	zone_warn = not zone_in and h != null and h.alive()
	if m.phase == BRMatch.Phase.PLANE:
		zone_lbl.text = "الطائرة في الطريق — اقفز عندما تريد"
	elif m.phase == BRMatch.Phase.PLAY:
		if m.zone_shrinking:
			zone_lbl.text = "الدائرة تنكمش الآن — نصف القطر %d م" % int(m.zone_r)
		elif m.zone_phase < Cfg.ZONE_PHASES.size():
			zone_lbl.text = "الدائرة القادمة بعد %d ثانية" % int(maxf(0.0, m.zone_timer))
		else:
			zone_lbl.text = "الدائرة نهائية"
	else:
		zone_lbl.text = "انتهت المباراة"
	if h == null:
		return
	var hp_ratio := clampf(h.hp / Cfg.HP_MAX, 0.0, 1.0)
	hp_fill.size = Vector2(256.0 * hp_ratio, 16)
	hp_fill.color = Color(0.3, 0.9, 0.35) if hp_ratio > 0.4 else Color(0.95, 0.35, 0.2)
	hp_lbl.text = "الصحة %d" % int(h.hp)
	var ws: Variant = h.cur_weapon()
	if ws == null:
		wpn_lbl.text = "بدون سلاح — اجمع سلاحاً"
		ammo_lbl.text = ""
	else:
		var W: Dictionary = Cfg.WEAPONS[ws["id"]]
		wpn_lbl.text = "%s  (%s)" % [W["name"], "%d / %d" % [int(ws["mag"]), int(W["mag"])]]
		ammo_lbl.text = "الذخيرة الاحتياطية: %d%s" % [h.ammo_reserve(), "   — جاري التعبئة" if h.reload_t > 0.0 else ""]
		sniper_ads = h.ads and ws["id"] == "sniper"
	ads_now = h.ads and h.state == Fighter.St.GROUND
	scope.visible = sniper_ads
	cross.visible = not sniper_ads
	if h.state == Fighter.St.DEAD:
		banner.text = "أنت خارج المعركة — المركز #%d   |   تشاهد: %s" % [h.place, spect.pname if spect != null else "—"]
	elif h.state == Fighter.St.PLANE:
		banner.text = "اضغط قفز لتنزل من الطائرة" if m.plane_t >= Cfg.PLANE_JUMP_MIN else "انتظر — الطائرة فوق البحر"
	elif h.state == Fighter.St.FALL:
		banner.text = "سقوط حر — المظلة تُفتح قرب الأرض (اضغط قفز لفتحها)"
	elif zone_warn:
		banner.text = "أنت خارج الدائرة! الضرر يتزايد"
	else:
		banner.text = ""

func _draw_cross() -> void:
	var s := cross.size
	var c := s * 0.5
	var col := Color(1, 1, 1, 0.85)
	var gap := 9.0 if not ads_now else 4.0
	cross.draw_line(c + Vector2(-gap - 9, 0), c + Vector2(-gap, 0), col, 2.0)
	cross.draw_line(c + Vector2(gap + 9, 0), c + Vector2(gap, 0), col, 2.0)
	cross.draw_line(c + Vector2(0, -gap - 9), c + Vector2(0, -gap), col, 2.0)
	cross.draw_line(c + Vector2(0, gap + 9), c + Vector2(0, gap), col, 2.0)
	cross.draw_circle(c, 1.5, col)
	if hit_t > 0.0:
		var hc := Color(1.0, 0.25, 0.2) if hit_head else Color(1, 1, 1)
		var r := 16.0
		cross.draw_line(c + Vector2(-r, -r), c + Vector2(-r * 0.5, -r * 0.5), hc, 3.0)
		cross.draw_line(c + Vector2(r, -r), c + Vector2(r * 0.5, -r * 0.5), hc, 3.0)
		cross.draw_line(c + Vector2(-r, r), c + Vector2(-r * 0.5, r * 0.5), hc, 3.0)
		cross.draw_line(c + Vector2(r, r), c + Vector2(r * 0.5, r * 0.5), hc, 3.0)

func _draw_scope() -> void:
	var s := scope.size
	var c := s * 0.5
	var R := minf(s.x, s.y) * 0.42
	var dark := Color(0, 0, 0, 0.92)
	scope.draw_rect(Rect2(Vector2.ZERO, Vector2(s.x, c.y - R)), dark)
	scope.draw_rect(Rect2(Vector2(0, c.y + R), Vector2(s.x, s.y - c.y - R)), dark)
	scope.draw_rect(Rect2(Vector2(0, c.y - R), Vector2(c.x - R, 2 * R)), dark)
	scope.draw_rect(Rect2(Vector2(c.x + R, c.y - R), Vector2(s.x - c.x - R, 2 * R)), dark)
	scope.draw_arc(c, R, 0, TAU, 96, Color(0, 0, 0, 1), 4.0)
	var lc := Color(0, 0, 0, 0.9)
	scope.draw_line(Vector2(c.x - R, c.y), Vector2(c.x + R, c.y), lc, 2.0)
	scope.draw_line(Vector2(c.x, c.y - R), Vector2(c.x, c.y + R), lc, 2.0)
	scope.draw_circle(c, 2.0, Color.RED)

func _draw_joy() -> void:
	if not touch_mode:
		return
	var s := joy_draw.size
	var base := joy_origin if joy_idx >= 0 else Vector2(s.x * 0.16, s.y - 210.0)
	joy_draw.draw_arc(base, 70.0, 0, TAU, 48, Color(1, 1, 1, 0.45), 3.0)
	var knob := base + joy_vec * 70.0 if joy_idx >= 0 else base
	joy_draw.draw_circle(knob, 26.0, Color(1, 1, 1, 0.35))

func _draw_mini() -> void:
	var s := mini.size
	var c := s * 0.5
	var k := (s.x * 0.5 - 4.0) / 1024.0
	mini.draw_circle(c, s.x * 0.5, Color(0.05, 0.1, 0.16, 0.7))
	var land_r := 1000.0 * k
	mini.draw_circle(c, land_r, Color(0.25, 0.45, 0.25, 0.9))
	if match_ref == null:
		return
	var m := match_ref
	for city in m.isl.cities:
		mini.draw_circle(c + Vector2(float(city["x"]), float(city["z"])) * k, 4.0, Color(0.9, 0.9, 0.7))
	mini.draw_arc(c + m.zone_c * k, m.zone_r * k, 0, TAU, 72, Color(0.4, 0.8, 1.0), 2.0)
	if m.phase == BRMatch.Phase.PLANE:
		var a := Cfg.PLANE_A
		var b := Cfg.PLANE_B
		mini.draw_line(c + a * k, c + b * k, Color(1, 1, 1, 0.35), 1.5)
		mini.draw_circle(c + m.plane_pos_2d() * k, 4.0, Color(1, 1, 1))
	if human_ref != null and human_ref.alive() and human_ref.state != Fighter.St.PLANE:
		var p := Vector2(human_ref.position.x, human_ref.position.z) * k
		var f := Vector2(sin(human_ref.yaw), cos(human_ref.yaw))
		var rgt := Vector2(f.y, -f.x)
		var tip := c + p + f * 9.0
		var l := c + p - f * 6.0 + rgt * 5.0
		var r := c + p - f * 6.0 - rgt * 5.0
		mini.draw_colored_polygon(PackedVector2Array([tip, l, r]), Color(1, 0.85, 0.2))
