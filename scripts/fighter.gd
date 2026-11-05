class_name Fighter
extends Node3D
# لاعب (بشري أو بوت): الطائرة، القفز الحر، المظلة، الأرض، الأسلحة، الضرر

enum St { PLANE, FALL, CHUTE, GROUND, DEAD }

var id := 0
var pname := ""
var human := false
var hp: float = 100.0
var state: int = St.PLANE
var vel := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var crouch := false
var ads := false
var kills := 0
var slots: Array = [null, null]     # null أو {"id": String, "mag": int}
var cur := 0
var ammo := {"9mm": 0, "556": 0, "12g": 0, "762": 0}
var fire_t := 0.0
var reload_t := 0.0
var place := 0
var hit_t := 0.0
var last_move := 0.0
var moving := false
var plane_offset := Vector3.ZERO
var model: Node3D
var gun: MeshInstance3D
var chute_node: Node3D
var label: Label3D
var anim: AnimationPlayer
var cur_anim := ""
var grounded := false
var dead_t := 0.0
var net_target := Vector3.ZERO
var net_yaw := 0.0
var net_pitch := 0.0

static var char_scene: PackedScene

func setup(p_id: int, p_name: String, p_human: bool, col: Color) -> void:
	id = p_id
	pname = p_name
	human = p_human
	if char_scene == null:
		char_scene = load("res://assets/models/character.glb")
	model = char_scene.instantiate() as Node3D
	model.name = "model"
	add_child(model)
	_tint(model, col)
	anim = _find_anim(model)
	if anim != null:
		for an in anim.get_animation_list():
			var a := anim.get_animation(an)
			a.loop_mode = Animation.LOOP_NONE if String(an) in Cfg.NON_LOOP else Animation.LOOP_LINEAR
	# مسدس/بندقية مرئية في اليد
	gun = MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.09, 0.14, 0.55)
	gun.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.1, 0.1, 0.12)
	gun.material_override = gmat
	gun.position = Vector3(0.28, 1.05, 0.35)
	gun.visible = false
	add_child(gun)
	# مظلة مرئية
	chute_node = Node3D.new()
	chute_node.visible = false
	add_child(chute_node)
	var cm := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.2
	sm.height = 2.2
	cm.mesh = sm
	cm.scale = Vector3(1.0, 0.45, 1.0)
	cm.position = Vector3(0, 3.6, 0)
	var chm := StandardMaterial3D.new()
	chm.albedo_color = col.lightened(0.35)
	cm.material_override = chm
	chute_node.add_child(cm)
	# اسم اللاعب
	label = Label3D.new()
	label.text = pname
	label.font_size = 36
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, 2.25, 0)
	label.modulate = Color(1, 1, 1, 0.95) if p_human else Color(0.9, 0.9, 0.9, 0.7)
	add_child(label)
	_play("Idle")

func _tint(n: Node, col: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			return
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i)
			if mat and String(mat.resource_name).to_lower().contains("character_main"):
				var m2 := mat.duplicate() as StandardMaterial3D
				if m2:
					m2.albedo_color = col
					mi.set_surface_override_material(i, m2)
	for c in n.get_children():
		_tint(c, col)

func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null

func _play(nm: String) -> void:
	if anim == null or cur_anim == nm:
		return
	if anim.has_animation(nm):
		anim.play(nm, 0.15)
		cur_anim = nm

func alive() -> bool:
	return state != St.DEAD

func eye() -> Vector3:
	return position + Vector3(0, 1.05 if crouch else 1.45, 0)

func fwd_h() -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))

func right_h() -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))

func aim_dir() -> Vector3:
	var cp := cos(pitch)
	return Vector3(sin(yaw) * cp, sin(pitch), cos(yaw) * cp)

func cur_weapon() -> Variant:
	return slots[cur]

func weapon_id() -> String:
	var s: Variant = slots[cur]
	return String(s["id"]) if s != null else ""

func has_empty_slot() -> bool:
	return slots[0] == null or slots[1] == null

func give_weapon(wid: String, mag: int) -> Variant:
	# يعيد السلاح المستبدل (إن وُجد) ليُسقط على الأرض
	var entry := {"id": wid, "mag": mag}
	if slots[cur] == null:
		slots[cur] = entry
		return null
	if slots[1 - cur] == null:
		slots[1 - cur] = entry
		return null
	var old: Variant = slots[cur]
	slots[cur] = entry
	reload_t = 0.0
	return old

func add_ammo(t: String, n: int) -> int:
	var before: int = int(ammo.get(t, 0))
	ammo[t] = mini(Cfg.AMMO_CAP, before + n)
	return int(ammo[t]) - before

func ammo_reserve() -> int:
	var s: Variant = slots[cur]
	if s == null:
		return 0
	return int(ammo.get(Cfg.WEAPONS[s["id"]]["ammo"], 0))

