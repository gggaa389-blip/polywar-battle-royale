class_name BRMatch
extends Node3D
# مباراة الباتل رويال: الطائرة، القفز، الدائرة، الغنائم، إطلاق النار، الفوز

enum Phase { PLANE, PLAY, OVER }

const TEAM_COLORS := [
	Color(0.92, 0.35, 0.3), Color(0.3, 0.6, 0.95), Color(0.95, 0.8, 0.25), Color(0.4, 0.85, 0.5),
	Color(0.8, 0.45, 0.9), Color(0.95, 0.55, 0.2), Color(0.55, 0.9, 0.9), Color(0.85, 0.85, 0.85),
]
const BOT_NAMES := ["ليث", "سارة", "عمر", "نور", "خالد", "ريم", "يوسف", "لينا", "زيد", "هدى",
	"سامي", "مريم", "كريم", "ياسمين", "باسل", "دينا", "طارق", "رنا", "وليد", "غادة",
	"حسام", "سلمى", "ماجد", "منى", "فادي", "هبة", "عادل", "ندى", "رامي", "جنى",
	"إياد", "لمى", "بلال", "أسيل", "ناصر", "رزان", "سليم", "تالا", "معاذ", "شذى",
	"أنس", "ميسم", "قيس", "غيداء", "فارس", "لارا", "نادر", "ريان", "يزن", "بتول"]
const LCELL := 32.0

var isl: Island
var fighters: Array = []
var brains: Array = []
var human: Fighter = null
var phase: int = Phase.PLANE
var t_match := 0.0
var plane_t := 0.0
var plane_pos := Vector3.ZERO
var plane_dir := Vector3.ZERO
var plane_len := 1.0
var plane_node: Node3D
var zone_c := Vector2.ZERO
var zone_r: float = Cfg.ZONE_START_R
var zone_from_c := Vector2.ZERO
var zone_from_r: float = Cfg.ZONE_START_R
var zone_to_c := Vector2.ZERO
var zone_to_r: float = Cfg.ZONE_START_R
var zone_phase := 0
var zone_timer: float = Cfg.ZONE_WAIT_FIRST
var zone_shrinking := false
var shrink_t := 0.0
var shrink_total := 1.0
var zone_node: MeshInstance3D
var zone_mesh: CylinderMesh
var loot: Array = []
var lgrid := {}
var events: Array = []
var alive := 0
var over := false
var winner: Fighter = null
var rng := RandomNumberGenerator.new()
var fx_root: Node3D
var loot_root: Node3D
var people_root: Node3D
var stats := {"shots": 0, "hits": 0, "kills": 0, "head": 0}
var is_client := false
var remote_inputs := {}
var next_uid := 1
var loot_by_uid := {}
var net_phase_hdr := 0

func setup(p_isl: Island, human_count: int, names: PackedStringArray, seed_v: int, my_slot: int) -> void:
	isl = p_isl
	rng.seed = seed_v
	people_root = Node3D.new()
	people_root.name = "People"
	add_child(people_root)
	loot_root = Node3D.new()
	loot_root.name = "Loot"
	add_child(loot_root)
	fx_root = Node3D.new()
	fx_root.name = "Fx"
	add_child(fx_root)
	var n := Cfg.TOTAL_PLAYERS
	for i in n:
		var is_h := i < human_count
		var f := Fighter.new()
		f.name = "F%02d" % i
		var pname: String = String(names[i]) if i < names.size() else String(BOT_NAMES[i % BOT_NAMES.size()])
		people_root.add_child(f)
		f.setup(i, pname, is_h, TEAM_COLORS[i % TEAM_COLORS.size()])
		f.plane_offset = Vector3(rng.randf_range(-6.0, 6.0), 0.0, rng.randf_range(-6.0, 6.0))
		fighters.append(f)
		brains.append(null if is_h else BotBrain.new(f, seed_v * 131 + i))
		if i == my_slot:
			human = f
	alive = n
	_build_plane()
	_build_zone()
	_spawn_loot()
	events.clear()

