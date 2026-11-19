package = "lua-sysbox"
version = "scm-0"

source = {
	url = "git+https://github.com/realhonbo/lua-sysbox.git",
}

description = {
	summary = "Misc POSIX system utilities for Lua",
	homepage = "https://github.com/realhonbo/lua-sysbox",
	license = "MIT",
}

dependencies = {
	"lua >= 5.1",
}

build = {
	type = "make",

	build_target = "all",
	build_variables = {
		CC = "$(CC)",
		LUA_INCDIR = "$(LUA_INCDIR)",
	},

	install = {
		lib = {
			["libutil"] = "libutil.so",
			["syscall"] = "syscall.so",
		},
		lua = {
			["appbox"] = "appbox.lua",
		},
	},
}
