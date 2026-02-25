Usage

(load the module.lua via loadstring)

SmartTween({
	Target = Object to move,
	Position = Vector3.new(x, y, z),
	ConstantSpeed = {true or false, speed in studs per second},
	Time = tween time, if constandspeed is true - ignored,
	EasingStyle = Enum.EasingStyle.Linear, <-- easing style
	EasingDirection = Enum.EasingDirection.Out, <-- easing direction
	ShowWaypoints = true, <-- show smart waypoints
	Callback = function()
  <--> function is ran when end is reached
  end
})
