-- computech-base mostly provides a set of helpers for other mods.
-- It does pretty much nothing on it's own.

computech = {
	loaded_modules = {},
}

-- Loading helper
computech.modpath_base = minetest.get_modpath("computech_base")
function computech.load_base(name, ...)
	local fp = computech.modpath_base .. "/modules/" .. assert(name, "need filename") .. ".lua"
	io.write("[computech_base] I: Loading '"..name.."'...")
	local tmp = loadfile(fp)(...)
	print(" Done.")
	return tmp
end
--[[function computech.insecure_load_base(ie, name, ...)
	local fp = computech.modpath_base .. "/modules/" .. assert(name, "need filename") .. ".lua"
	io.write("[computech_base] I: Loading '"..name.."'...")
	local tmp = ie.loadfile(fp)(...)
	print(" Done.")
	return tmp
end

-- Mod security requesting thing.
local insenv, req_ie = _G, minetest.request_insecure_environment
if req_ie then insenv = req_ie() end
if not insenv then
	local msg = "computech_base requires access to insecure functions to function correctly. Please add computech_base to your secure.trusted_mods."
	print("[computest_base] W: "..msg)
	minetest.chat_send_all("[computest_base] "..msg)
end

-- Lazy loading
-- We lazy-load modules to not load useless things if they are not used.
-- Or rather, we would, if mod security would allow it. But apparently it takes the calling mod into account, so that falls flat.
function computech.lazy_load(ie, name)
	local tmp = computech[assert(name, "need filename")] or {}
	setmetatable(tmp, {
		__index = function(t, key)
			setmetatable(t, nil)
			local res = computech.insecure_load_base(ie, name, ie)
			computech[name] = res
			computech.loaded_modules[name] = true
			return res[key]
		end
	})
	computech[name] = tmp
end--]]

-- Mark available modules
computech.base_modules = {
	"strutils",
	"msgpack",
	"com",
	"cmds",
	"bettertimers",
	"bit32"
}

for i=1, #computech.base_modules do
	local name = computech.base_modules[i]
	--[[if insenv then -- insecure is there, lazy loading
		computech.loaded_modules[name] = false
		computech.lazy_load(insenv, name) -- does not work, because of mod security. :|
	else--]]
		computech[name] = computech.load_base(name)
		computech.loaded_modules[name] = true
	--end
end

-- Chat command helper
local _cmd_not_found = function()
	return false, "No such subcommand. Try 'list', perhaps?"
end

minetest.register_chatcommand("computech", {
	privs = {
		server = true,
	},
	func = function(name, param)
		local args = computech.strutils.split(param, " ")
		local fn = args[1]
		table.remove(args, 1)

		if fn == nil then
			fn = "list-cmds"
		end

		return (computech.cmds[fn] or _cmd_not_found)(name, args)
	end,
})
