import re
import requests
import argparse
import sys

import numpy as np
from scipy.optimize import minimize
import matplotlib.pyplot as plt

# ===== Configuration =====
# Sourcing
SOURCE_URL = "https://raw.githubusercontent.com/Syampuuh/Titanfall2/master/scripts/weapons/"

# Params
PILOT_HP = 100

ARM_HFVEL = 400.0
ARM_PILOT = 5.0
ARM_TITAN = 50.0

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
def lerp(a, b, t):
	return 

def solve_itp(fn, tgt, a, b, tol=1., k1=0.2, k2=2.0):
	targets = np.atleast_1d(targets)
	a = np.full(targets.shape, float(low))
	b = np.full(targets.shape, float(high))

	def g(x): return fn(x) - targets

	y_a, y_b = g(a), g(b)

	# Handle cases where target is outside current physics bounds
	# (e.g. projectile stops before reaching damage_very_far)
	mask = (y_a * y_b < 0)

	# Constants for ITP logic
	k1 = 0.2
	k2 = 2.0
	n_half = np.ceil(np.log2((b - a) / (2 * tol)))

	for j in range(max_iter):
		# 1. Interpolation (Regula Falsi)
		# Avoid division by zero: if y_a == y_b, points are identical
		denom = y_b - y_a
		x_f = np.where(np.abs(denom) > 1e-9, (y_b * a - y_a * b) / denom, (a + b) / 2)

		# 2. Truncation
		x_half = (a + b) / 2
		r = tol * (2.0 ** (n_half - j))
		sigma = np.sign(x_half - x_f)
		delta = np.minimum(k1 * ((b - a) ** k2), np.abs(x_half - x_f))
		x_t = x_f + sigma * delta

		# 3. Projection
		x_itp = np.where(np.abs(x_t - x_half) <= r, x_t, x_half - sigma * r)

		# Update Bounds
		y_itp = g(x_itp)

		# Vectorized update of a and b
		side = y_itp * y_a > 0

		a = np.where(side, x_itp, a)
		y_a = np.where(side, y_itp, y_a)
		
		b = np.where(~side, x_itp, b)
		y_b = np.where(~side, y_itp, y_b)

		# Check convergence across the whole vector
		if np.all((b - a) < 2 * tol): break
	
	return (a + b) / 2

def htk_fmt(dmg):
	if dmg <= 0: return "inf"

	htk = PILOT_HP / dmg
	if htk < 9.95: return f"{htk:.1f}"[:3]
	
	base = int(htk)
	frac = htk - base

	if frac < 0.3: return f"{base:2d}+"
	elif frac <= 0.7: return f"{base:2d}."
	else: return f"{base+1:2d}-"

def htk_range_text(wf, fc, dist_max=5000, dist_inc=100):
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
			wf.default["damage_near_distance"],
			wf.default["damage_far_distance"],
			wf.default["damage_very_far_distance"]
		]:
			idx = int(d/dist_inc)

			defP = fc.damage_lerp(d, False)
			strDefP = htk_fmt(defP)
			defT = fc.damage_lerp(d, True)
			strDefT = htk_fmt(defT)

		for d in [ 0,
			wf.modded["damage_near_distance"],
			wf.modded["damage_far_distance"],
			wf.modded["damage_very_far_distance"]
		]:
			idx = int(d/dist_inc)

			dmgP = fc.damage_at(d, False)
			strDmgP = htk_fmt(dmgP)
			dmgT = fc.damage_at(d, True)
			strDmgT = htk_fmt(dmgT)

		pass
	
	# Header section
	header = []
	header.append(f"//\t\t{wf.name}")
	header.append(f"//\tCOMMENTS 1")
	header.append(f"//\tCOMMENTS 2")

	pass

