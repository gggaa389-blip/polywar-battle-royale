extends Node3D
# نقطة الدخول: البيئة، الكاميرا، الجزيرة، تدفق المباراة، الأصوات

enum Mode { MENU, MATCH }

var mode := Mode.MENU
var isl: Island
var match_: BRMatch = null
var hud: HUD
var menu: MenuUI
var cam: Camera3D
var sfx_cache := {}
var match_seed := 1
var last_hp := 100.0
var last_reload := 0.0
var out_shown := false
var end_shown := false
var lan: Lan
var player_name := "لاعب"

func _ready() -> void:
	var th := Theme.new()
	var fnt := load("res://assets/font/Tajawal-Regular.ttf") as Font
	if fnt != null:
		th.default_font = fnt
		th.default_font_size = 18
	get_window().theme = th
	_setup_env()
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 2600.0
	cam.near = 0.1
	add_child(cam)
	cam.current = true
	isl = Island.new()
	add_child(isl)
	isl.build()
	hud = HUD.new()
	add_child(hud)
	hud.visible = false
	lan = Lan.new()
	lan.name = "Lan"
	add_child(lan)
	lan.lobby_changed.connect(func(names: PackedStringArray): menu.update_lobby(names))
	lan.connect_ok.connect(func(): menu.show_lobby(false, PackedStringArray()))
	lan.connect_failed.connect(func(): menu.set_status("تعذّر الاتصال بالمضيف. تأكد من العنوان ومن أنكما على نفس الشبكة."); menu.show_net())
	lan.server_gone.connect(_on_server_gone)
	lan.started.connect(_on_net_started)
	lan.snapshot_in.connect(_on_snapshot)
	lan.events_in.connect(_on_events)
	lan.input_in.connect(_on_remote_input)
	lan.peer_left.connect(_on_peer_left)
	menu = MenuUI.new()
	add_child(menu)
	menu.start_pressed.connect(_start_solo)
	menu.host_pressed.connect(_host)
	menu.join_pressed.connect(_join)
	menu.start_net_pressed.connect(func(): lan.start_all())
	menu.leave_pressed.connect(_leave_room)
	menu.back_pressed.connect(_to_menu)
	menu.continue_pressed.connect(func(): menu.hide_overlay())
	menu.sens_changed.connect(func(v: float): hud.sens = v)
	player_name = "لاعب-%d" % (randi() % 90 + 10)
	menu.show_main()
	_load_sfx()

func _setup_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color(0.28, 0.5, 0.8)
	sky.sky_horizon_color = Color(0.72, 0.84, 0.92)
	sky.ground_horizon_color = Color(0.6, 0.72, 0.8)
	sky.ground_bottom_color = Color(0.1, 0.2, 0.3)
	var sky_res := Sky.new()
	sky_res.sky_material = sky
	env.background_mode = Environment.BG_SKY
	env.sky = sky_res
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_density = 0.00045
	env.fog_light_color = Color(0.75, 0.85, 0.93)
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 1.1
	add_child(sun)

func _load_sfx() -> void:
	for n in ["shot", "hit", "hurt", "heal", "click", "boom", "alarm", "reload_in", "reload_out"]:
		sfx_cache[n] = load("res://assets/sfx/%s.wav" % n)

func _sfx(n: String) -> void:
	if not sfx_cache.has(n) or sfx_cache[n] == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = sfx_cache[n]
	p.volume_db = -6.0
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

func _start_solo() -> void:
	lan.leave()
	_begin_match(randi() % 1000000 + 1, PackedStringArray(["أنت"]), 0, false)

func _host() -> void:
	if not lan.host(player_name):
		menu.set_status("تعذّر فتح المنفذ 24567. جرّب مرة أخرى.")
		return
	menu.show_lobby(true, lan.local_ips())

func _join(ip: String) -> void:
	if ip == "":
		menu.set_status("أدخل عنوان المضيف أولاً.")
		return
	if not lan.join(ip, player_name):
		menu.set_status("تعذّر بدء الاتصال.")
		return
	menu.set_status("جاري الاتصال بـ %s ..." % ip)

func _leave_room() -> void:
	lan.leave()
	menu.show_net()

func _on_server_gone() -> void:
	if match_ != null:
		_to_menu()
	menu.show_net()
	menu.set_status("انقطع الاتصال بالمضيف.")

func _on_net_started(seed_v: int, names: PackedStringArray, slot: int) -> void:
	_begin_match(seed_v, names, slot, lan.role == Lan.ROLE_CLIENT)

func _on_snapshot(d: PackedFloat32Array) -> void:
	if match_ != null and lan.role == Lan.ROLE_CLIENT and match_.human != null:
		match_.apply_snapshot(d, match_.human.id)

func _on_events(evs: Array) -> void:
	if match_ != null:
		match_.events.append_array(evs)

func _on_remote_input(slot: int, d: PackedFloat32Array) -> void:
	if match_ != null:
		match_.merge_remote(slot, d)

func _on_peer_left(slot: int) -> void:
	if match_ != null:
		match_.human_left(slot)
		hud.feed_add("غادر لاعب — يكمل بوت مكانه")

func _begin_match(seed_v: int, names: PackedStringArray, slot: int, client: bool) -> void:
	if match_ != null:
		match_.queue_free()
	match_ = BRMatch.new()
	match_.is_client = client
	add_child(match_)
	match_.setup(isl, names.size(), names, seed_v, slot)
	match_.start()
	mode = Mode.MATCH
	last_hp = Cfg.HP_MAX
	last_reload = 0.0
	out_shown = false
	end_shown = false
	menu.hide_overlay()
	hud.visible = true
	hud.toast("انزل من الطائرة واجمع الأسلحة!", 3.0)

