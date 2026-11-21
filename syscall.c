/* SPDX-License-Identifier: MIT */
/*
 * Copyright (c) 2026 Honbo He, <hehongbo918@gmail.com>
 *
 * system call wrappers for Lua
 */
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sendfile.h>
#include <sys/stat.h>
#include <unistd.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

static int syscall_open(lua_State * L)
{
	const char * path, * str;
	char * end;
	size_t len;
	long val;
	mode_t mode = 0;
	int fd, flags, need_mode;
	lua_Number num;

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

	/* flags: mandatory, as in open(2) */
	if (lua_type(L, 2) != LUA_TNUMBER) {
		lua_pushnil(L);
		lua_pushinteger(L, EINVAL);
		return 2;
	}
	num = lua_tonumber(L, 2);
	if (num < INT_MIN || num > INT_MAX || num != (lua_Number) (int) num) {
		lua_pushnil(L);
		lua_pushinteger(L, EINVAL);
		return 2;
	}
	flags = (int) num;

	/* mode: mandatory with O_CREAT/O_TMPFILE, otherwise ignored like open(2) */
	need_mode = (flags & O_CREAT) != 0;
#ifdef O_TMPFILE
	if ((flags & O_TMPFILE) == O_TMPFILE)
		need_mode = 1;
#endif
	if (need_mode) {
		if (lua_isnoneornil(L, 3)) {
			lua_pushnil(L);
			lua_pushinteger(L, EINVAL);
			return 2;
		}
		if (lua_type(L, 3) == LUA_TSTRING) {
			str = lua_tostring(L, 3);
			errno = 0;
			val = strtol(str, &end, 8);
			if (errno != 0 || end == str || *end != '\0') {
				lua_pushnil(L);
				lua_pushinteger(L, EINVAL);
				return 2;
			}
		} else {
			if (lua_type(L, 3) != LUA_TNUMBER) {
				lua_pushnil(L);
				lua_pushinteger(L, EINVAL);
				return 2;
			}
			num = lua_tonumber(L, 3);
			if (num < 0 || num > UINT_MAX || num != (lua_Number) (long) num) {
				lua_pushnil(L);
				lua_pushinteger(L, EINVAL);
				return 2;
			}
			val = (long) num;
		}
		if (val < 0 || (unsigned long) val > UINT_MAX) {
			lua_pushnil(L);
			lua_pushinteger(L, EINVAL);
			return 2;
		}
		mode = (mode_t) val;
	}

	fd = open(path, (int) flags, mode);

	if (fd < 0) {
		lua_pushnil(L);
		lua_pushinteger(L, errno);
		return 2;
	}
	lua_pushinteger(L, fd);
	return 1;
}

static int syscall_read(lua_State * L)
{
	char * buf;
	size_t count;
	ssize_t ret;
	int fd;
	lua_Number num;

	if (lua_type(L, 1) != LUA_TNUMBER) {
		lua_pushnil(L);
		lua_pushinteger(L, EBADF);
		return 2;
	}
	num = lua_tonumber(L, 1);
	if (num < INT_MIN || num > INT_MAX || num != (lua_Number) (int) num) {
		lua_pushnil(L);
		lua_pushinteger(L, EBADF);
		return 2;
	}
	fd = (int) num;

	if (lua_type(L, 2) != LUA_TNUMBER) {
		lua_pushnil(L);
		lua_pushinteger(L, EINVAL);
		return 2;
	}
	num = lua_tonumber(L, 2);
	if (num < 0 || num > SSIZE_MAX || num != (lua_Number) (size_t) num) {
		lua_pushnil(L);
		lua_pushinteger(L, EINVAL);
		return 2;
	}
	count = (size_t) num;

	buf = malloc(count > 0 ? count : 1);
	if (buf == NULL) {
		lua_pushnil(L);
		lua_pushinteger(L, ENOMEM);
		return 2;
	}

	ret = read(fd, buf, count);
	if (ret < 0) {
		lua_pushnil(L);
		lua_pushinteger(L, errno);
		free(buf);
		return 2;
	}
	lua_pushlstring(L, buf, (size_t) ret);
	free(buf);
	return 1;
}

static int syscall_write(lua_State * L)
{
	const char * data;
	size_t len;
	ssize_t ret;
	int fd;
	lua_Number num;

	if (lua_type(L, 1) != LUA_TNUMBER) {
		lua_pushnil(L);
		lua_pushinteger(L, EBADF);
		return 2;
	}
	num = lua_tonumber(L, 1);
	if (num < INT_MIN || num > INT_MAX || num != (lua_Number) (int) num) {
		lua_pushnil(L);
		lua_pushinteger(L, EBADF);
		return 2;
	}
	fd = (int) num;

	if (lua_type(L, 2) != LUA_TSTRING) {
		lua_pushnil(L);
		lua_pushinteger(L, EINVAL);
		return 2;
	}
	data = lua_tolstring(L, 2, &len);

	ret = write(fd, data, len);
	if (ret < 0) {
		lua_pushnil(L);
		lua_pushinteger(L, errno);
		return 2;
	}
	lua_pushinteger(L, (lua_Integer) ret);
	return 1;
}

