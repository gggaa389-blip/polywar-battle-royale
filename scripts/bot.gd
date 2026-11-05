class_name BotBrain
extends RefCounted
# ذكاء البوت: القفز من الطائرة في وقت متفرّق، البحث عن الغنائم، الدائرة، القتال

var f: Fighter
var rng := RandomNumberGenerator.new()
var skill := 0.5
var jump_at := 0.5
var goal := Vector3.ZERO
var has_goal := false
var plan_t := 0.0
var react := 0.0
var target: Fighter = null
var strafe := 1.0
var strafe_t := 0.0
var wander_t := 0.0
var crouch_plan := false
var jumped := false
var stuck_t := 0.0
var sample_pos := Vector3.ZERO
var loot_block := 0.0
var want_kind := ""

func _init(p_f: Fighter, seed_v: int) -> void:
	f = p_f
	rng.seed = seed_v
	skill = rng.randf_range(0.35, 0.8)
	jump_at = rng.randf_range(0.24, 0.56)
	strafe = 1.0 if rng.randf() < 0.5 else -1.0

func think(dt: float, m: Node) -> Dictionary:
	var out := {"move": Vector2.ZERO, "fire": false, "ads": false, "jump": false, "sprint": false,
		"reload": false, "pickup": false, "crouch": false, "switch": false, "fire_edge": true, "want": ""}
	plan_t -= dt
	react = maxf(0.0, react - dt)
	strafe_t -= dt
	if strafe_t <= 0.0:
		strafe_t = rng.randf_range(0.6, 1.6)
		strafe = -strafe if rng.randf() < 0.8 else strafe
	match f.state:
		Fighter.St.PLANE:
			if not jumped and m.plane_t >= jump_at:
				jumped = true
				out.jump = true
				goal = _pick_city_goal(m)
				has_goal = true
		Fighter.St.FALL, Fighter.St.CHUTE:
			_face(out, goal)
			out.move = Vector2(0, 1)
		Fighter.St.GROUND:
			_ground(dt, out, m)
		_:
			pass
	return out

func _pick_city_goal(m: Node) -> Vector3:
	var cs: Array = m.isl.cities
	var c: Dictionary = cs[rng.randi() % cs.size()]
	var p := Vector3(float(c["x"]) + rng.randf_range(-40, 40), 0.0, float(c["z"]) + rng.randf_range(-40, 40))
	return p

func _face(out: Dictionary, p: Vector3) -> void:
	var d := p - f.position
	d.y = 0.0
	if d.length() < 0.5:
		return
	out["yaw_set"] = atan2(d.x, d.z)

func _ground(dt: float, out: Dictionary, m: Node) -> void:
	loot_block = maxf(0.0, loot_block - dt)
	stuck_t += dt
	if stuck_t >= 1.5:
		stuck_t = 0.0
		if has_goal and target == null and f.position.distance_to(sample_pos) < 1.0:
			# عالق (جدار مثلاً): تجاهل الغنيمة لفترة واختر نقطة عشوائية
			loot_block = 8.0
			has_goal = false
		sample_pos = f.position
	if plan_t <= 0.0:
		plan_t = 0.25 + rng.randf() * 0.15
		_plan(m)
	if target != null and not target.alive():
		target = null
	if target != null:
		var dv := target.eye() - f.eye()
		var hd := Vector2(dv.x, dv.z).length()
		var want_yaw := atan2(dv.x, dv.z)
		var err := absf(wrapf(want_yaw - f.yaw, -PI, PI))
		var aim_jit := (1.0 - skill) * 0.12
		out["yaw_set"] = want_yaw + rng.randf_range(-aim_jit, aim_jit)
		out["pitch_set"] = atan2(dv.y, maxf(hd, 0.01))
		var W: Dictionary = Cfg.WEAPONS[f.weapon_id()] if f.weapon_id() != "" else {}
		var rng_w := float(W.get("range", 100.0))
		if err < 0.16 and react <= 0.0 and hd < rng_w * 0.9 and f.reload_t <= 0.0:
			out["fire"] = true
		out["ads"] = hd > 45.0 and rng_w > 150.0
		out["crouch"] = crouch_plan
		if hd > 22.0:
			out["move"] = Vector2(strafe * 0.6, 0.6)
		elif hd < 9.0:
			out["move"] = Vector2(strafe * 0.5, -0.5)
		else:
			out["move"] = Vector2(strafe * 0.9, 0.0)
		out["sprint"] = false
	else:
		# بدون هدف: الغنائم أو الدائرة أو التجوال
		if has_goal:
			var d := goal - f.position
			d.y = 0.0
			if d.length() > 1.6:
				out["yaw_set"] = atan2(d.x, d.z)
				out["move"] = Vector2(0, 1)
				out["sprint"] = d.length() > 40.0
			else:
				has_goal = false
		out["crouch"] = false
		out["ads"] = false
	if want_kind != "" and m.find_loot(f, 1.9, want_kind).size() > 0:
		out["pickup"] = true
		out["want"] = want_kind
	if f.weapon_id() == "" and not has_goal and target == null:
		out["move"] = Vector2(0, 1)
		out["yaw_set"] = wander_yaw(dt)

func wander_yaw(dt: float) -> float:
	wander_t -= dt
	if wander_t <= 0.0:
		wander_t = rng.randf_range(2.0, 4.0)
		return f.yaw + rng.randf_range(-PI * 0.7, PI * 0.7)
	return f.yaw

func _plan(m: Node) -> void:
	# قرار كل 0.25 ثانية تقريباً
	var zone_ok: bool = m.zone_contains(f.position)
	var prev := target
	target = m.nearest_enemy(f, 85.0) if f.weapon_id() != "" else null
	if target != null and prev == null:
		react = 0.3 + (1.0 - skill) * 0.4
	crouch_plan = target != null and rng.randf() < 0.15 and f.position.distance_to(target.position) > 30.0
	if not zone_ok:
		want_kind = ""
		goal = Vector3(m.zone_c.x, 0.0, m.zone_c.y)
		has_goal = true
		return
	if target != null:
		has_goal = false
		want_kind = ""
		return
	# بحث عن غنيمة
	var want := "ammo"
	if f.weapon_id() == "":
		want = "weapon"
	elif f.hp < 70.0:
		want = "med"
	elif f.ammo_reserve() < 15:
		want = "ammo"
	elif f.has_empty_slot():
		want = "weapon"
	want_kind = want
	var found: Dictionary = {} if loot_block > 0.0 else m.find_loot(f, 110.0, want)
	if found.size() > 0:
		goal = found["pos"]
		has_goal = true
	elif not has_goal or f.position.distance_to(goal) < 3.0:
		var a := rng.randf() * TAU
		var r := rng.randf_range(40.0, 140.0)
		goal = f.position + Vector3(cos(a) * r, 0, sin(a) * r)
		goal.x = clampf(goal.x, -900.0, 900.0)
		goal.z = clampf(goal.z, -900.0, 900.0)
		has_goal = true
