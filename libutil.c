/* SPDX-License-Identifier: MIT */
/*
 * Copyright (c) 2026 Honbo He, <hehongbo918@gmail.com>
 *
 * misc POSIX utilities for Lua
 */
#include <errno.h>
#include <libgen.h>
#include <stdlib.h>
#include <string.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#define LIBUTIL_PATHBUF 512

typedef char * (*libutil_pathfn)(char *);

static int libutil_pathpart(lua_State * L, libutil_pathfn fn)
{
	char stackbuf[LIBUTIL_PATHBUF];
	char * buf = stackbuf;
	const char * path;
	size_t len;

	if (lua_type(L, 1) != LUA_TSTRING) {
		lua_pushnil(L);
		lua_pushinteger(L, EINVAL);
		return 2;
	}

	path = lua_tolstring(L, 1, &len);
	if (memchr(path, '\0', len) != NULL) {
		lua_pushnil(L);
		lua_pushinteger(L, EINVAL);
		return 2;
	}

	if (len >= sizeof(stackbuf)) {
		buf = malloc(len + 1);
		if (buf == NULL) {
			lua_pushnil(L);
			lua_pushinteger(L, ENOMEM);
			return 2;
		}
	}

	memcpy(buf, path, len);
	buf[len] = '\0';
	lua_pushstring(L, fn(buf));
	if (buf != stackbuf)
		free(buf);
	return 1;
}

static int libutil_basename(lua_State * L)
{
	return libutil_pathpart(L, basename);
}

static int libutil_dirname(lua_State * L)
{
	return libutil_pathpart(L, dirname);
}

static const struct luaL_Reg libutil_regs[] = {
	{ "basename",            libutil_basename },
	{ "dirname",             libutil_dirname },
	{ NULL, NULL }
};

int luaopen_libutil(lua_State * L)
{
	luaL_register(L, "libutil", libutil_regs);

	return 1;
}