static int syscall_close(lua_State * L)
{
	long fd;
	lua_Number num;

	if (lua_type(L, 1) != LUA_TNUMBER) {
		lua_pushnil(L);
		lua_pushinteger(L, EBADF);
		return 2;
	}
	num = lua_tonumber(L, 1);
	if (num < INT_MIN || num > INT_MAX || num != (lua_Number) (int) num) {
		lua_pushnil(L);
		lua_pushinteger(L, EBADF);
		return 2;
	}
	fd = (int) num;

	if (close(fd) < 0) {
		lua_pushnil(L);
		lua_pushinteger(L, errno);
		return 2;
	}
	lua_pushboolean(L, 1);
	return 1;
}

static int syscall_sendfile(lua_State * L)
{
	int out_fd, in_fd;
	size_t count;
	off_t offset = 0, * offp = NULL;
	ssize_t ret;
	lua_Number num;

	/* out_fd: mandatory, as in sendfile(2) */
	if (lua_type(L, 1) != LUA_TNUMBER)
		goto badfd;
	num = lua_tonumber(L, 1);
	if (num < INT_MIN || num > INT_MAX || num != (lua_Number) (int) num)
		goto badfd;
	out_fd = (int) num;

	if (lua_type(L, 2) != LUA_TNUMBER)
		goto badfd;
	num = lua_tonumber(L, 2);
	if (num < INT_MIN || num > INT_MAX || num != (lua_Number) (int) num)
		goto badfd;
	in_fd = (int) num;

	/*
	 * offset: optional.  Omitted or nil means NULL, i.e. the in_fd file
	 * position is used and advanced.  A number means the explicit starting
	 * offset; the updated offset is then returned as a second value.
	 */
	if (!lua_isnoneornil(L, 3)) {
		if (lua_type(L, 3) != LUA_TNUMBER)
			goto badval;
		num = lua_tonumber(L, 3);
		if (num < 0 || num > SSIZE_MAX || num != (lua_Number) (off_t) num)
			goto badval;
		offset = (off_t) num;
		offp = &offset;
	}

	/* count: mandatory */
	if (lua_type(L, 4) != LUA_TNUMBER)
		goto badval;
	num = lua_tonumber(L, 4);
	if (num < 0 || num > SSIZE_MAX || num != (lua_Number) (size_t) num)
		goto badval;
	count = (size_t) num;

	ret = sendfile(out_fd, in_fd, offp, count);
	if (ret < 0) {
		lua_pushnil(L);
		lua_pushinteger(L, errno);
		return 2;
	}

	lua_pushinteger(L, (lua_Integer) ret);
	if (offp != NULL) {
		lua_pushnumber(L, (lua_Number) offset);
		return 2;
	}
	return 1;

badfd:
	lua_pushnil(L);
	lua_pushinteger(L, EBADF);
	return 2;

badval:
	lua_pushnil(L);
	lua_pushinteger(L, EINVAL);
	return 2;
}

static const struct luaL_Reg syscall_regs[] = {
	{ "open",                syscall_open },
	{ "read",                syscall_read },
	{ "write",               syscall_write },
	{ "close",               syscall_close },
	{ "sendfile",            syscall_sendfile },
	{ NULL, NULL }
};

#define SYSCALL_EXPORT_INTEGER(L, v) \
	do { \
		lua_pushinteger((L), (v)); \
		lua_setfield((L), -2, #v); \
	} while (0)

int luaopen_syscall(lua_State * L)
{
	luaL_register(L, "syscall", syscall_regs);

	SYSCALL_EXPORT_INTEGER(L, O_RDONLY);
	SYSCALL_EXPORT_INTEGER(L, O_WRONLY);
	SYSCALL_EXPORT_INTEGER(L, O_RDWR);
	SYSCALL_EXPORT_INTEGER(L, O_CREAT);
	SYSCALL_EXPORT_INTEGER(L, O_EXCL);
	SYSCALL_EXPORT_INTEGER(L, O_TRUNC);
	SYSCALL_EXPORT_INTEGER(L, O_APPEND);
	SYSCALL_EXPORT_INTEGER(L, O_NONBLOCK);
	SYSCALL_EXPORT_INTEGER(L, O_CLOEXEC);
	SYSCALL_EXPORT_INTEGER(L, O_DIRECTORY);
	SYSCALL_EXPORT_INTEGER(L, O_NOFOLLOW);
	SYSCALL_EXPORT_INTEGER(L, O_SYNC);
#ifdef O_TMPFILE
	SYSCALL_EXPORT_INTEGER(L, O_TMPFILE);
#endif

	return 1;
}
