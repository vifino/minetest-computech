-- A Digilines console!

local console_lines = 6

local function console_gui(pos)
	local meta = minetest.get_meta(pos)
	local formspec = "size[8," .. ((console_lines / 2) + 1) .. "]"
	for l = 1, console_lines do
		formspec = formspec .. "label[0, " .. ((l - 1) / 2) .. ";" .. minetest.formspec_escape(meta:get_string("c" .. l)) ..  "]"
	end
	local hd = ((console_lines / 2) + 0.5)
	formspec = formspec .. "button[6," .. hd .. ";2,1;submit;Send]"
	                    .. "field[1," .. hd .. ";5,1;stext;;]"
	meta:set_string("formspec", formspec)
	meta:set_string("infotext", "Digiline Console, channels:\n'console', 'keyboard'")
end

-- A simple comprehensive function to emulate a really basic terminal.
local function console_append(pos, str)
	local meta = minetest.get_meta(pos)
	while str:len() > 0 do
		if str:sub(1, 1) == "\n" then
			for l = 1, console_lines - 1 do
				meta:set_string("c" .. l, meta:get_string("c" .. (l + 1)))
			end
			meta:set_string("c" .. console_lines, "")
			str = str:sub(2)
		else
			local substr = str:gmatch("[^\n]+")()
			if not substr then return end
			meta:set_string("c" .. console_lines, meta:get_string("c" .. console_lines) .. substr)
			str = str:sub(substr:len() + 1)
		end
	end
end

local function console_rfields(pos, _, fields, sender)
	local meta = minetest.get_meta(pos)
	if fields["submit"] then
		local t = tostring(fields["stext"]) .. "\n"
		console_append(pos, t)
		digiline:receptor_send(pos, digiline.rules.default, "keyboard", t)
	end
	console_gui(pos)
end

local function console_reset(pos)
	local meta = minetest.get_meta(pos)
	for l = 1, console_lines do
		meta:set_string("c" .. l, "")
	end
	console_gui(pos)
end

local function console_digiline(pos, node, channel, msg)
	if channel == "console" then
		console_append(pos, tostring(msg))
	end
end

minetest.register_node("computech_console:console", {
	groups = {dig_immediate = 2},
	param2 = "facedir",
	tiles = {"computech_console_block.png", "computech_console_block.png",
		"computech_console_ridge.png", "computech_console_ridge.png",
		"computech_console_ridge.png", "computech_console_screen.png"},
	description = "Digilines Console",
	on_construct = console_reset,
	on_punch = console_reset,
	on_receive_fields = console_rfields,
	digiline = {
		receptor = {},
		effector = {
			action = console_digiline
		},
	},
})