func start() -> void:
	phase = Phase.PLANE
	plane_t = 0.0
	_update_plane_pos()

func _build_plane() -> void:
	plane_node = Node3D.new()
	add_child(plane_node)
	var a := Cfg.PLANE_A
	var b := Cfg.PLANE_B
	plane_dir = Vector3(b.x - a.x, 0.0, b.y - a.y).normalized()
	plane_len = Vector2(b.x - a.x, b.y - a.y).length()
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.6, 2.4, 11.0)
	body.mesh = bm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.85, 0.85, 0.9)
	body.material_override = wm
	plane_node.add_child(body)
	var wing := MeshInstance3D.new()
	var wbm := BoxMesh.new()
	wbm.size = Vector3(18.0, 0.3, 2.4)
	wing.mesh = wbm
	wing.position = Vector3(0, -0.2, 0.5)
	var wg := StandardMaterial3D.new()
	wg.albedo_color = Color(0.3, 0.35, 0.45)
	wing.material_override = wg
	plane_node.add_child(wing)
	var tail := MeshInstance3D.new()
	var tbm := BoxMesh.new()
	tbm.size = Vector3(6.0, 0.25, 1.6)
	tail.mesh = tbm
	tail.position = Vector3(0, 0.2, -4.6)
	tail.material_override = wg
	plane_node.add_child(tail)

func _update_plane_pos() -> void:
	var a := Cfg.PLANE_A
	var b := Cfg.PLANE_B
	var p := a.lerp(b, plane_t)
	plane_pos = Vector3(p.x, Cfg.PLANE_ALT, p.y)
	plane_node.position = plane_pos
	plane_node.rotation.y = atan2(plane_dir.x, plane_dir.z)
	plane_node.visible = plane_t < 1.0

func _build_zone() -> void:
	zone_node = MeshInstance3D.new()
	zone_mesh = CylinderMesh.new()
	zone_mesh.height = 160.0
	zone_mesh.top_radius = zone_r
	zone_mesh.bottom_radius = zone_r
	zone_mesh.radial_segments = 72
	zone_mesh.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.55, 1.0, 0.22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	zone_node.mesh = zone_mesh
	zone_node.material_override = mat
	add_child(zone_node)

func _wpick(weights: Dictionary) -> String:
	var tot := 0.0
	for k in weights:
		tot += float(weights[k])
	var r := rng.randf() * tot
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return String(k)
	return String(weights.keys()[0])

func _spawn_loot() -> void:
	var wpn := {"pistol": 0.3, "smg": 0.22, "ar": 0.22, "shotgun": 0.14, "sniper": 0.12}
	var amm := {"9mm": 0.4, "556": 0.3, "12g": 0.15, "762": 0.15}
	for p in isl.loot_spots:
		var roll := rng.randf()
		if roll < 0.2:
			var wid := _wpick(wpn)
			_add_loot(p, "weapon", wid, int(Cfg.WEAPONS[wid]["mag"]))
		elif roll < 0.42:
			var at := _wpick(amm)
			_add_loot(p, "ammo", at, int(Cfg.AMMO_BOX[at]))
		elif roll < 0.5:
			_add_loot(p, "med", "medkit", 1)
		elif roll < 0.6:
			_add_loot(p, "band", "bandage", 1)

func _add_loot(p: Vector3, kind: String, id: String, n: int) -> void:
	var uid := next_uid
	next_uid += 1
	_create_loot(uid, p, kind, id, n)
	events.append({"t": "loot_add", "u": uid, "k": kind, "i": id, "n": n, "p": p})

func _create_loot(uid: int, p: Vector3, kind: String, id: String, n: int) -> LootItem:
	var li := LootItem.make(loot_root, kind, id, n, p)
	li.uid = uid
	loot.append(li)
	loot_by_uid[uid] = li
	var k := _lkey(li.position)
	if not lgrid.has(k):
		lgrid[k] = []
	(lgrid[k] as Array).append(li)
	return li

