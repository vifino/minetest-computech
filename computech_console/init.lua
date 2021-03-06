-- A Digilines console!

-- Amount of lines in the console.
local console_lines = 8

-- Line height in slots.
local console_lh = 0.35

-- Estimated.
local console_width = 400

-- lines -> node names
local console_mapping = {}

local function console_cpx(l, lwu)
	if l == " " then if lwu then return 6 else return 3 end end
	if l == "a" then return 9 end
	if l == "f" then return 5 end
	if l == "i" then return 3 end
	if l == "l" then return 3 end
	if l == "m" then return 13 end
	if l == "t" then return 5 end
	if l == ":" then return 5 end
	if l == ";" then return 5 end
	if l == "(" then return 5 end
	if l == ")" then return 5 end
	if l == "{" then return 5 end
	if l == "}" then return 5 end
	if l == "[" then return 5 end
	if l == "]" then return 5 end
	if l == "\\" then return 5 end
	if l == "/" then return 5 end
	if l == "'" then return 3 end
	if l == "`" then return 5 end
	if l == l:upper() then return 10, true end
	return 8
end
local function console_lpx(line)
	local px = 0
	local upper = false
	for i = 1, line:len() do
		if line:byte(i) < 128 then
			-- avoid chars > 127 so they can't get cut
			local sz, lu = console_cpx(line:sub(i, i), upper)
			upper = lu
			px = px + sz
		end
	end
	return px
end
local function console_gui(pos, first)
	local meta = minetest.get_meta(pos)
	local formspec = "size[8," .. ((console_lines * console_lh) + 1) .. "]"
	local console = {}
	local firstline = console_lines + 1
	for l = 1, console_lines do
		console[l] = meta:get_string("c" .. l) or ""
		if console[l]:len() > 0 then
			firstline = math.min(firstline, l)
		end
	end
	for l = 1, console_lines do
		local n = minetest.get_node(pos)
		if n and (not first) then
			local maxlines = (console_lines + 1) - firstline
			local wanted = console_mapping[maxlines]
			if wanted then
				if n.name ~= wanted then
					minetest.set_node(pos, {name = wanted, param2 = n.param2})
				end
			else
				print("computech_console: edge case!")
			end
		end
		formspec = formspec .. "label[0, " .. ((l - 1) * console_lh) .. ";" .. minetest.formspec_escape(console[l]) ..  "]"
		meta:set_string("c" .. l, console[l])
	end
	local hd = ((console_lines * console_lh) + 0.5)
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
			local res = meta:get_string("c" .. console_lines) .. substr
			str = str:sub(substr:len() + 1)
			local ext = ""
			while console_lpx(res) > console_width do
				ext = res:sub(res:len()) .. ext
				res = res:sub(1, res:len() - 1)
			end
			meta:set_string("c" .. console_lines, res)
			if ext ~= "" then
				str = "\n" .. ext .. str
			end
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

local function console_reset(pos, first)
	local meta = minetest.get_meta(pos)
	for l = 1, console_lines do
		meta:set_string("c" .. l, "")
	end
	console_gui(pos, first)
end

local function console_digiline(pos, node, channel, msg)
	if channel == "console" then
		console_append(pos, tostring(msg))
		console_gui(pos)
	end
end

for i = 0, console_lines do
	local scrtexlen, scrtexpos = 8, 4
	local point = ((i / console_lines) * (scrtexlen / 16)) + (scrtexpos / 16)
	local screen = "computech_console_screen.png^[lowpart:" .. math.floor(point * 100) .. ":computech_console_screen_ovl.png"
	local ip = tostring(i)
	if i == 0 then ip = "" end
	local n = "computech_console:console" .. ip
	console_mapping[i] = n
	local g = {dig_immediate = 2}
	if i ~= 0 then
		g.not_in_creative_inventory = 1
	end
	minetest.register_node(n, {
		groups = g,
		paramtype = "light",
		paramtype2 = "facedir",
		drop = "computech_console:console",
		light_source = math.floor((i / console_lines) * 10),
		tiles = {"computech_console_block.png", "computech_console_block.png",
			"computech_console_ridge.png", "computech_console_ridge.png",
			"computech_console_ridge.png", screen},
		description = "Digilines Console",
		on_construct = function (pos) console_reset(pos, true) end,
		on_punch = function (pos) console_reset(pos, false) end,
		on_receive_fields = console_rfields,
		digiline = {
			receptor = {},
			effector = {
				action = console_digiline
			},
		},
	})
end
