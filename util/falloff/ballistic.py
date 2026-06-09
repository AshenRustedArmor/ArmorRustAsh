
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
			"arm_const":	[1e0,		True,	0.1,	5e2  ],
			"arm_pilot":	[10.0,		False,	5.0,	5e1  ],
			"arm_titan":	[15.0,		False,	10.0,	1e2	 ],

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
		return r * r * np.pi

	def _prob(self, dist_hu, tgt_rad):
		return 1.0

	# ====== Model impl ======
	def _phys_flight(self, dist_hu):
		#	Muzzle
		v0	= self.get("v0_ms")
	
		#	Impact
		# Velocity
		cd0 = self._drag(v0)
		k0  = cd0 / np.maximum(self.get("bc_kgm2"), 1.0)
		
		d_m	= dist_hu * CONST_HU_M
		v_I	= v0 * np.exp(-k0 * d_m)
		
		# Energy
		m	= self.get("mass_kg")
		e_I	= 0.5 * m * v_I * v_I

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
		
		arm_satur	= e_I / np.maximum(arm_resist, 1.0)
		arm_trans	= 1.0 / ( 1.0 + np.exp(-10.0 * (arm_satur - 0.85)) )
		arm_spall	= 1.0 + np.clip((arm_satur - 1.1) * 5.0, 0.0, 1.0) * 0.2
		arm_shock	= a_I / a_ref

		return e_I * arm_satur * arm_trans * arm_spall * arm_shock

	def damage_at(self, dist_hu, isHeavyArmor):
		tgt_armor = self.get("arm_titan") if isHeavyArmor else self.get("arm_pilot")
		tgt_area  = SZ_TITAN if isHeavyArmor else SZ_PILOT

		pen  = self._phys_impact(dist_hu, tgt_armor)
		prob = self._prob(dist_hu, tgt_area)

		tgt_mod	= self.get("dmg_titan") if isHeavyArmor else self.get("dmg_pilot")
		return pen * prob * tgt_mod * np.pow(10, -self.get("dmg_scale"))

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
		points = solve(func, B=3500, n=3) #[0]; points.extend()

		baked.data["damage_near_distance"]				= points[0]
		baked.data["damage_far_distance"]				= points[1]
		baked.data["damage_very_far_distance"]			= points[2]

		baked.data["damage_near_value"]					= self.damage_at(0.0, False) #points[0]
		baked.data["damage_far_value"]					= self.damage_at(points[1], False)
		baked.data["damage_very_far_value"]				= self.damage_at(points[2], False)

		baked.data["damage_near_value_titanarmor"]		= self.damage_at(0.0, True) #points[0]
		baked.data["damage_far_value_titanarmor"]		= self.damage_at(points[1], True)
		baked.data["damage_very_far_value_titanarmor"]	= self.damage_at(points[2], True)

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

	def _area(self, v_ms):
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