func _remove_loot(li: LootItem) -> void:
	loot.erase(li)
	loot_by_uid.erase(li.uid)
	var k := _lkey(li.position)
	if lgrid.has(k):
		(lgrid[k] as Array).erase(li)
	events.append({"t": "loot_gone", "u": li.uid})
	li.queue_free()

func _remove_loot_uid(uid: int) -> void:
	if not loot_by_uid.has(uid):
		return
	var li: LootItem = loot_by_uid[uid]
	loot.erase(li)
	loot_by_uid.erase(uid)
	var k := _lkey(li.position)
	if lgrid.has(k):
		(lgrid[k] as Array).erase(li)
	li.queue_free()

func _lkey(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / LCELL)), int(floor(p.z / LCELL)))

func loot_near(p: Vector3, rad: float) -> Array:
	var out: Array = []
	var k0 := _lkey(Vector3(p.x - rad, 0, p.z - rad))
	var k1 := _lkey(Vector3(p.x + rad, 0, p.z + rad))
	for ix in range(k0.x, k1.x + 1):
		for iz in range(k0.y, k1.y + 1):
			var k := Vector2i(ix, iz)
			if lgrid.has(k):
				out.append_array(lgrid[k])
	return out

func _want_ok(li: LootItem, want: String, types: Dictionary) -> bool:
	match want:
		"weapon":
			return li.kind == "weapon"
		"ammo":
			return li.kind == "ammo" and types.has(li.id)
		"med":
			return li.kind == "med" or li.kind == "band"
	return true

func find_loot(f: Fighter, rad: float, want: String) -> Dictionary:
	var types := {}
	for s in f.slots:
		if s != null:
			types[Cfg.WEAPONS[s["id"]]["ammo"]] = true
	var best := {}
	var bd := rad * rad
	for li in loot_near(f.position, rad):
		if not _want_ok(li, want, types):
			continue
		var dd := Vector2(li.position.x - f.position.x, li.position.z - f.position.z).length_squared()
		if dd < bd:
			bd = dd
			best = {"pos": li.position, "node": li}
	return best

func zone_contains(p: Vector3) -> bool:
	return Vector2(p.x - zone_c.x, p.z - zone_c.y).length() <= zone_r

func los(a: Vector3, b: Vector3) -> bool:
	var L := a.distance_to(b)
	var steps := int(L / 3.0) + 1
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / float(steps))
		if p.y < isl.height_at(p.x, p.z) + 0.1:
			return false
		if isl.solid_at(p.x, p.y, p.z):
			return false
	return true

func nearest_enemy(f: Fighter, rad: float) -> Fighter:
	var best: Fighter = null
	var bd := rad * rad
	var me := f.eye()
	for o in fighters:
		var of: Fighter = o
		if of == f or not of.alive() or of.state == Fighter.St.PLANE:
			continue
		var dd := Vector2(of.position.x - f.position.x, of.position.z - f.position.z).length_squared()
		if dd < bd and los(me, of.eye()):
			bd = dd
			best = of
	return best

func spectate_target() -> Fighter:
	var best: Fighter = null
	var bd := 1e18
	for o in fighters:
		var of: Fighter = o
		if not of.alive() or of.state == Fighter.St.PLANE:
			continue
		if human != null:
			var dd := of.position.distance_squared_to(human.position)
			if dd < bd:
				bd = dd
				best = of
		else:
			return of
	return best