func heal(n: float) -> void:
	hp = minf(Cfg.HP_MAX, hp + n)

func hurt(dmg: float, by: int) -> bool:
	if state == St.DEAD:
		return false
	hp -= dmg
	hit_t = 0.25
	if hp <= 0.0:
		hp = 0.0
		die_now()
		return true
	return false

func die_now() -> void:
	state = St.DEAD
	reload_t = 0.0
	fire_t = 0.0
	ads = false
	gun.visible = false
	chute_node.visible = false
	label.visible = false
	_play("Death")

func step(dt: float, inp: Dictionary, isl: Island, m: Node) -> Array:
	# يعيد قائمة الطلقات المُطلقة هذا الإطار
	var shots: Array = []
	if state == St.DEAD:
		dead_t += dt
		return shots
	if inp.has("dyaw"):
		yaw += float(inp["dyaw"])
	if inp.has("dpitch"):
		pitch = clampf(pitch + float(inp["dpitch"]), -1.2, 1.0)
	if inp.has("yaw_set"):
		yaw = lerp_angle(yaw, float(inp["yaw_set"]), clampf(dt * 10.0, 0.0, 1.0))
	if inp.has("pitch_set"):
		pitch = lerpf(pitch, clampf(float(inp["pitch_set"]), -1.2, 1.0), clampf(dt * 10.0, 0.0, 1.0))
	hit_t = maxf(0.0, hit_t - dt)
	fire_t = maxf(0.0, fire_t - dt)
	var mv: Vector2 = inp.get("move", Vector2.ZERO)
	if mv.length() > 1.0:
		mv = mv.normalized()
	var wish := fwd_h() * mv.y + right_h() * mv.x
	last_move = mv.length()
	match state:
		St.FALL:
			_fall(dt, wish, inp, isl)
		St.CHUTE:
			_chute(dt, wish, inp, isl)
		St.GROUND:
			if inp.has("switch") and bool(inp["switch"]):
				cur = 1 - cur
				reload_t = 0.0
			crouch = bool(inp.get("crouch", crouch))
			ads = bool(inp.get("ads", false))
			_ground(dt, wish, inp, isl)
			shots = _weapon_tick(dt, inp, m)
	_update_model(dt)
	return shots

func _fall(dt: float, wish: Vector3, inp: Dictionary, isl: Island) -> void:
	vel.y = maxf(vel.y - Cfg.FREEFALL_ACC * dt, -Cfg.FREEFALL_MAX)
	vel.x = lerpf(vel.x, wish.x * 9.0, clampf(dt * 1.2, 0.0, 1.0))
	vel.z = lerpf(vel.z, wish.z * 9.0, clampf(dt * 1.2, 0.0, 1.0))
	position += vel * dt
	position.x = clampf(position.x, -Cfg.MAP_HALF + 2.0, Cfg.MAP_HALF - 2.0)
	position.z = clampf(position.z, -Cfg.MAP_HALF + 2.0, Cfg.MAP_HALF - 2.0)
	var gy := isl.height_at(position.x, position.z)
	if (bool(inp.get("jump", false)) or (position.y - gy) < Cfg.CHUTE_OPEN_ALT) and position.y > gy + 1.0:
		_open_chute()
	if position.y <= gy + 0.05:
		_land(gy)

func _open_chute() -> void:
	state = St.CHUTE
	chute_node.visible = true
	vel.y = -Cfg.CHUTE_FALL

func _chute(dt: float, wish: Vector3, _inp: Dictionary, isl: Island) -> void:
	vel.y = -Cfg.CHUTE_FALL
	vel.x = lerpf(vel.x, wish.x * 7.0, clampf(dt * 2.0, 0.0, 1.0))
	vel.z = lerpf(vel.z, wish.z * 7.0, clampf(dt * 2.0, 0.0, 1.0))
	position += vel * dt
	position.x = clampf(position.x, -Cfg.MAP_HALF + 2.0, Cfg.MAP_HALF - 2.0)
	position.z = clampf(position.z, -Cfg.MAP_HALF + 2.0, Cfg.MAP_HALF - 2.0)
	var gy := isl.height_at(position.x, position.z)
	if position.y <= gy + 0.05:
		_land(gy)

func _land(gy: float) -> void:
	state = St.GROUND
	position.y = gy
	vel = Vector3.ZERO
	chute_node.visible = false
	grounded = true
	_play("Jump_Land")

