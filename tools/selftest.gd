extends SceneTree
# اختبار ذاتي: بناء الجزيرة + مباراة كاملة لـ 50 لاعباً (بوتات) بالمحاكاة السريعة

var fails := 0

func check(name: String, ok: bool, info: String = "") -> void:
	if ok:
		print("PASS ", name, " ", info)
	else:
		fails += 1
		print("FAIL ", name, " ", info)

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var isl := Island.new()
	root.add_child(isl)
	isl.build()
	print("ISLAND_MS ", Time.get_ticks_msec() - t0)
	check("island_heights", isl.heights.size() == Island.GRID * Island.GRID)
	check("island_houses", isl.houses.size() >= 20, "houses=%d" % isl.houses.size())
	check("island_obstacles", isl.obstacle_count > 500, "obs=%d" % isl.obstacle_count)
	check("island_loot_spots", isl.loot_spots.size() >= 400, "spots=%d" % isl.loot_spots.size())
	var h0 := isl.height_at(0.0, 0.0)
	check("height_sample", absf(h0 - 7.44) < 0.6, "h(0,0)=%.2f" % h0)
	var sea := isl.height_at(1000.0, -1000.0)
	check("sea_outside", sea < 0.5, "h=%.2f" % sea)
	# منزل قابل للدخول: نقطة داخل أول منزل يجب أن تكون ممرة للاعب (لا يوجد حاجز عند المركز)
	var hh: Dictionary = isl.houses[0]
	var inside_ok := not isl.blocked(float(hh["x"]), float(hh["z"]), float(hh["y0"]), 0.42)
	check("house_interior_free", inside_ok)
	# باب المنزل: نقطة عند الباب يجب أن تكون حرة
	var door_z := float(hh["minz"]) + 0.2
	var door_free := not isl.blocked(float(hh["x"]), door_z - 0.1, float(hh["y0"]), 0.42)
	check("house_door_passable", door_free)
	# الجدار الشرقي يجب أن يمنع الدخول
	var wall_blocked := isl.blocked(float(hh["maxx"]) + 0.1, float(hh["z"]), float(hh["y0"]), 0.42)
	check("house_wall_blocks", wall_blocked)

	var m := BRMatch.new()
	root.add_child(m)
	m.setup(isl, 0, PackedStringArray(), 11, -1)
	check("match_players", m.fighters.size() == Cfg.TOTAL_PLAYERS, "n=%d" % m.fighters.size())
	check("loot_spawned", m.loot.size() > 150, "loot=%d" % m.loot.size())
	m.start()
	var dt := 0.1
	var t := 0.0
	var steps := 0
	var min_pl := 1e9
	var max_pl := -1e9
	var nan_bad := false
	var drop_seen := false
	var land_seen := false
	var chute_seen := false
	var kills_seen := 0
	var hits := 0
	var zone_done := false
	var inside_bounds := true
	var armed := {}
	while not m.over and t < 1500.0 and steps < 40000:
		m.update(dt, {})
		t += dt
		steps += 1
		for f in m.fighters:
			var p: Vector3 = f.position
			if is_nan(p.x) or is_nan(p.y) or is_nan(p.z):
				nan_bad = true
			if f.state == Fighter.St.FALL or f.state == Fighter.St.CHUTE:
				drop_seen = true
			if f.state == Fighter.St.CHUTE:
				chute_seen = true
			if f.state == Fighter.St.GROUND:
				land_seen = true
			if f.state == Fighter.St.GROUND and (absf(p.x) > 1030.0 or absf(p.z) > 1030.0):
				if inside_bounds:
					print("BOUNDS_DBG id=%d state=%d pos=%s t=%.1f" % [f.id, f.state, str(p), t])
				inside_bounds = false
			if f.slots[0] != null or f.slots[1] != null:
				armed[f.id] = true
		if m.zone_phase >= 1:
			zone_done = true
		m.events.clear()
	check("no_nan", not nan_bad)
	check("players_dropped", drop_seen)
	check("chute_used", chute_seen)
	check("players_landed", land_seen)
	check("zone_shrank", zone_done, "phase=%d t=%.0f" % [m.zone_phase, t])
	check("bounds", inside_bounds)
	check("bots_armed", armed.size() >= 20, "armed=%d" % armed.size())
	check("shots_fired", int(m.stats["shots"]) > 50, "shots=%d" % int(m.stats["shots"]))
	check("hits_landed", int(m.stats["hits"]) > 10, "hits=%d" % int(m.stats["hits"]))
	check("kills_happened", int(m.stats["kills"]) > 5, "kills=%d" % int(m.stats["kills"]))
	check("match_over", m.over, "alive=%d t=%.0f" % [m.alive, t])
	check("winner", m.winner != null and m.alive == 1, "alive=%d" % m.alive)
	var wn := m.winner.pname if m.winner != null else "-"
	print("MATCH_RESULT time=%.0f alive=%d winner=%s shots=%d hits=%d head=%d kills=%d loot_left=%d steps=%d" % [t, m.alive, wn, int(m.stats["shots"]), int(m.stats["hits"]), int(m.stats["head"]), int(m.stats["kills"]), m.loot.size(), steps])
	print("SELFTEST_MS ", Time.get_ticks_msec() - t0)
	if fails == 0:
		print("SELFTEST_ALL_PASS")
	else:
		print("SELFTEST_FAILS ", fails)
	quit(0 if fails == 0 else 1)