func merge_remote(slot: int, d: PackedFloat32Array) -> void:
	# مدخلات لاعب بعيد (الشبكة): تُجمع حتى الإطار التالي للمضيف
	if slot < 0 or slot >= fighters.size() or d.size() < 10:
		return
	var e: Dictionary = remote_inputs.get(slot, {"dyaw": 0.0, "dpitch": 0.0})
	e["move"] = Vector2(d[0], d[1])
	e["fire"] = d[2] > 0.5
	e["ads"] = d[3] > 0.5
	e["crouch"] = d[4] > 0.5
	e["sprint"] = d[5] > 0.5
	e["dyaw"] = float(e["dyaw"]) + d[6]
	e["dpitch"] = float(e["dpitch"]) + d[7]
	var ed := int(d[8])
	e["jump"] = bool(e.get("jump", false)) or (ed & 1) != 0
	e["reload"] = bool(e.get("reload", false)) or (ed & 2) != 0
	e["pickup"] = bool(e.get("pickup", false)) or (ed & 4) != 0
	e["switch"] = bool(e.get("switch", false)) or (ed & 8) != 0
	e["fire_edge"] = bool(e.get("fire_edge", false)) or (ed & 16) != 0
	remote_inputs[slot] = e

func _clear_remote_edges() -> void:
	for k in remote_inputs:
		var e: Dictionary = remote_inputs[k]
		e["dyaw"] = 0.0
		e["dpitch"] = 0.0
		e["jump"] = false
		e["reload"] = false
		e["pickup"] = false
		e["switch"] = false
		e["fire_edge"] = false

func human_left(slot: int) -> void:
	if slot < 0 or slot >= fighters.size():
		return
	var f: Fighter = fighters[slot]
	f.human = false
	brains[slot] = BotBrain.new(f, 9000 + slot)
	remote_inputs.erase(slot)

func update(dt: float, human_inp: Dictionary) -> void:
	if phase == Phase.OVER:
		return
	if is_client:
		client_tick(dt, human_inp)
		return
	t_match += dt
	var shots: Array = []
	if phase == Phase.PLANE:
		plane_t = minf(1.0, plane_t + Cfg.PLANE_SPEED * dt / plane_len)
		_update_plane_pos()
	for f in fighters:
		var ff: Fighter = f
		if not ff.alive():
			continue
		var inp: Dictionary
		if ff.human:
			if ff == human:
				inp = human_inp
			else:
				inp = remote_inputs.get(ff.id, {})
		else:
			inp = brains[ff.id].think(dt, self)
		if ff.state == Fighter.St.PLANE:
			ff.position = plane_pos + ff.plane_offset
			var can_jump := plane_t >= Cfg.PLANE_JUMP_MIN
			if (bool(inp.get("jump", false)) and can_jump) or plane_t >= Cfg.PLANE_FORCE_T:
				_drop(ff)
			continue
		var s: Array = ff.step(dt, inp, isl, self)
		if ff.human and s.size() > 0:
			events.append({"t": "shot", "src": ff.id})
		shots.append_array(s)
		if bool(inp.get("pickup", false)):
			try_pickup(ff, String(inp.get("want", "")))
	if phase == Phase.PLANE and plane_t >= Cfg.PLANE_FORCE_T:
		phase = Phase.PLAY
		events.append({"t": "drop_end"})
	for s in shots:
		_resolve_shot(s)
	_clear_remote_edges()
	if phase == Phase.PLAY:
		_update_zone(dt)
		_zone_damage(dt)
	_check_win()

func _drop(f: Fighter) -> void:
	f.state = Fighter.St.FALL
	f.position = plane_pos + f.plane_offset
	f.vel = Vector3(plane_dir.x * 12.0, -4.0, plane_dir.z * 12.0)
	f.yaw = atan2(plane_dir.x, plane_dir.z)
	f.pitch = -0.3
	f.hit_t = 0.0
	events.append({"t": "drop", "v": f.id})

