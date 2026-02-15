import re
import requests
import argparse
import sys
import copy

import numpy as np
from scipy.optimize import minimize
import matplotlib.pyplot as plt
from matplotlib.widgets import Slider, Button

# ===== Configuration =====
# Sourcing
SOURCE_URL = "https://raw.githubusercontent.com/Syampuuh/Titanfall2/master/scripts/weapons/"

# Params
PILOT_HP = 100

# Constants
CONST_FT_M = 0.3048
CONST_HU_M = 0.01905
CONST_GR_G = 0.0646989

CONST_MACH = 343.0

DRAG_TABLES = {
	"G1": np.array([
		[0.0, 0.5, 0.8, 1.0, 1.2, 2.0, 5.0],	# Mach
		[0.2, 0.2, 0.2, 0.4, 0.5, 0.4, 0.3]		# Cd
	]),

	"G7": np.array([
		[0.0, 0.5, 0.8, 1.0, 1.2, 2.0, 5.0],
		[0.1, 0.1, 0.1, 0.2, 0.3, 0.2, 0.1]
	]),
}

# ===== Functions =====
def htk_fmt(dmg):
	if dmg <= 0: return "inf"

	htk = PILOT_HP / dmg
	if htk < 9.95: return f"{htk:.1f}"[:3]

	base = int(htk)
	frac = htk - base

	if frac < 0.3: return f"{base:2d}+"
	elif frac <= 0.7: return f"{base:2d}."
	else: return f"{base+1:2d}-"

def htk_range_text(vanilla, physics, dist_max=5000, dist_inc=100):
	"""
	Builds the range meter notation for weapon keyvars.
	"""

	def htk_range_bar():
		dist_ct = int(dist_max/dist_inc) + 1

		bufferP = list("-"*dist_ct)
		bufferT = bufferP

		#	Sample range
		#dist_rng = np.arange(dist_max, step=dist_inc)
		#dmgP = fnDmgP(dist_rng); dmgT = fnDmgT(dist_rng)

		for d in [ 0,
			vanilla.default["damage_near_distance"],
			vanilla.default["damage_far_distance"],
			vanilla.default["damage_very_far_distance"]
		]:
			idx = int(d/dist_inc)

			defP = physics.damage_lerp(d, False)
			strDefP = htk_fmt(defP)
			defT = physics.damage_lerp(d, True)
			strDefT = htk_fmt(defT)

		for d in [ 0,
			vanilla.modded["damage_near_distance"],
			vanilla.modded["damage_far_distance"],
			vanilla.modded["damage_very_far_distance"]
		]:
			idx = int(d/dist_inc)

			dmgP = physics.damage_at(d, False)
			strDmgP = htk_fmt(dmgP)
			dmgT = physics.damage_at(d, True)
			strDmgT = htk_fmt(dmgT)

		pass

	# Header section
	header = []
	header.append(f"//\t\t{vanilla.name}")
	header.append(f"//\tCOMMENTS 1")
	header.append(f"//\tCOMMENTS 2")

	pass

# ===== Storage ====
class FalloffCurve:
	def __init__(self, name):
		self.name = name
		self.config = {
		#	Name			Defl.	Tune?	Min		Max
			"dmg_scale":	[5.0,	True,	1e-1,	1e1],
			"dmg_pilot":	[1.0,	False,	1.0,	5.0],
			"dmg_titan":	[3.5,	False,	1.0,	5.0],
		}

	def get(self, key): return self.config.get(key, 0)[0]
	def set(self, key, val): self.config[key][0] = val

	#	Overridden in child class
	def damage_at(self, dist_hu, isHeavyArmor): raise NotImplementedError

	# Constant
	def calibrate(self, data, isHeavyArmor):
		mod_data = data.copy()

		#	Retrieve vanilla values
		indices = ["damage_near_"]
		if data.get("damage_far_distance"): indices.append("damage_far_")
		if data.get("damage_very_far_distance"): indices.append("damage_very_far_")

		def _get(suffix, first):
			vals = [first]
			vals.extend([ data.get(i+suffix, 0) for i in indices ])
			return np.array(vals, dtype=float)

		dists = _get("distance", 0.0)
		tgtP  = _get("value", data.get("damage_near_value"))
		tgtT  = _get("value_titanarmor", data.get("damage_near_value_titanarmor"))

		#	Physics calculation
		tunable = [k for k, v in self.config.items() if v[1]]
		guess   = [self.config[k][0] for k in tunable]
		bounds  = [tuple(self.config[k][2:4]) for k in tunable]

		def objective(params):
			for i, k in enumerate(tunable):
				self.set(k, params[i])

			predP = self.damage_at(dists, False)
			predT = self.damage_at(dists, True)

			return	np.sum((predP - tgtP)**2) + \
					np.sum((predT - tgtT)**2)

		res = minimize(objective, guess, bounds=bounds, method='L-BFGS-B')
		
		res_str = f"Calibration failed for {self.name}: {res.message}"
		if res.success:
			res_str = f"Calibrated {self.name}: Loss {res.fun:.4f}"
			for i, k in enumerate(tunable):
				self.set(k, res.x[i])

		print(res_str)
		return res