# ===== Storage =====
class WeaponFalloff:
	# Containts weapon-specific falloff data.
	def __init__(self, weapon_name):
		self.name = weapon_name

		self.default = {
			"damage_near_value": 				0,
			"damage_far_value": 				0,
			"damage_very_far_value": 			0,

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
			print(f"Vals: {vals}")
			return np.array(vals, dtype=float)

		dists = _get("distance", 0.0)
		tgtP  = _get("value", data.get("damage_near_value"))
		tgtT  = _get("value_titanarmor", data.get("damage_near_value_titanarmor"))

		#	Physics calculation
		tunable = [k for k, v in self.config.items() if v[1]]
		guess   = [self.config[k][0] for k in tunable]
		bounds  = [self.config[k][2:4] for k in tunable]
		
		def objective(params):
			for i, k in enumerate(tunable):
				self.set(k, params[i])

			predP = self.damage_at(dists, False)
			predT = self.damage_at(dists, True)

			return	np.sum((predP - tgtP)**2) + \
					np.sum((predT - tgtT)**2)

		res = minimize(objective, guess, bounds=bounds, method='L-BFGS-B')
		if res.success: print(f"Calibrated {self.name}: Loss {res.fun:.4f}")
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

			"damage_near_distance": 			0,
			"damage_far_distance": 				0,
			"damage_very_far_distance":			0,

			"red_crosshair_range":				0
		}
		self.modded = {}

	#	Helper functions
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
		for key in self.default.keys():
			pattern = f'"{key}"\s*"([^"]+)"'
			matched = re.search(pattern, clean)
<<<<<<< HEAD
=======

>>>>>>> parent of 1ee5b97 (Bug squashing)
			if not matched: continue

			val_raw = matched.group(1)
			try:
				self.default[key] = float(raw_val)
			except ValueError:
				self.default[key] = val_raw

	#	Get damage
	def damage_at(self, dist_hu, isHeavyArmor, isModded):
		# interpolation consts
		strA = "damage_near_"
		strB = "damage_far_"

		consts = self.modded if isModded else self.default

		if dist_hu >= consts["damage_far_distance"]:
			strA = "damage_far_"
			strB = "damage_very_far_"

		distA = consts[strA + "distance"]
		distB = consts[strB + "distance"]
		
		dmgDist = dist_hu - distA
		t = dmgDist / (distB - distA)
        
		# get damage
		suffix = "_titanarmor" if isHeavyArmor else ""
		dmgA = strA + "value" + suffix
		dmgB = strB + "value" + suffix

		# interpolation consts
		a_str, b_str, c_str = "damage_near_", "damage_far_", "damage_far_"

		if (self.data.get("damage_very_far_distance") is not None) \
		  and (self.data.get("damage_very_far_value") is not None):
			c_str = "damage_very_far_"

		isFar = dist_hu >= self.data.get("damage_far_distance", 0)

		a_idx = np.where(isFar, b_str, a_str)
		b_idx = np.where(isFar, c_str, b_str)

		a_dist = np.array([ self.data.get(f"{s}distance", 0) for s in a_idx ])
		b_dist = np.array([ self.data.get(f"{s}distance", 0) for s in b_idx ])

		a_dmg_ = []
		for s in a_idx:
			s_str = f"{str(s)}value{suffix}"
			x = self.data.get(s_str)
			a_dmg_.append(x)

		a_dmg = np.array([ self.data.get(f"{str(s)}value{suffix}", 0) for s in a_idx ])
		b_dmg = np.array([ self.data.get(f"{str(s)}value{suffix}", 0) for s in b_idx ])
		
		# Get interpolation const
		rngDiff = b_dist - a_dist

		t = np.where(b_dist-a_dist > 0, (dist_hu-a_dist)/rngDiff, 0.)
		t = np.clip(t, 0.0, 1.0)

		# Get damage
		a_dmg = self.data.get(a_str + "value" + suffix)
		b_dmg = self.data.get(b_str + "value" + suffix)

		out = (1-t)*a_dmg + t*b_dmg
		return out[0] if out.size == 1 else out