func try_pickup(f: Fighter, want_f: String = "") -> bool:
	if f.state != Fighter.St.GROUND:
		return false
	var best: LootItem = null
	var bd := 2.2 * 2.2
	var types := {}
	for s in f.slots:
		if s != null:
			types[Cfg.WEAPONS[s["id"]]["ammo"]] = true
	for li in loot_near(f.position, 2.2):
		var it: LootItem = li
		if want_f != "" and not _want_ok(it, want_f, types):
			continue
		var dd := Vector2(it.position.x - f.position.x, it.position.z - f.position.z).length_squared()
		if dd < bd:
			bd = dd
			best = it
	if best == null:
		return false
	var picked_kind := best.kind
	match best.kind:
		"weapon":
			var dropped: Variant = f.give_weapon(best.id, best.n)
			if dropped != null:
				_add_loot(best.position, "weapon", String(dropped["id"]), int(dropped["mag"]))
			_remove_loot(best)
		"ammo":
			var got := f.add_ammo(best.id, best.n)
			if got <= 0:
				return false
			best.n -= got
			if best.n <= 0:
				_remove_loot(best)
			else:
				best.refresh()
				events.append({"t": "loot_n", "u": best.uid, "n": best.n})
		"med":
			if f.hp >= Cfg.HP_MAX - 0.5:
				return false
			f.heal(50.0)
			_remove_loot(best)
			events.append({"t": "heal", "v": f.id})
		"band":
			if f.hp >= Cfg.HP_MAX - 0.5:
				return false
			f.heal(25.0)
			_remove_loot(best)
			events.append({"t": "heal", "v": f.id})
	events.append({"t": "pick", "v": f.id, "kind": picked_kind})
	return true

func _resolve_shot(s: Dictionary) -> void:
	var o: Vector3 = s["o"]
	var d: Vector3 = s["d"]
	var rmax: float = s["range"]
	var src: Fighter = s["src"]
	stats["shots"] = int(stats["shots"]) + 1
	var best := rmax
	var hit_f: Fighter = null
	var head := false
	for f in fighters:
		var ff: Fighter = f
		if ff == src or not ff.alive() or ff.state == Fighter.St.PLANE:
			continue
		var r := _ray_capsule(o, d, ff)
		if r.x > 0.0 and r.x < best:
			best = r.x
			hit_f = ff
			head = r.y > 0.5
	var block_t := _march(o, d, best)
	var end_p := o + d * best
	if block_t >= 0.0 and block_t < best:
		hit_f = null
		best = block_t
		end_p = o + d * block_t
		Fx.spark(fx_root, end_p)
	var tr_end := o + d * minf(rmax, 300.0) if hit_f == null and block_t < 0.0 else end_p
	Fx.tracer(fx_root, o + d * 1.2, tr_end)
	events.append({"t": "tr", "a": o + d * 1.2, "b": tr_end, "src": src.id})
	if hit_f == null:
		return
	stats["hits"] = int(stats["hits"]) + 1
	var W: Dictionary = Cfg.WEAPONS[s["w"]]
	var dmg := float(s["dmg"])
	if head:
		dmg *= float(s["hs"])
		stats["head"] = int(stats["head"]) + 1
	Fx.blood_burst(fx_root, end_p, head)
	var died := hit_f.hurt(dmg, src.id)
	events.append({"t": "hit", "src": src.id, "v": hit_f.id, "hs": head, "dmg": dmg})
	events.append({"t": "blood", "p": end_p, "hs": head})
	if died:
		_on_death(hit_f, src, head)

func _ray_capsule(o: Vector3, d: Vector3, f: Fighter) -> Vector2:
	var pos := f.position
	var top := pos.y + (1.2 if f.crouch else 1.85)
	var bot := pos.y + 0.1
	var R := 0.4
	var ox := o.x - pos.x
	var oz := o.z - pos.z
	var a := d.x * d.x + d.z * d.z
	if a < 1e-8:
		return Vector2(-1.0, 0.0)
	var b := 2.0 * (ox * d.x + oz * d.z)
	var c := ox * ox + oz * oz - R * R
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return Vector2(-1.0, 0.0)
	var sq := sqrt(disc)
	var t := (-b - sq) / (2.0 * a)
	if t < 0.0:
		t = (-b + sq) / (2.0 * a)
		if t < 0.0:
			return Vector2(-1.0, 0.0)
	var y := o.y + d.y * t
	if y < bot or y > top:
		return Vector2(-1.0, 0.0)
	var head := y > top - 0.42
	return Vector2(t, 1.0 if head else 0.0)