class VanillaFalloff(FalloffCurve):
	def __init__(self, name):
		super().__init__(name)
		self.data = {
			"damage_near_distance": 0,
			"damage_far_distance": 0,
			"damage_very_far_distance": 0,

			"damage_near_value": 0,
			"damage_far_value": 0,
			"damage_very_far_value": 0,

			"damage_near_value_titanarmor": 0,
			"damage_far_value_titanarmor": 0,
			"damage_very_far_value_titanarmor": 0,

			"projectiles_per_shot": 1,
			"spread_stand_hip": 0,
			"spread_stand_ads": 0
		}

		self.is_shotgun = False
		self.is_projectile = False

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
			self._analyze()
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
			pattern = rf'"{key}"\s*"([^"]+)"'
			matched = re.search(pattern, clean)
			if not matched: continue

			raw = matched.group(1)
			try: self.data[key] = float(raw)
			except ValueError: self.data[key] = raw

	def _analyze(self):
		pellets = self.data.get("projectiles_per_shot", 1)
		self.is_shotgun = (pellets > 1)
		self.is_projectile = ("projectile_launch_speed" in self.data)

	def damage_at(self, dist_hu, isHeavyArmor):
		far_dist = self.data.get("damage_far_distance", 0)
		suffix = "_titanarmor" if isHeavyArmor else ""
		has_vfar = self.data.get("damage_very_far_distance") \
            and self.data.get("damage_very_far_value")

		def _internal(d):
			d = np.atleast_1d(d)

			# interpolation consts
			a_str, b_str, c_str = "damage_near_", "damage_far_", "damage_far_"
			if has_vfar: c_str = "damage_very_far_"

			isFar = d >= self.data.get("damage_far_distance", 0)

			a_idx = b_str if isFar else a_str
			b_idx = c_str if isFar else b_str

			a_dist = self.data.get(f"{a_idx}distance", 0)
			b_dist = self.data.get(f"{b_idx}distance", 0)

			a_dmg = self.data.get(a_idx + "value" + suffix)
			b_dmg = self.data.get(b_idx + "value" + suffix)

			# Get interpolation const
			rngDiff = b_dist - a_dist

			t = (d-a_dist)/rngDiff if rngDiff > 0 else 0.0
			t = np.clip(t, 0.0, 1.0)

			# Get damage
			out = (1-t)*a_dmg + t*b_dmg
			return out[0] if out.size == 1 else out

		fn = np.vectorize(_internal, otypes=[float], cache=True)
		result = fn(dist_hu)

		if result.size == 1:return float(result)
		return result

#	Constants
SZ_PILOT = 0.5
SZ_TITAN = 3.5

