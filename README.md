# computech
computech is a set of mods that are adding a series of computers, accessories and more to MineTest.

## Modules
 - computech_base
   - Base APIs for all computech mods. Provides no blocks and barely any features stand alone.
 - computech_machine_forth
   - A forth machine. Unlike LuaControllers, it has a clock and does not depend on external events.
   - It's not great, has issues regarding security, etc... Don't use. Really.
 - computech_addressbus
   - Infrastructure providing the basics of addressbus, a bus used by other machines.
 - computech_machine_zpu
   - This is the fun stuff! A ZPU processor emulated in minetest. Use with addressbus stuff.

# License
MIT.
