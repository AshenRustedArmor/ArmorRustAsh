import re
import requests

import numpy as np
import matplotlib.pyplot as plt

# ===== Configuration =====
# Sourcing
SOURCE_URL = "https://raw.githubusercontent.com/Syampuuh/Titanfall2/master/scripts/weapons/"

# Statistics
PILOT_HP = 100

# Graphing
GRAPH_WIDTH = 100
GRAPH_DIST = 5000
GRAPH_STEPS = 50

# ===== Functions =====
def lerp(a, b, t):
	t = max(min(t, 1), 0)
	return (1-t)*a + t*b

def solve_itp(fn, tgt, a, b, tol=1., k1=0.2, k2=2.0):
	# Root-finding
	def g(x): return func(x) - target

	#
	y_a = g(a)
	y_b = g(b)

	# 2. Safety Check: If root isn't bracketed (e.g., damage never drops that low),
	#    return the closest boundary.
	if y_a * y_b > 0:
		return a if abs(y_a) < abs(y_b) else b

	# 3. ITP Initialization
	n_half = math.ceil(math.log2((b - a) / (2 * tol))) if (b - a) > 0 else 1
	n_max = n_half + 20

	# Ensure correct ordering for the algorithm
	if y_a > y_b:
		a, b = b, a
		y_a, y_b = y_b, y_a

	for j in range(n_max):
		# Calculating parameters
		x_half = (a + b) / 2
		r = tol * (2 ** (n_half - j)) if j <= n_half else 0

		# Interpolation (Regula Falsi)
		if y_b - y_a == 0: break # Avoid division by zero
		x_f = (y_b * a - y_a * b) / (y_b - y_a)

		# Truncation
		sigma = 1 if x_half - x_f > 0 else -1
		delta = k1 * ((b - a) ** k2)
		if delta > abs(x_half - x_f): delta = abs(x_half - x_f)

		x_t = x_f + sigma * delta

		# Projection
		x_itp = x_t if abs(x_t - x_half) <= r else x_half - sigma * r

		# Update bounds
		y_itp = g(x_itp)
		if y_itp > 0:
			b, y_b = x_itp, y_itp
		elif y_itp < 0:
			a, y_a = x_itp, y_itp
		else:
			return x_itp # Exact match found

		# Check convergence
		if (b - a) < 2 * tol: break
	return (a + b) / 2

def fmt_htk(dmg):
	if dmg <= 0: return "inf"

	htk = PILOT_HP / dmg
	if htk < 9.95: return f"{htk:.1f}"[:3]
	
	base = int(htk)
	frac = htk - base

	if frac < 0.3: return f"{base:2d}+"
	elif frac <= 0.7: return f"{base:2d}."
	else: return f"{base+1:2d}-"

# ===== Storage =====
class WeaponFalloff:
	def __init__(self, weapon_name):
		self.name = weapon_name

		self.data = {
			"damage_near_value": 				0,
			"damage_far_value": 				0,
			"damage_very_far_value": 			0,

			"damage_near_value_titanarmor": 	0,
			"damage_far_value_titanarmor": 		0,
			"damage_very_far_value_titanarmor": 0,

			"damage_near_distance": 			0,
			"damage_far_distance": 				0,
			"damage_very_far_distance":			0,

			"red_crosshair_range":				0
		}
		self.modified = {}
		self.has_mod = False

	def fetch(self):
		"""
		Scrapes weapon data from github.
		"""
		# URL Retrieval
		url = f"{SOURCE_URL}{self.name}.txt"
		print(f"Fetching '{self.name}' from: {url}")

		try:
			resp = requests.get(url)
			if resp.status_code != 200:
				print(f"Error 200: Could not find '{self.name}'. Status {resp.status_code}")
				return False
			self.parse(resp.text)
			return True
		except Exception as e:
			print(f"Connection error: {e}")
			return False

	def parse(self, keyvars):
		"""
		Regex parser for Source Engine KeyValues.
		"""
		# Sanitize
		clean = re.sub(r'//.*', '', keyvars)

		# Parse
		for key in self.data.keys():
			pattern = f'"{key}"\s*"([^"]+)"'
			matched = re.search(pattern, clean)

			if not matched: continue

			val_raw = matched.group(1)
			try:
				self.data[key] = float(raw_val)
			except ValueError:
				self.data[key] = val_raw