class BallisticFalloff(FalloffCurve):
	def __init__(self, params):
		"""
		Create a ballistic model.

		params: {
			"name":    str,
			"model":   str (Ballistic drag model)

			"mass_gr": float (Bullet mass in grains),
			"v0_fps":  float (Initial velocity in fps),
			"bc_kgm2": float (Ballistic coefficient in kg/m^2),

			"cal_mm":  float (Bullet diameter),
		} """
		#	Table retrieval
		name = params.get("name", "unknown")
		self.model = params.get("model", "G1")

		mass_kg = params["mass_kg"] #gr"] * CONST_GR_G * 0.001
		v0_ms = params["v0_ms"] #fps"] * CONST_FT_M

		bc_kgm2 = params["bc_kgm2"]
		cal_mm = params["cal_mm"]

		# Sectional density in lbm / sq in
		mass_gr = mass_kg * CONST_GR_G * 1e3
		self.sd = (mass_gr/7000.) * (cal_mm/25.4)**-2

		#	Superclass
		super().__init__(name)
		self.config.update({
			# Name			Default		Tune?	Min		Max
			"arm_const":	[2e2,		True,	1.0,	1e3  ],
			"arm_pilot":	[1e1,		True,	0.0,	5e1  ],
			"arm_titan":	[5e1,		True,	0.0,	5e2	 ],

			"mass_kg":		[2.8e-2,	True,	2e-3,	0.1  ],
			#[mass_kg,	True,	5e-5,	0.1  ],

			"v0_ms":		[v0_ms,		True,	2e2,	3500 ],
			"bc_kgm2":		[bc_kgm2,	True,	5e1,	6e2  ],

			"cal_mm":		[cal_mm,	True,	3,		30   ],
		})

	# ====== Model hooks ======
	def _drag(self, v_ms):
		mach = v_ms / CONST_MACH
		table = DRAG_TABLES.get(self.model, DRAG_TABLES["G1"])
		return np.interp(mach, table[0], table[1])

	def _area(self, v_ms):
		r = self.get("cal_mm") * 5e-4
		return r * r * pi

	def _prob(self, dist_hu, tgt_rad):
		return 1.0

	# ====== Model impl ======
	def _phys_flight(self, dist_hu):
		#	Muzzle
		v0		= self.get("v0_ms")
		
		#	Impact
		# Velocity
		cd0 = self._drag(v0)
		k0  = cd0 / np.max(self.get("bc_kgm2"), 1.0)
		
		d_m	= dist_hu * CONST_HU_M
		v_I	= v0 * np.exp(-k0 * d_m)
		
		# Energy
		m	= self.get("mass_kg")
		e_I	= 0.5 * m * vI * vI

		#	Return
		# vel & energy @ impact
		return v_I, e_I
	
	def _phys_impact(self, dist_hu, armor):
		#	Retrieve projectile data
		v_I, e_I	= self._phys_flight(dist_hu)
		a_I			= self._area(v_I)

		#	Armor calculation
		# Scaling to "absorbed energy"
		a_ref = 4.5e-5 # Roughly the frontal area of 7.62

		arm_energy	= armor * self.get("arm_const")	
		arm_geo		= np.where(a_I == 0., 0., np.pow(a_I / a_ref, 0.5))
		arm_resist	= arm_energy * arm_geo
		
		arm_satur	= e_I / np.max(arm_resist, 1.0)
		arm_trans	= 1.0 / ( 1.0 + np.exp(-10.0 * (arm_satur - 0.85)) )
		arm_spall	= 1.0 + np.clip((sat_ratio - 1.1) * 5.0, 0.0, 1.0) * 0.2
		arm_shock	= a_I / a_ref

		return e_I * arm_satur * arm_trans * arm_spall * arm_shock

	def _damage_at(self, dist_hu, isHeavyArmor):
		tgt_armor = self.get("arm_titan") if isHeavyArmor else self.get("arm_pilot")
		tgt_area  = SZ_TITAN if isHeavyArmor else SZ_PILOT

		pen  = self._phys_impact(dist_hu, tgt_armor)
		prob = self._prob(dist_hu, tgt_area)

		tgt_mod   = self.get("dmg_titan") if isHeavyArmor else self.get("dmg_pilot")
		return pen * prob * tgt_mod

	def bake(self, ref):
		"""
		Creates a 'Baked' VanillaFalloff by sampling this physics model
		at the reference curve's Near/Far/VeryFar distances.
		"""
		# Clone reference curve
		baked = copy.deepcopy(ref)
		baked.name = f"{self.name}_baked"

		# Find optimal breakpoints
		def func(d): return self.damage_at(d, False)
		points = solve(func, B=5000, n=3)

		baked.data["damage_near_distance"] = points[0][0]
		baked.data["damage_far_distance"]  = points[1][0]
		baked.data["damage_very_far_distance"] = points[2][0]

		baked.data["damage_near_value"]    = points[0][1]
		baked.data["damage_far_value"]     = points[1][1]
		baked.data["damage_very_far_value"]    = points[2][1]

		baked.data["damage_near_value_titanarmor"]     = self.damage_at(points[0][0], True)
		baked.data["damage_far_value_titanarmor"]      = self.damage_at(points[1][0], True)
		baked.data["damage_very_far_value_titanarmor"] = self.damage_at(points[2][0], True)

		return baked