func _ground(dt: float, wish: Vector3, inp: Dictionary, isl: Island) -> void:
	var sp := Cfg.WALK
	var wants_sprint := bool(inp.get("sprint", false)) and wish.length() > 0.1
	if wants_sprint and not crouch and not ads:
		sp = Cfg.RUN
	if crouch:
		sp *= Cfg.CROUCH_MUL
	if ads:
		sp *= Cfg.ADS_MUL
	var mv := wish
	if mv.length() > 1.0:
		mv = mv.normalized()
	moving = mv.length() > 0.05
	var nx := position.x + mv.x * sp * dt
	var nz := position.z + mv.z * sp * dt
	var r := Cfg.FIGHTER_R
	var gy_here := isl.height_at(position.x, position.z)
	# حركة منفصلة للمحور X و Z للانزلاق على الجدران
	if isl.height_at(nx, position.z) > 0.25 and not isl.blocked(nx, position.z, position.y, r):
		position.x = nx
	if isl.height_at(position.x, nz) > 0.25 and not isl.blocked(position.x, nz, position.y, r):
		position.z = nz
	var fixed := isl.push_out(position, r, position.y + 1.8)
	position.x = fixed.x
	position.z = fixed.z
	var gy := isl.height_at(position.x, position.z)
	if gy_here < 0.0 and gy < 0.25:
		gy = gy_here
	# الجاذبية والقفز
	grounded = position.y <= gy + 0.06 and vel.y <= 0.5
	if grounded and bool(inp.get("jump", false)) and not crouch:
		vel.y = Cfg.JUMP_V
		grounded = false
	vel.y -= Cfg.GRAV * dt
	position.y += vel.y * dt
	if position.y <= gy:
		position.y = gy
		vel.y = 0.0
		grounded = true

func _weapon_tick(dt: float, inp: Dictionary, m: Node) -> Array:
	var out: Array = []
	var s: Variant = slots[cur]
	if s == null:
		reload_t = 0.0
		return out
	var W: Dictionary = Cfg.WEAPONS[s["id"]]
	if reload_t > 0.0:
		reload_t -= dt
		if reload_t <= 0.0:
			_finish_reload()
		return out
	if bool(inp.get("reload", false)):
		_start_reload()
		return out
	if int(s["mag"]) <= 0:
		if int(ammo.get(W["ammo"], 0)) > 0:
			_start_reload()
		return out
	var want := bool(inp.get("fire", false))
	if not want or fire_t > 0.0 or state != St.GROUND:
		return out
	if not bool(W["auto"]) and not bool(inp.get("fire_edge", not human)):
		return out
	s["mag"] = int(s["mag"]) - 1
	fire_t = float(W["rate"])
	var spread := float(W["spread"]) * (float(W["ads_spread"]) if ads else 1.0)
	if moving and not ads:
		spread *= 1.6
	var base := aim_dir()
	var o := eye()
	for _i in int(W["pellets"]):
		var jit := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * spread
		var d := (base + jit).normalized()
		out.append({"o": o, "d": d, "w": s["id"], "dmg": float(W["dmg"]), "range": float(W["range"]), "hs": float(W["hs"]), "src": self})
	return out

func _start_reload() -> void:
	var s: Variant = slots[cur]
	if s == null:
		return
	var W: Dictionary = Cfg.WEAPONS[s["id"]]
	if int(s["mag"]) >= int(W["mag"]) or int(ammo.get(W["ammo"], 0)) <= 0:
		return
	if reload_t > 0.0:
		return
	reload_t = float(W["reload"])

func _finish_reload() -> void:
	var s: Variant = slots[cur]
	if s == null:
		return
	var W: Dictionary = Cfg.WEAPONS[s["id"]]
	var t: String = W["ammo"]
	var need := int(W["mag"]) - int(s["mag"])
	var take := mini(need, int(ammo.get(t, 0)))
	s["mag"] = int(s["mag"]) + take
	ammo[t] = int(ammo.get(t, 0)) - take

func _update_model(dt: float) -> void:
	if model == null:
		return
	model.rotation.y = yaw
	model.position.y = lerpf(model.position.y, -0.35 if crouch and state == St.GROUND else 0.0, clampf(dt * 10.0, 0.0, 1.0))
	gun.visible = state == St.GROUND and slots[cur] != null
	gun.position = Vector3(sin(yaw) * 0.35 + cos(yaw) * 0.28, 1.05, cos(yaw) * 0.35 - sin(yaw) * 0.28)
	gun.rotation.y = yaw
	match state:
		St.DEAD:
			_play("Death")
		St.PLANE:
			_play("Idle")
		St.FALL:
			_play("Jump_Idle")
		St.CHUTE:
			_play("Idle")
		St.GROUND:
			var has_w := slots[cur] != null
			if crouch:
				_play("Duck")
			elif not grounded:
				_play("Jump_Idle")
			elif moving:
				if has_w and ads:
					_play("Walk_Shoot")
				elif has_w:
					_play("Run_Gun")
				elif ads:
					_play("Walk")
				else:
					_play("Run")
			else:
				if has_w and fire_t > 0.05:
					_play("Idle_Shoot")
				else:
					_play("Idle")
