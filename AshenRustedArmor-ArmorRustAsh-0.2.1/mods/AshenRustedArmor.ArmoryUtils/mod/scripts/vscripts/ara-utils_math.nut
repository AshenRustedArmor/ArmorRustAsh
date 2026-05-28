globalize_all_functions

int function ArmoryUtil_WeightedRound( float x ) {
	int intPart = x.tointeger()
	float floatPart = x - intPart

	return (RandomFloatRange( 0.0, 1.0 ) > fabs( floatPart )) ? intPart : intPart + 1
}

float function ArmoryUtil_SmoothMin( float a, float b, float k ) {
    float h = max( k - fabs(a - b), 0.0 ) / k;
    return min( a, b ) - h*h * k * (1.0 / 4.0);
}

array<float> function ArmoryUtil_Range( float a, float b, int count ) {
	array<float> arr
	if( count == 0 ) return arr

	int absCt = count < 0 ? -count : count
	float start  = count < 0 ? b : a
	float end    = count < 0 ? a : b

	if (absCt == 1) {
		arr.append(start)
		return arr
	}

	for (int i = 0; i < absCt; i++) {
		float val = GraphCapped(i*1., 0., absCt - 1.0, start, end)
		arr.append(val)
	}

	return arr
}


vector function ArmoryUtil_VecHadamard( vector a, vector b ) {
	return Vector(a.x * b.x, a.y * b.y, a.z * b.z)
}

