local bit32, addressbus = computech.bit32, computech.addressbus
local tilebox = {
	type = "fixed",
	fixed = {{-0.5, -0.5, -0.5, 0.5, -0.3, 0.5}},
}

-- Digiline I/O Chip Specification
-- 0x00-0x03: S/ID Shorts: 0x0010, 0x0001 (0x00100001)
-- 0x04-0x07: Channel Buffer Loc.
-- 0x08-0x0B: Data Buffer Loc.
-- 0x0C: Channel Buffer Size.
-- 0x0D: Data Buffer Size.
-- 0x0E: Command Byte. Always reads 0, writing can cause things.
--       Command 0: NOP.
--       Command 1: Send a message over the Digiline bus.
--       Command 2: Read a message on the Digiline bus.
--       Command 3: Confirm interrupt enable.
-- 0x0F: Available messages counter.
-- If interrupts are enabled,
--  this device will fire an interrupt when a message is received,
--  unless there is a message waiting.
local function dio_reset(pos)
	local meta = minetest.get_meta(pos)
	meta:set_int("buffers", 0)
end
local function dio_digiline()
	-- TODO.
end
local function dio_send_buffers(pos)
	local meta = minetest.get_meta(pos)
	local buffer_count = meta:get_int("buffers")
	for i = 1, buffer_count do
		-- send buffer?
	end
	return false -- stop timer
end
minetest.register_node("computech_addressbus:digiline_io", {
	description = "Computech Digiline IO Chip <NOP. TODO.>",
	tiles = {"computech_addressbus_dio_top.png", "computech_addressbus_dio_top.png",
		"computech_addressbus_port.png", "computech_addressbus_port.png",
		"computech_addressbus_port.png", "computech_addressbus_port.png"},
	paramtype = "light",
	drawtype = "nodebox",
	node_box = tilebox,
	groups = {dig_immediate = 2, computech_addressbus_cable = 1},
	on_construct = dio_reset,
	on_timer = dio_send_buffers,
	digiline = {
		receptor = {},
		effector = {
			action = dio_digiline
		},
	},
	computech_addressbus = {
		extent = function (pos, msg, dir)
			msg.respond(0x10)
		end
	}
})
