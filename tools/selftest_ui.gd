extends SceneTree
# اختبار واجهة: تشغيل main.tscn فعلياً مع إدخال لاعب محاكى (قفز، حركة، إطلاق)

var main: Node3D
var frame := 0
var jumped := false
var fails := 0
var max_frames := 6000
var last_state := 0

func _initialize() -> void:
	var ps := load("res://scenes/main.tscn") as PackedScene
	main = ps.instantiate() as Node3D
	root.add_child(main)

func _process(_delta: float) -> bool:
	frame += 1
	if frame > 12000:
		print("UI_TIMEOUT")
		quit(1)
		return true
	if frame == 5:
		main.call("_start_solo")
		print("UI_MATCH_STARTED")
	var m = main.get("match_")
	if m == null:
		return false
	var h = m.human
	var hud = main.get("hud")
	if h == null or hud == null:
		return false
	if h.state != last_state:
		print("UI_STATE %d -> %d pos=%s vel=%s gy=%.1f plane_t=%.2f frame=%d" % [last_state, h.state, str(h.position), str(h.vel), m.isl.height_at(h.position.x, h.position.z), m.plane_t, frame])
		last_state = h.state
	if h.state == Fighter.St.PLANE and m.plane_t > 0.3 and not jumped:
		hud.pj = true
		jumped = true
	if h.state == Fighter.St.GROUND:
		hud.joy_vec = Vector2(0.0, 1.0)
		hud.fire_held = (frame % 90) < 60
		hud.acc_dyaw = 0.004
		if frame % 200 == 0:
			hud.pr = true
		if frame % 150 == 0:
			hud.ads_held = not hud.ads_held
		if frame % 77 == 0:
			hud.crouch_on = not hud.crouch_on
		if frame % 120 == 0:
			hud.pp = true
	if frame % 300 == 0:
		print("UI_TICK frame=%d t=%.1f state=%d hp=%.0f alive=%d plane_t=%.2f banner=%s" % [frame, m.t_match, h.state, h.hp, m.alive, m.plane_t, hud.banner.text])
	if m.over or frame >= max_frames or not h.alive() and frame > 200 and m.over:
		print("UI_END frame=%d over=%s alive=%d human_state=%d place=%d kills=%d" % [frame, str(m.over), m.alive, h.state, h.place, h.kills])
		var ok := frame >= 60 and jumped
		print("UI_SELFTEST ", "PASS" if ok else "FAIL")
		quit(0 if ok else 1)
		return true
	return false
