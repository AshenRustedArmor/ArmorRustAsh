# Coordinates
**Vector**:
*	X:	+Fwd  / -Back
*	Y:	+Left / -Right
*	Z:	+Up	  / -Down

**Angles**:
*	Pitch (X):	+Down / -Up
*	Yaw	  (Z):	+Left / -Right
*	Roll  (Y):	+CCW  / -CW	

#	Functions
**Conversion**
VectorToAngles
	Inputs:		vector
	Outputs:	angles
> Computes the Euler angles `<pitch, yaw, 0>` required to look along the
> given direction vector. 3D vectors provide no roll information.

AnglesToVector
	Inputs		angles
	Outputs:	vector
> Alternate alias for `AnglesToForward`, providing the forward vector.

**Relative**
AnglesToForward
	Inputs		angles
	Outputs:	vector
> Computes the directional unit vector pointing **forward** within the given
> orientation, discarding any roll information. This is `+X` in worldspace.

AnglesToRight
	Inputs		angles
	Outputs:	vector
> Computes the directional unit vector pointing **rightward** within the given
> orientation. This is `-Y` in worldspace, but `+Y` in orientation space.

AnglesToUp
	Inputs		angles
	Outputs:	vector
> Computes the directional unit vector pointing **upward** within the given
> orientation, discarding the roll component of the input orientation.