class FalloffCurve:
	def __init__(self, name):
		self.name = name
		self.config = {
		#	Name			Defl.	Tune?	Min		Max
			"dmg_scale":	(1.0,	True,	0.001,	10.0),
			"dmg_pilot":	(1.0,	True,	0.1,	5.0),
			"dmg_titan":	(1.5,	True,	0.1,	5.0),
		}

	def get(self, key): return self.config.get(key, 0)[0]
	def set(self, key, val): self.config[key][0] = val

	#	Overridden in child class
	def damage_at(self, dist_hu, isHeavyArmor): raise NotImplementedError

	# Constant
	def apply(self, data, isHeavyArmor):
		mod_data = data.copy()

		#	Retrieve vanilla values
		indices = [
			"damage_near_",
			"damage_near_",
			"damage_far_",
			"damage_very_far_",
		]
		
		dists = np.array([ wf.get(i+"distance") for i in indices ])
		dists[0] = 0.0

		tgtP = np.array([ wf.get(i+"value") for i in indices ])
		tgtT = np.array([ wf.get(i+"value_titanarmor") for i in indices ])

		#	Physics calculation
		tunable = [k for k, v in self.config.itmes() if v[1]]
		guess = [self.config[k][0] for k in tunable]
		bounds = [self.config[k][2:4] for k in tunable_keys]
		
		def objective(params):
			for i, k in enumerate(tunable):
				self.set(k, params[i])

			predP = self.damage_at(dists, False)
			predT = self.damage_at(dists, True)
			
			errP = np.sum((predP - tgtP)**2)
			errT = np.sum((predT - tgtT)**2)

			return errP + errT

		res = minimize(objective, guess, bounds=bounds, method='L-BFGS-B')
		
		if res.success: print(f"Calibrated {self.name}: Loss {res.fun:.4f}")
		return res

#	Constants
DMG_PEN   = 0.1
DMG_PILOT = 1.0
DMG_TITAN = 2.5






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
		
		mass_kg = params["mass_gr"] * CONST_GR_G * 0.001
		v0_ms = params["v0_fps"] * CONST_FT_M

		bc_kgm2 = params["bc_kgm2"]
		cal_mm = params["cal_mm"]

		# Sectional density in lbm / sq in
		self.sd = (mass_gr/7000.) * (cal_mm/25.4)**-2

		#	Superclass
		super().__init__(name)
		self.config.update({
			# Name			Default		Tune?	Min		Max
			"arm_const":	(ARM_HFVEL,	True,	10.0,	1e3  ),
			"arm_pilot":	(ARM_PILOT,	True,	0.0,	1e2  ),
			"arm_titan":	(ARM_TITAN,	True,	0.0,	5e2	 ),

			"mass_kg":		(mass_kg,	True,	5e-5,	0.1  ),
			"v0_ms":		(v0_ms,		True,	2e2,	3500 ),			
			"bc_kgm2":		(bc,		True,	5e1,	6e2  ),

			"cal_mm":		(cal_mm,	True,	3,		30   ),
			#"len_cal":   	(len,		True,	1.0,	5.5	 ),
			#"twist":		(twist,		True,	7.0,	24.0 ),
			#"tumble_mod":	(0.5,		True,	0.0,	2.0  ),
		})

	def _drag(self, v_ms):
		mach = v_ms / CONST_MACH
		table = DRAG_TABLES.get(self.model, DRAG_TABLES["G1"])
		return np.interp(mach, table[0], table[1])

	def _phys_at(self, dist_hu):
		#	Initial
		dist_m = dist_hu * CONST_HU_M
		v0 = self.get("v0_ms")
		bc = max(self.get("bc_kgm2"), 1.0)
		
		# Mach drag
		cd0 = self._drag(v0)
		k0 = cd0 / bc

		# Stability, tumble
		v0_fps = v0 / CONST_FT_M
		sg0 = sg(v_fps0)

		#	Final
		# Velocity
		v1 = v0 / (1.0 + v0 * k0 * dist_m)

		# Penetration
		pen = (0.5*m*v1*v1) * self.sd #* dmg_mult

		# Return phys
		return vel, pen

	def _dmg_scale(self, dist_hu, v_ms, pen, isHeavyArmor):
		return pen

	def damage_at(self, dist_hu, isHeavyArmor):
		vel, pen = self._phys_at(dist_hu)
		pen = self._dmg_scale(dist_hu, vel, pen)
		
		# Armor calculation
		armor = self.get("arm_titan") if isHeavyArmor else self.get("arm_pilot")
		armor_eff = armor * self.get("arm_const") / np.maximum(vel, 1.)
		dr = 1. / (1. + armor_eff)
		
		# Damage
		damage = dr * pen/self.get("dmg_scale")
		damage = damage * self.get("dmg_titan") if isHeavyArmor else self.get("dmg_pilot")

		return np.maximum(damage, 0.)
	
	def bake(self, ref):
		"""
		Creates a 'Baked' VanillaFalloff by sampling this physics model
		at the reference curve's Near/Far/VeryFar distances.
		"""
		# 1. Clone the reference (Vanilla) curve to keep distances/structure
		baked = copy.deepcopy(ref)
		baked.name = f"{self.name}_baked"

		# 2. Get the distances where the game engine samples damage
		d_near = baked.data.get("damage_near_distance", 0)
		d_far  = baked.data.get("damage_far_distance", 0)
		d_vfar = baked.data.get("damage_very_far_distance", 0)

		# 3. Calculate Physics Damage at those exact points and overwrite values
		# Pilot
		baked.data["damage_near_value"] = self.damage_at(d_near, False)
		baked.data["damage_far_value"]  = self.damage_at(d_far, False)
		baked.data["damage_very_far_value"] = self.damage_at(d_vfar, False)

		# Titan
		baked.data["damage_near_value_titanarmor"] = self.damage_at(d_near, True)
		baked.data["damage_far_value_titanarmor"]  = self.damage_at(d_far, True)
		baked.data["damage_very_far_value_titanarmor"] = self.damage_at(d_vfar, True)

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

		sg = (30*m)/(t*t*d*d*d*l*(1+l*l)) * np.cbrt(v_fps / 2800)
		return 1.0/(1.0 + np.exp(10.0 * (sg - 0.95))) 			# Sigmoid to estimate stability

	def _drag(self, v_ms):
		cd_base = super()._drag(v_ms)
		stable = self._stability(vel_ms)
		return cd_base * (1.0 + stable*3.0)

	def _dmg_scale(self, dist_hu, vel_ms, pen, isHeavyArmor):
		stable = self._stability(vel_ms)
		mult = 1.0 + stable*(self.get("tumble") - 1.0)
		return pen * mult