class RifleFalloff(BallisticFalloff):
	def __init__(self, params, len_cal=2.0, twist=10, tumble=1.5):
		super().__init__(params)
		self.config.update({
			# Name		Default		Tune?	Min		Max
			"len_cal":	[len_cal,	True,	1.0,	5.5	 ],
			"twist":	[twist,		True,	7.0,	24.0 ],
			"tumble":	[tumble,	True,	0.0,	1e1  ],
		})

	def _stability(self, v_ms):
		m  = self.get("mass_kg") * 1e3 / CONST_GR_G
		d  = self.get("cal_mm") * 25.4
		l  = self.get("len_cal")
		t  = self.get("twist")

		v_fps = v_ms / CONST_FT_M
		mach = v_ms / CONST_MACH
        
		sg = (30*m)/(t*t*d*d*d*l*(1+l*l))
		dip = 0.5 * np.exp(-((mach - 1.0) / 0.15)**2)
		return np.maximum(sg - dip, 0.1)
		#1.0/(1.0 + np.exp(10.0 * (sg - 0.95))) # Sigmoid to estimate stability

	def _drag(self, v_ms):
		cd = super()._drag(v_ms)
		sg = self._stability(v_ms)
		stable = np.clip(1.5 - sg, 0.0, 1.0)
		return cd * (1.0 + stable)

	def _area():
		a_front	= super()._area(v_ms)
		a_side	= a_front * self.get("len_cal")

		sg		= self._stability(v_ms)
		yaw		= 1.0 / (1.0 + np.exp(8.0 * (sg - 1.1)))
		return (1-yaw) * a_front + yaw * a_side

class ShotgunFalloff(BallisticFalloff):
	def __init__(self, params, pellets, spread):
		super().__init__(params)
		self.config.update({
			# Name		Default		Tune?	Min		Max
			"pellets":	[pellets,	True,	1,		50	],
			"spread":	[spread,	True, 	0.1,	15.0],
		})
	
	def _prob(self, dist_hu, tgt_r=SZ_PILOT):
		dist_m = np.maximum(dist_hu * CONST_HU_M, 0.1)

		sigma_rad = self.get("spread") * np.pi / 360
		sigma_r = dist_m * np.tan(sigma_rad)

		prob_hit = 1.0 - np.exp( -(tgt_r**2)/(2 * sigma_r**2) )
		return prob_hit * self.get("pellets") 

# ===== Plotting utils =====
class FalloffGUI:
	def __init__(self, vanilla, physics, dist_max = 5000, dist_ct = 200):
		self.vanilla = vanilla; self.physics = physics
		self.baked = self.physics.bake(self.vanilla)

		#	Figure, subplots
		self.sliders = []
		self.fig, (self.ax_p, self.ax_t) = plt.subplots(2, 1, sharex=True, figsize=(10, 8))
		plt.subplots_adjust(right=0.55, hspace=0.3)

		#	Data
		self.dists = np.linspace(0, dist_max, dist_ct+1)

		#	Functions
		self._funcs()
		self._graph()
		self._controls()

		plt.show()

	def _funcs(self):
		self.fnPhysP = np.vectorize(lambda d: self.physics.damage_at(d, False))
		self.fnIntrP = np.vectorize(lambda d: self.baked.damage_at(d, False)) #, False))
		self.fnGameP = np.vectorize(lambda d: self.vanilla.damage_at(d, False)) #, True))

		self.fnPhysT = np.vectorize(lambda d: self.physics.damage_at(d, True))
		self.fnIntrT = np.vectorize(lambda d: self.baked.damage_at(d, True)) #, False))
		self.fnGameT = np.vectorize(lambda d: self.vanilla.damage_at(d, True)) #, True))

	def _graph(self):
		#	Plot
		# Titles/labels/legend
		self.ax_p.clear()
		self.ax_t.clear()

		self.ax_p.set_title(f"{self.vanilla.name}: Pilot")
		self.ax_t.set_title(f"{self.vanilla.name}: Titan")

		self.ax_p.set_ylabel("Damage")
		self.ax_t.set_ylabel("Damage")
		self.ax_t.set_xlabel("Distance (hu)")

		self.ax_p.grid(True, alpha=0.25)
		self.ax_t.grid(True, alpha=0.25)

		# Plot
		self.axPhysP, = self.ax_p.plot(self.dists, self.fnPhysP(self.dists), ':', color='grey', alpha=0.5, label='Modeled')
		self.axPhysT, = self.ax_t.plot(self.dists, self.fnPhysT(self.dists), ':', color='grey', alpha=0.5, label='Modeled')

		self.axIntrP, = self.ax_p.plot(self.dists, self.fnIntrP(self.dists), '--', color='orange', alpha=0.6, label='Interpolated')
		self.axIntrT, = self.ax_t.plot(self.dists, self.fnIntrT(self.dists), '--', color='cyan', alpha=0.6, label='Interpolated')

		self.axGameP, = self.ax_p.plot(self.dists, self.fnGameP(self.dists), '-', color='red', alpha=0.8, label='Vanilla')
		self.axGameT, = self.ax_t.plot(self.dists, self.fnGameT(self.dists), '-', color='blue', alpha=0.8, label='Vanilla')

		self.ax_p.legend()
		self.ax_t.legend()

	def _controls(self):
		# Identify tunable parameters
		tunables = [k for k, v in self.physics.config.items() if True] #v[1]]

		# Formatting
		ax_color = 'lightgoldenrodyellow'
		start_y = 0.85; spacing = 0.04

		# Print button
		ax_btn = plt.axes([0.70,
			start_y - (len(tunables) * spacing) - 0.05,
			0.1, 0.04
		])
		self.btn = Button(ax_btn, 'Print', hovercolor='0.975')
		self.btn.on_clicked(self._print)

		for i, key in enumerate(tunables):
			val, _, v_min, v_max = self.physics.config[key]

			slider_ax = plt.axes(
				[0.70, start_y - (i * spacing), 0.20, 0.03],
				facecolor=ax_color
			)
			slider = Slider(
				ax			=	slider_ax,
				label		=	key,
				orientation	=	'horizontal',

				valinit		=	val,
				valmin		=	v_min,
				valmax		=	v_max,
			)

			slider.on_changed(self._updater(key))
			self.sliders.append(slider)

	def _updater(self, key):
		def update(val):
			# Update config/functions
			self.physics.set(key, val)
			self.baked = self.physics.bake(self.vanilla)
			self._funcs()

			# Update plots
			self.axPhysP.set_ydata(self.fnPhysP(self.dists))
			self.axPhysT.set_ydata(self.fnPhysT(self.dists))

			self.axIntrP.set_ydata(self.fnIntrP(self.dists))
			self.axIntrT.set_ydata(self.fnIntrT(self.dists))

            # Redraw
			self.fig.canvas.draw_idle()
		return update

	def _print(self, event):
		title = f"\n=== {self.physics.name} ==="

		print(title)
		for k, v in self.physics.config.items():
			if v[1]: print(f"'{k}': {v[0]:.4f},")
		print("="*len(title)+"\n")

