-- Chat commands!
-- Mostly informative.

local cmds = {}

-- List commands
function cmds.list()
	-- Return a list of available subcommands.
	table.sort(computech.cmds) -- because order, yay.

	local str = "Available sub-commands: "
	for k, _ in pairs(computech.cmds) do
		str = str .. k .. " "
	end
	
	return true, str
end

return cmds