func _to_menu() -> void:
	if match_ != null:
		match_.queue_free()
		match_ = null
	mode = Mode.MENU
	hud.visible = false
	hud.fire_held = false
	hud.ads_held = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.captured = false
	if lan.role != Lan.ROLE_NONE:
		lan.leave()
	menu.show_main()

func _process(delta: float) -> void:
	if mode != Mode.MATCH or match_ == null:
		return
	var inp := hud.take_input()
	var h := match_.human
	var dt := minf(delta, 0.05)
	match_.update(dt, inp)
	if lan.role == Lan.ROLE_CLIENT:
		lan.client_input(dt, inp)
	elif lan.role == Lan.ROLE_HOST:
		lan.host_tick(dt, match_, match_.events.duplicate())
	_handle_events()
	var spect: Fighter = null
	if h != null and not h.alive():
		spect = match_.spectate_target()
	hud.update_match(match_, h, spect)
	if h != null:
		if h.hp < last_hp - 0.01 and h.alive():
			hud.flash_hurt()
		last_hp = h.hp
		if h.reload_t > 0.0 and last_reload <= 0.0:
			_sfx("reload_in")
		if h.reload_t <= 0.0 and last_reload > 0.0:
			_sfx("reload_out")
		last_reload = h.reload_t
	_update_camera(delta)

func _handle_events() -> void:
	var h := match_.human
	var client := lan.role == Lan.ROLE_CLIENT
	for e in match_.events:
		var t: String = e["t"]
		if t in ["tr", "blood", "loot_add", "loot_gone", "loot_n"]:
			if client:
				match_.client_fx(e)
			continue
		match t:
			"drop_end":
				hud.toast("بدأ السقوط — انتبه لدائرة الأمان", 2.5)
			"zone":
				_sfx("alarm")
				hud.toast("الدائرة تنكمش!", 2.5)
			"shot":
				if h != null and int(e["src"]) == h.id:
					_sfx("shot")
			"hit":
				if h != null and int(e["src"]) == h.id:
					hud.hit_marker(bool(e["hs"]))
					_sfx("hit")
				if h != null and int(e["v"]) == h.id:
					_sfx("hurt")
			"kill":
				var a := int(e["a"])
				var v := int(e["v"])
				var an: String = "الدائرة" if a < 0 else String(match_.fighters[a].pname)
				var vn: String = String(match_.fighters[v].pname)
				var suffix := " (رأس)" if bool(e["hs"]) else ""
				hud.feed_add("%s  ←  %s%s" % [an, vn, suffix])
				if h != null and a == h.id:
					_sfx("boom")
					hud.toast("قضاء!" + suffix, 2.0)
			"heal":
				if h != null and int(e["v"]) == h.id:
					_sfx("heal")
			"pick":
				if h != null and int(e["v"]) == h.id:
					_sfx("click")
			"you_out":
				if h != null and int(e["v"]) == h.id and not out_shown:
					out_shown = true
					hud.toast("خرجت من المعركة — المركز #%d" % int(e["place"]), 4.0)
					menu.show_hud_overlay("انتهت مشاركتك", "المركز #%d من %d\nالقتلى: %d" % [int(e["place"]), Cfg.TOTAL_PLAYERS, h.kills], true)
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
					hud.captured = false
			"over":
				if not end_shown:
					end_shown = true
					match_.over = true
					match_.phase = BRMatch.Phase.OVER
					var wid := int(e["winner"])
					var w: Fighter = match_.fighters[wid] if wid >= 0 else null
					var won := w != null and h != null and w.id == h.id
					var title := "فزت بالمعركة!" if won else "انتهت المعركة"
					var body := "الفائز: %s\nالمركز الأخير لك: #%d\nالقتلى: %d" % [w.pname if w != null else "—", h.place if h != null else 0, h.kills if h != null else 0]
					if won:
						body = "أنت الأخير على قيد الحياة!\nالقتلى: %d" % h.kills
					menu.show_end(title, body)
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
					hud.captured = false
	match_.events.clear()

func _update_camera(dt: float) -> void:
	if match_ == null:
		return
	var h := match_.human
	var target: Fighter = h
	if h != null and not h.alive():
		target = match_.spectate_target()
	if target == null:
		return
	if match_.phase == BRMatch.Phase.PLANE and target.state == Fighter.St.PLANE:
		var pp := match_.plane_pos
		var back := -match_.plane_dir
		cam.global_position = pp + back * 30.0 + Vector3(0, 10.0, 0)
		cam.look_at(pp + Vector3(0, 0, 0), Vector3.UP)
		cam.fov = 60.0
		return
	var eye := target.eye()
	var dir := target.aim_dir()
	var ads := target.ads and target.state == Fighter.St.GROUND and target == h
	var dist := 1.4 if ads else 3.4
	var right := Vector3(cos(target.yaw), 0, -sin(target.yaw))
	var goal_pos := eye - dir * dist + Vector3(0, 0.35, 0)
	if ads:
		goal_pos += right * 0.3
	cam.global_position = cam.global_position.lerp(goal_pos, clampf(dt * 25.0, 0.0, 1.0)) if cam.global_position.distance_to(goal_pos) < 6.0 else goal_pos
	cam.look_at(eye + dir * 80.0, Vector3.UP)
	var want_fov := 70.0
	var ws: Variant = target.cur_weapon()
	if ads and ws != null:
		want_fov = float(Cfg.WEAPONS[ws["id"]]["fov"])
	cam.fov = lerpf(cam.fov, want_fov, clampf(dt * 10.0, 0.0, 1.0))
	if target.model != null:
		target.model.visible = not (ads and ws != null and ws["id"] == "sniper")