# ===== Main Execution =====
if __name__ == "__main__":
	#	Parsing
	parser = argparse.ArgumentParser()
	parser.add_argument("weapon", help="Internal weapon name (e.g. mp_weapon_rspn101)")

	parser.add_argument("--mass_gr",	type=float, help="Bullet mass (grain)")
	parser.add_argument("--v0_fps",		type=float, help="Muzzle velocity (ft/s)")
	parser.add_argument("--bc_kgm2",	type=float, help="Ballistic coeff. (kg/m2)")
	parser.add_argument("--cal_mm",		type=float, help="Caliber (mm)")

	parser.add_argument("--len_cal",	type=float, help="Round length (cal)")
	parser.add_argument("--twist",		type=float, help="Twist rate/ratio")

	args = parser.parse_args()

	# Fetch Real Data
	vanilla = VanillaFalloff(args.weapon)
	if not vanilla.fetch(): sys.exit(1)

	# Setup params
	params = { "name": args.weapon, "model": "G1" }
	if args.mass_gr: 	params.update({"mass_kg":	args.mass_gr * CONST_GR_G * 0.001})
	if args.v0_fps:		params.update({"v0_ms":		args.v0_fps * CONST_FT_M})
	if args.bc_kgm2:	params.update({"bc_kgm2":	args.bc_kgm2})
	if args.cal_mm:		params.update({"cal_mm":	args.cal_mm})

	if args.len_cal:	params.update({"len_cal":	args.len_cal})
	if args.twist:		params.update({"twist":		args.twist})


	config = {
		"mass_kg":		9.5e-3,
		"v0_ms":		853.44,
		"bc_kgm2":		279,
		"cal_mm":		7.62,
	}; config.update(params)

	# Derive Class
	if vanilla.is_shotgun:
		pellets = int(vanilla.data.get("projectiles_per_shot", 8))
		spread  = vanilla.data.get("spread_stand_hip", 3.0)
		phys = ShotgunFalloff(config, pellets, spread)
	else:
		if vanilla.is_projectile:
			v0_hu = vanilla.data.get("projectile_launch_speed", 30000)
			config["v0_ms"] = v0_hu / CONST_HU_M
		phys = RifleFalloff(config)

	# Apply arguments
	for k in phys.config.keys():
		if k not in params: continue
		#phys.config[k][0] = v
		phys.config[k][1] = False

		print(f"Locked {k} (Value: {phys.config[k][0]})")

	# Calibrate & Display
	phys.calibrate(vanilla.data, False)
	FalloffGUI(vanilla, phys)
