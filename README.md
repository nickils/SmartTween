Usage Example:
-- Either copy the raw code or use loadstring
local HttpService = game:GetService("HttpService")

-- Fetch the raw code from the GitHub URL
local code = HttpService:GetAsync("https://raw.githubusercontent.com/nickils/SmartTween/refs/heads/main/Module.lua")

-- Execute the code to define the 'SmartTween' function globally in this script
-- Ensure "Allow LoadString" and "Allow HTTP Requests" are enabled in Game Settings > Security
loadstring(code)()

-- Call the function with your specific configuration
SmartTween({
	Target = workspace:WaitForChild("Move"), -- The object being moved
	Position = Vector3.new(84.5, 12.5, -9),   -- The goal destination
	ConstantSpeed = {true, 16},              -- Uses 16 studs per second (ignores Time)
	Time = 5,                                -- Only used if ConstantSpeed first value is false
	EasingStyle = Enum.EasingStyle.Linear,   -- Movement style
	EasingDirection = Enum.EasingDirection.Out,
	ShowWaypoints = true,                    -- Shows the pathfinding dots in the world
	Callback = function()                    -- Runs when the destination is reached
		print("Reached the destination")
	end
})