class ShotgunFalloff(BallisticFalloff):
	def __init__(self, params, pellets, spread):
		super().__init__(params)
		self.config.update({
			# Name		Default		Tune?	Min		Max
			"pellets":	(pellets,	False,	1,		50	),
			"spread":	(spread,	True, 	0.1,	15.0),
			"sz_pilot":	(0.5,		False,	0.3,	1.0	),
			"sz_titan":	(3.5,		False,	2.0,	6.0	),
		})
	
	def _dmg_scale(self, dist_hu, vel_ms, pen, isHeavyArmor):
		dist_m = np.maximum(dist_hu * CONST_HU_M, 0.1)

		sz_tgt = self.get("sz_titan") if isHeavyArmor else self.get("sz_pilot")
		r_tgt  = sz_tgt / 2.0

		spread = dist_safe * np.tan(np.radians(self.get("spread")))
		prob_hit = np.clip(np.pow(sz_tgt/spread, 2), 0.0, 1.0)

		return pen * self.get("pellets") * hit_prob

# ===== Plotting utils =====
class FalloffGUI:
	def __init__(self, vanilla, physics, dist_max = 5000, dist_ct = 2):
		self.vanilla = vanilla; self.physics = physics
		self.baked = self.physics.bake(self.vanilla)

		#	Figure, subplots
		self.fig, (self.ax_p, self.ax_t) = plt.subplots(2, 1, sharex=True, figsize=(10, 8))
		plt.subplots_adjust(right=0.7, hspace=0.3)

		#	Data
		self.dists = np.linspace(0, dist_max, dist_ct)

		#	Functions
		self._funcs()
		self._graph()
		self._controls()

		plt.show()

	def _funcs(self):
		self.fnPhysP = np.vectorize(lambda d: self.fc.damage_at(d, False))
		self.fnIntrP = np.vectorize(lambda d: self.fc.damage_lerp(d, False, False))
		self.fnGameP = np.vectorize(lambda d: self.fc.damage_lerp(d, False, True))

		self.fnPhysT = np.vectorize(lambda d: self.fc.damage_at(d, True))
		self.fnIntrT = np.vectorize(lambda d: self.fc.damage_lerp(d, True, False))
		self.fnGameT = np.vectorize(lambda d: self.fc.damage_lerp(d, True, True))

	def _graph(self):
		#	Plot
		# Titles/labels/legend
		self.ax_p.clear()
		self.ax_t.clear()

		self.ax_p.set_title(f"{self.wf.name}: Pilot")
		self.ax_t.set_title(f"{self.wf.name}: Titan")

		self.ax_p.set_ylabel("Damage")
		self.ax_t.set_ylabel("Damage")
		self.ax_t.set_xlabel("Distance (hu)")

		self.ax_p.grid(True, alpha=0.25)
		self.ax_t.grid(True, alpha=0.25)

		# Plot
		self.axPhysP = self.ax_p.plot(self.dists, self.fnPhysP(self.dists), ':', color='grey', alpha=0.5, label='Modeled')
		self.axPhysT = self.ax_t.plot(self.dists, self.fnPhysT(self.dists), ':', color='grey', alpha=0.5, label='Modeled')

		self.axIntrP = self.ax_p.plot(self.dists, self.fnIntrP(self.dists), '--', color='orange', alpha=0.6, label='Interpolated')
		self.axIntrT = self.ax_t.plot(self.dists, self.fnIntrT(self.dists), '--', color='cyan', alpha=0.6, label='Interpolated')

		self.axGameT = self.ax_p.plot(self.dists, self.fnGameP(self.dists), '-', color='red', alpha=0.8, label='Vanilla')
		self.axGameT = self.ax_t.plot(self.dists, self.fnGameT(self.dists), '-', color='blue', alpha=0.8, label='Vanilla')
		
		self.ax_p.legend()
		self.ax_t.legend()

	def _controls(self):
		# Identify tunable parameters
		params = [k for k, v in self.fc.config.items() if v[1]]

		# Formatting
		ax_color = 'lightgoldenrodyellow'
		start_y = 0.85; spacing = 0.04

		# Print button
		ax_btn = plt.axes([0.70, 
			start_y - (len(tunables) * spacing) - 0.05, 
			0.1,
			0.04
		])
		self.btn = Button(ax_btn, 'Print', hovercolor='0.975')
		self.btn.on_clicked(self._print)

		for i, key in enumerate(tunables):
			val, _, v_min, v_max = self.fc.config[key]

			slider_ax = plt.axes(
				[0.70, start_y - (i * spacing), 0.20, 0.03],
				facecolor=ax_color
			)
			slider = Slider(
				ax			=	slider_ax,
				label		=	key,
				orientation	=	'horizontal',
				
				valinit		=	val,
				valmin		=	min_v,
				valmax		=	max_v,
			)

			slider.on_changed(self._updater(key))
			self.sliders.append(slider)

	def _updater(self, key):
		def update(val):
			# Update config/functions
			self.fc.set(key, val)
			self._funcs()

			# Update plots
			self.axPhysP.set_ydata(self.fnPhysP(self.dists))
			self.axPhysP.set_ydata(self.fnPhysT(self.dists))

			self.axIntrP.set_ydata(self.fnIntrP(self.dists))
			self.axIntrP.set_ydata(self.fnIntrT(self.dists))
            
            # Redraw
			self.fig.canvas.draw_idle()
		return update
	
	def _print(self, event):
		title = f"\n=== {self.fc.name} ==="

		print(title)
		for k, v in self.fc.config.items():
			if v[1]: print(f"'{k}': {v[0]:.4f},")
		print("="*len(title)+"\n")

# ===== Main Execution =====
if __name__ == "__main__":
	parser = argparse.ArgumentParser(description="TF|2 Falloff Calc")
	parser.add_argument("weapon", help="Internal name (e.g. mp_weapon_rspn101)")
	args = parser.parse_args()

	# 1. Lookup Weapon
	if args.weapon not in WEAPON_DB:
		print(f"Error: '{args.weapon}' not in database.")
		print("Available:", ", ".join(WEAPON_DB.keys()))
		sys.exit(1)

	db_entry = WEAPON_DB[args.weapon]

	# 2. Fetch Vanilla Data
	wf = WeaponFalloff(args.weapon)
	success = wf.fetch()
	if not success: print("Proceeding without vanilla comparison...")

	# 3. Initialize Physics Model
	print(f"Loading Physics for: {db_entry['name']}")
	if db_entry["type"] == "rifle": model = RifleFalloff(db_entry["params"], **db_entry["spec"])
	elif db_entry["type"] == "shotgun": model = ShotgunFalloff(db_entry["params"], **db_entry["spec"])
	else: print("Unknown weapon type."); sys.exit(1)

	# 4. Launch GUI
	gui = FalloffGUI(wf, model)