func _march(o: Vector3, d: Vector3, tmax: float) -> float:
	var t := 0.8
	while t < tmax:
		var p := o + d * t
		var gy := isl.height_at(p.x, p.z)
		if gy > 0.0 and p.y < gy:
			return t
		if p.y < 8.0 and isl.solid_at(p.x, p.y, p.z):
			return t
		t += 0.9
	return -1.0

func _on_death(f: Fighter, src: Fighter, head: bool) -> void:
	var before := alive
	alive -= 1
	f.place = before
	if src != null:
		src.kills += 1
		stats["kills"] = int(stats["kills"]) + 1
	Fx.blood_pool(fx_root, f.position, isl.height_at(f.position.x, f.position.z))
	_drop_loot(f)
	events.append({"t": "kill", "a": src.id if src != null else -1, "v": f.id, "hs": head, "place": before})
	if f.human:
		events.append({"t": "you_out", "place": before, "v": f.id})

func _drop_loot(f: Fighter) -> void:
	for s in f.slots:
		if s != null:
			var p := f.position + Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
			_add_loot(Vector3(p.x, isl.height_at(p.x, p.z), p.z), "weapon", String(s["id"]), int(s["mag"]))
	for t in f.ammo.keys():
		var n := int(f.ammo[t])
		if n > 0:
			var p := f.position + Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
			_add_loot(Vector3(p.x, isl.height_at(p.x, p.z), p.z), "ammo", String(t), n)
			f.ammo[t] = 0
	f.slots = [null, null]

func _update_zone(dt: float) -> void:
	if zone_phase >= Cfg.ZONE_PHASES.size():
		return
	if not zone_shrinking:
		zone_timer -= dt
		if zone_timer <= 0.0:
			var ph: Dictionary = Cfg.ZONE_PHASES[zone_phase]
			zone_shrinking = true
			shrink_t = 0.0
			shrink_total = float(ph["shrink"])
			zone_from_c = zone_c
			zone_from_r = zone_r
			zone_to_r = float(ph["r"])
			var span := zone_from_r - zone_to_r
			var a := rng.randf() * TAU
			var rr := rng.randf() * maxf(0.0, span - 4.0)
			zone_to_c = zone_from_c + Vector2(cos(a), sin(a)) * rr
			events.append({"t": "zone"})
	else:
		shrink_t += dt
		var k := clampf(shrink_t / shrink_total, 0.0, 1.0)
		zone_r = lerpf(zone_from_r, zone_to_r, k)
		zone_c = zone_from_c.lerp(zone_to_c, k)
		if k >= 1.0:
			zone_shrinking = false
			zone_phase += 1
			if zone_phase < Cfg.ZONE_PHASES.size():
				zone_timer = float(Cfg.ZONE_PHASES[zone_phase]["wait"])
	zone_mesh.top_radius = zone_r
	zone_mesh.bottom_radius = zone_r
	zone_node.position = Vector3(zone_c.x, 80.0, zone_c.y)

func zone_dps() -> float:
	var idx := mini(zone_phase, Cfg.ZONE_PHASES.size() - 1)
	return float(Cfg.ZONE_PHASES[idx]["dps"])

func _zone_damage(dt: float) -> void:
	var dps := zone_dps()
	for f in fighters:
		var ff: Fighter = f
		if not ff.alive() or ff.state == Fighter.St.PLANE or ff.state == Fighter.St.FALL:
			continue
		if not zone_contains(ff.position):
			if ff.hurt(dps * dt, -1):
				_on_death(ff, null, false)

func _check_win() -> void:
	if over or phase == Phase.PLANE:
		return
	if alive > 1:
		return
	over = true
	phase = Phase.OVER
	for f in fighters:
		var ff: Fighter = f
		if ff.alive():
			winner = ff
			ff.place = 1
	events.append({"t": "over", "winner": winner.id if winner != null else -1})

