extends Node
# ثوابت مشتركة لوضع الباتل رويال (Free Fire style)

const VERSION_NAME := "2.0"
const MAP_HALF := 1024.0
const TOTAL_PLAYERS := 50
const GRAV := 26.0
const WALK := 4.6
const RUN := 7.4
const CROUCH_MUL := 0.5
const ADS_MUL := 0.55
const JUMP_V := 6.4
const FREEFALL_MAX := 56.0
const FREEFALL_ACC := 22.0
const CHUTE_OPEN_ALT := 150.0
const CHUTE_FALL := 6.5
const PLANE_ALT := 340.0
const PLANE_SPEED := 85.0
const PLANE_A := Vector2(-1250.0, -950.0)
const PLANE_B := Vector2(1250.0, 950.0)
const PLANE_JUMP_MIN := 0.22
const PLANE_FORCE_T := 0.62
const FIGHTER_R := 0.42
const HP_MAX := 100.0
const AMMO_CAP := 300
const ZONE_START_R := 1250.0
const ZONE_WAIT_FIRST := 60.0
# كل مرحلة: مدة الانتظار، مدة الانكماش، نصف القطر الجديد، ضرر الثانية خارج الدائرة
const ZONE_PHASES := [
	{"wait": 60.0, "shrink": 40.0, "r": 700.0, "dps": 1.0},
	{"wait": 45.0, "shrink": 35.0, "r": 340.0, "dps": 2.0},
	{"wait": 35.0, "shrink": 30.0, "r": 160.0, "dps": 4.0},
	{"wait": 25.0, "shrink": 25.0, "r": 70.0, "dps": 8.0},
	{"wait": 20.0, "shrink": 20.0, "r": 22.0, "dps": 14.0},
	{"wait": 15.0, "shrink": 15.0, "r": 4.0, "dps": 22.0},
]

# الأسلحة: الضرر، معدل الإطلاق (ثانية بين الطلقات)، سعة المخزن، مدة التعبئة، نوع الذخيرة، إطلاق متواصل، الانتشار، المدى، عدد الرصاصات، مضاعف الرأس
const WEAPONS := {
	"pistol": {"name": "مسدس", "dmg": 24.0, "rate": 0.28, "mag": 12, "reload": 1.1, "ammo": "9mm", "auto": false, "spread": 0.012, "range": 160.0, "pellets": 1, "hs": 2.0, "fov": 55.0, "ads_spread": 0.5},
	"smg": {"name": "رشاش", "dmg": 15.0, "rate": 0.085, "mag": 30, "reload": 1.8, "ammo": "9mm", "auto": true, "spread": 0.035, "range": 120.0, "pellets": 1, "hs": 1.8, "fov": 55.0, "ads_spread": 0.5},
	"ar": {"name": "بندقية هجومية", "dmg": 22.0, "rate": 0.11, "mag": 30, "reload": 2.2, "ammo": "556", "auto": true, "spread": 0.018, "range": 260.0, "pellets": 1, "hs": 2.0, "fov": 42.0, "ads_spread": 0.4},
	"shotgun": {"name": "بندقية صيد", "dmg": 13.0, "rate": 0.85, "mag": 5, "reload": 2.4, "ammo": "12g", "auto": false, "spread": 0.085, "range": 45.0, "pellets": 8, "hs": 1.5, "fov": 55.0, "ads_spread": 0.7},
	"sniper": {"name": "قناصة", "dmg": 95.0, "rate": 1.5, "mag": 5, "reload": 2.8, "ammo": "762", "auto": false, "spread": 0.002, "range": 900.0, "pellets": 1, "hs": 2.5, "fov": 20.0, "ads_spread": 0.2},
}

const WEAPON_IDS := ["", "pistol", "smg", "ar", "shotgun", "sniper"]
const NET_PORT := 24567
const NET_SNAP_HZ := 20.0
const NET_INPUT_HZ := 30.0
const NET_SNAP_HEADER := 10
const NET_SNAP_STRIDE := 8
const NET_TAIL := 12

const AMMO_NAMES := {"9mm": "ذخيرة 9mm", "556": "ذخيرة 5.56", "12g": "ذخيرة 12 قيج", "762": "ذخيرة 7.62"}
const AMMO_BOX := {"9mm": 30, "556": 30, "12g": 10, "762": 10}
const NON_LOOP: Array = ["Jump", "Jump_Land", "Jump_Idle", "HitReact", "Death", "Punch", "Yes", "No", "Wave", "Duck"]