class FalloffCurve:
	def __init__(self, name):
		self.name = name

		self.thresholds = {
			"near":	0.90, 
			"far":	0.60, 
			"vfar":	0.25
		}

		self.consts = {
			"dmg_scale":	1.0,
			"dmg_pilot":	1.0,
			"dmg_titan":	1.5,
		}

	#	Overridden in child class
	def calibrate(self, data):
		pass

	def damage_at(self, dist_hu, isHeavyArmor):
		return 0.

	# Constant
	def apply(self, data, isHeavyArmor):
		mod_data = data.copy()

		# Damage intervals
		dmg_max = self.damage_at(0., isHeavyArmor)

		tgt_near = dmg_max * 0.95
		tgt_far  = dmg_max * 0.55
		tgt_vfar = dmg_max * 0.30

		# Search
		range = 1.5e4

		dist_near = solve_itp(self.damage_at, tgt_near, 0, range)
		dist_far  = solve_itp(self.damage_at, tgt_far,  0, range)
		dist_vfar = solve_itp(self.damage_at, tgt_vfar, 0, range)

		dmg_near = self.damage_at(dist_95)
		dmg_far  = self.damage_at(dist_55)
		dmg_vfar = self.damage_at(dist_30)

		# Enforce

		# Assign


		return

#	Constants
DMG_PEN   = 0.1
DMG_PILOT = 1.0
DMG_TITAN = 2.5

ARM_HFVEL = 400.0
ARM_PILOT = 5.0
ARM_TITAN = 50.0
class BallisticFalloff(FalloffCurve):
	CONST_DRAG = 0.0015

	CONST_FT_M = 0.3048
	CONST_HU_M = 0.01905
	CONST_GR_G = 0.0646989

	def __init__(self, name, mass_gr, vel_fps, bc, cal_mm):
		#	Bullet parameters
		self.mass_kg = mass_gr * CONST_GR_G * 0.001
		
		self.v0_ms = vel_fps * CONST_FT_M
		self.bc = bc
		self.cal_mm = cal_mm

		# Sectional density in lbm / sq in
		self.sd = (mass_gr/7000.) * (cal_mm/25.4)**-2

		#	Scaling
		self.consts = {
			"dmg_scale":	DMG_PEN,
			"dmg_pilot":	DMG_PILOT,
			"dmg_titan":	DMG_TITAN,

			"arm_const":	ARM_HFVEL,
			"arm_pilot":	ARM_PILOT,
			"arm_titan":	ARM_TITAN,
		}

	def calibrate(self, wpn):
		#	Retrieve data
		dists = np.array([
			0.,
			wpn["damage_near_distance"],
			wpn["damage_far_distance"],
		])

		tgt_pilot = np.array([
			wpn["damage_near_value"],
			wpn["damage_near_value"],
			wpn["damage_far_value"],
		])

		tgt_titan = np.array([
			wpn["damage_near_value_titanarmor"],
			wpn["damage_near_value_titanarmor"],
			wpn["damage_far_value_titanarmor"],
		])

		#	Find constants
		vel, pen = zip(*[self._phys_at(d, False) for d in dists])
		vel, pen = np.array(vel), np.array(pen)

		# Equation: P / D = S + (S * A * C) * (1/v)
        # Linear form: Y = M*X + b
        # X = vel ** -1
        # Y = pen / dmg

		x = np.vstack([1.0 / vels, np.ones(len(vels))]).T
		y_pilot = pen / tgt_pilot
		y_titan = pen / tgt_titan

		(m_p, c_p), _, _, _ = np.linalg.lstsq(X, y_pilot, rcond=None)
		(m_t, c_t), _, _, _ = np.linalg.lstsq(X, y_titan, rcond=None)

		#dmg_p = 1.0
		dmg_t = c_p / c_t

		arm_p = m_p / (c_p * self.consts["arm_const"])
		arm_t = m_t / (c_t * self.consts["arm_const"])

		self.consts.update({
			"dmg_scale":	float(c_p),
			"dmg_pilot":	1.0,
			"dmg_titan":	float(dmg_t),

			#"arm_const":	ARM_HFVEL,
			"arm_pilot":	abs(float(arm_p)),
			"arm_titan":	abs(float(arm_t)),
		})

		return self.consts

	def _phys_at(self, dist_hu):
		# Conversion
		dist_m = dist_hu * CONST_HU_M
		decay = (dist*CONST_HU_M) * self.bc / CONST_DRAG
		vel = self.v0_ms * math.exp(-decay * dist_m)

		# Puncture factor
		e_J = 0.5 * self.mass_kg * vel * vel
		pen = e_J * self.sd

		# Return phys
		return vel, pen

	def damage_at(self, dist_hu, isHeavyArmor):
		vel, pen = self._phys_at(dist_hu)
		
		# Armor calculation
		armor = self.consts["arm_titan"] if isHeavyArmor else self.consts["arm_pilot"]
		armor_eff = armor * ARM_CONST / max(vel, 1.)
		dr = 1. / (1. + armor_eff)
		
		# Damage
		damage = pen/DMG_PEN * dr
		return max(1., int(damage))