func plane_pos_2d() -> Vector2:
	return Vector2(plane_pos.x, plane_pos.z)

# ---------- الشبكة: ترميز اللقطات (المضيف) ----------

func _bits_of(f: Fighter) -> int:
	var b := int(f.state) & 7
	if f.crouch:
		b |= 8
	if f.ads:
		b |= 16
	if f.moving:
		b |= 32
	if f.fire_t > 0.05:
		b |= 64
	if f.grounded:
		b |= 128
	if f.cur == 1:
		b |= 256
	if f.reload_t > 0.0:
		b |= 512
	return b

func _wid_index(s: Variant) -> int:
	if s == null:
		return 0
	return maxi(0, Cfg.WEAPON_IDS.find(String(s["id"])))

func build_snapshot_base() -> PackedFloat32Array:
	var H := Cfg.NET_SNAP_HEADER
	var S := Cfg.NET_SNAP_STRIDE
	var d := PackedFloat32Array()
	d.resize(H + fighters.size() * S)
	d[0] = plane_t
	d[1] = zone_c.x
	d[2] = zone_c.y
	d[3] = zone_r
	d[4] = zone_phase
	d[5] = 1.0 if zone_shrinking else 0.0
	d[6] = zone_timer
	d[7] = alive
	d[8] = float(phase)
	for i in fighters.size():
		var f: Fighter = fighters[i]
		var b := H + i * S
		d[b] = f.position.x
		d[b + 1] = f.position.y
		d[b + 2] = f.position.z
		d[b + 3] = f.yaw
		d[b + 4] = f.pitch
		d[b + 5] = f.hp
		d[b + 6] = float(_bits_of(f))
		d[b + 7] = float(_wid_index(f.slots[0]) + 6 * _wid_index(f.slots[1]))
	return d

func build_tail(slot: int) -> PackedFloat32Array:
	var t := PackedFloat32Array()
	t.resize(Cfg.NET_TAIL)
	if slot < 0 or slot >= fighters.size():
		return t
	var f: Fighter = fighters[slot]
	t[0] = f.ammo["9mm"]
	t[1] = f.ammo["556"]
	t[2] = f.ammo["12g"]
	t[3] = f.ammo["762"]
	t[4] = float(f.slots[0]["mag"]) if f.slots[0] != null else 0.0
	t[5] = float(f.slots[1]["mag"]) if f.slots[1] != null else 0.0
	t[6] = f.reload_t
	t[7] = f.kills
	t[8] = f.place
	t[9] = f.vel.x
	t[10] = f.vel.y
	t[11] = f.vel.z
	return t

# ---------- الشبكة: العميل ----------

