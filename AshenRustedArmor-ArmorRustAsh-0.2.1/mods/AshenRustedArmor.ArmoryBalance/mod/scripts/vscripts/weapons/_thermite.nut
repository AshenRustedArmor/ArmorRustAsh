struct {
	int count = 0

	array<int>		dmgPilot
	array<int>		dmgTitan

	array<float>	radInner
	array<float>	radOuter

	array<float>	timeStart
	array<float>	timeLife

	array<entity>	owner
	array<entity>	weapon
} ComponentThermiteDamage