func apply_snapshot(d: PackedFloat32Array, my_slot: int) -> void:
	var H := Cfg.NET_SNAP_HEADER
	var S := Cfg.NET_SNAP_STRIDE
	var N := fighters.size()
	if d.size() < H + N * S + Cfg.NET_TAIL:
		return
	plane_t = d[0]
	zone_c = Vector2(d[1], d[2])
	zone_r = d[3]
	zone_phase = int(d[4])
	zone_shrinking = d[5] > 0.5
	zone_timer = d[6]
	alive = int(d[7])
	var ph := int(d[8])
	if phase != Phase.OVER and ph != Phase.OVER:
		phase = ph
	var tb := H + N * S
	for i in N:
		var f: Fighter = fighters[i]
		var b := H + i * S
		var pos := Vector3(d[b], d[b + 1], d[b + 2])
		var bits := int(d[b + 6])
		var st := bits & 7
		var wpn := int(d[b + 7])
		var w0 := wpn % 6
		var w1 := wpn / 6
		f.hp = d[b + 5]
		if i == my_slot:
			f.kills = int(d[tb + 7])
			f.place = int(d[tb + 8])
			f.ammo["9mm"] = int(d[tb])
			f.ammo["556"] = int(d[tb + 1])
			f.ammo["12g"] = int(d[tb + 2])
			f.ammo["762"] = int(d[tb + 3])
			f.reload_t = d[tb + 6]
			f.slots[0] = {"id": Cfg.WEAPON_IDS[w0], "mag": int(d[tb + 4])} if w0 > 0 else null
			f.slots[1] = {"id": Cfg.WEAPON_IDS[w1], "mag": int(d[tb + 5])} if w1 > 0 else null
			var vel := Vector3(d[tb + 9], d[tb + 10], d[tb + 11])
			if st == Fighter.St.DEAD:
				if f.state != Fighter.St.DEAD:
					f.die_now()
			elif f.state == Fighter.St.DEAD:
				pass
			elif st != f.state:
				# تصحيح حالة: المضيف هو المرجع
				f.state = st
				f.position = pos
				f.vel = vel
				f.chute_node.visible = st == Fighter.St.CHUTE
			elif st != Fighter.St.PLANE and f.position.distance_to(pos) > 1.0:
				f.position = pos
				f.vel = vel
		else:
			f.net_target = pos
			f.net_yaw = float(d[b + 3])
			f.net_pitch = float(d[b + 4])
			f.slots[0] = {"id": Cfg.WEAPON_IDS[w0], "mag": 1} if w0 > 0 else null
			f.slots[1] = {"id": Cfg.WEAPON_IDS[w1], "mag": 1} if w1 > 0 else null
			if st == Fighter.St.DEAD:
				if f.state != Fighter.St.DEAD:
					f.die_now()
				continue
			f.state = st
			f.crouch = (bits & 8) != 0
			f.ads = (bits & 16) != 0
			f.moving = (bits & 32) != 0
			f.fire_t = 0.1 if (bits & 64) != 0 else 0.0
			f.grounded = (bits & 128) != 0
			f.cur = (bits >> 8) & 1
			f.chute_node.visible = st == Fighter.St.CHUTE
			if f.state != Fighter.St.PLANE and f.position.distance_to(pos) > 12.0:
				f.position = pos

func client_tick(dt: float, inp: Dictionary) -> void:
	t_match += dt
	if phase == Phase.PLANE:
		_update_plane_pos()
	var k := 1.0 - exp(-dt * 14.0)
	for f in fighters:
		var ff: Fighter = f
		if ff.state == Fighter.St.DEAD:
			ff._update_model(dt)
			continue
		if ff.state == Fighter.St.PLANE:
			ff.position = plane_pos + ff.plane_offset
			ff._update_model(dt)
			continue
		if ff == human:
			var pin := inp.duplicate()
			pin["fire"] = false
			pin["reload"] = false
			pin["pickup"] = false
			ff.step(dt, pin, isl, null)
		else:
			ff.position = ff.position.lerp(ff.net_target, k)
			ff.yaw = lerp_angle(ff.yaw, ff.net_yaw, k)
			ff.pitch = lerpf(ff.pitch, ff.net_pitch, k)
			ff._update_model(dt)
	zone_mesh.top_radius = zone_r
	zone_mesh.bottom_radius = zone_r
	zone_node.position = Vector3(zone_c.x, 80.0, zone_c.y)

func client_fx(e: Dictionary) -> void:
	match String(e["t"]):
		"tr":
			Fx.tracer(fx_root, e["a"], e["b"])
		"blood":
			Fx.blood_burst(fx_root, e["p"], bool(e["hs"]))
		"loot_add":
			_create_loot(int(e["u"]), e["p"], String(e["k"]), String(e["i"]), int(e["n"]))
		"loot_gone":
			_remove_loot_uid(int(e["u"]))
		"loot_n":
			var u := int(e["u"])
			if loot_by_uid.has(u):
				var li: LootItem = loot_by_uid[u]
				li.n = int(e["n"])
				li.refresh()
