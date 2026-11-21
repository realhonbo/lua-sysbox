--
-- libutil: basename(3) and dirname(3) wrappers.
--
-- Expected values follow glibc/POSIX; the modules target Linux.
--
local libutil = require("libutil")

return function(t)
	t.test("basename drops leading directories", function()
		t.eq(libutil.basename("/usr/lib/lua"), "lua", "basename(/usr/lib/lua)")
		t.eq(libutil.basename("usr/lib/lua"), "lua", "basename(usr/lib/lua)")
	end)

	t.test("basename ignores trailing slashes", function()
		t.eq(libutil.basename("/usr/lib/"), "lib", "basename(/usr/lib/)")
		t.eq(libutil.basename("/a//"), "a", "basename(/a//)")
	end)

	t.test("basename handles root and empty names", function()
		t.eq(libutil.basename("/"), "/", "basename(/)")
		t.eq(libutil.basename(""), ".", "basename()")
	end)

	t.test("dirname drops the last component", function()
		t.eq(libutil.dirname("/usr/lib/lua"), "/usr/lib", "dirname(/usr/lib/lua)")
		t.eq(libutil.dirname("usr/lib/lua"), "usr/lib", "dirname(usr/lib/lua)")
	end)

	t.test("dirname collapses to root or dot", function()
		t.eq(libutil.dirname("/usr"), "/", "dirname(/usr)")
		t.eq(libutil.dirname("/"), "/", "dirname(/)")
		t.eq(libutil.dirname("usr"), ".", "dirname(usr)")
		t.eq(libutil.dirname(""), ".", "dirname()")
	end)

	t.test("a non-string path fails with EINVAL", function()
		t.fails(t.E.EINVAL, "basename(42)",
			function() return libutil.basename(42) end)
		t.fails(t.E.EINVAL, "dirname(nil)",
			function() return libutil.dirname(nil) end)
		t.fails(t.E.EINVAL, "basename(table)",
			function() return libutil.basename({}) end)
	end)

	t.test("a path with an embedded NUL fails with EINVAL", function()
		t.fails(t.E.EINVAL, "basename(a\\0b)",
			function() return libutil.basename("a\0b") end)
		t.fails(t.E.EINVAL, "dirname(a\\0b)",
			function() return libutil.dirname("a\0b") end)
	end)

	t.test("paths at and past the stack buffer size still work", function()
		-- 511 bytes fits the 512 byte stack buffer, 513 spills to the heap.
		local edge = ("a"):rep(511) .. "/b"
		t.eq(libutil.dirname(edge), ("a"):rep(511), "dirname at the buffer edge")
		t.eq(libutil.basename(edge), "b", "basename at the buffer edge")

		local long = ("d"):rep(600)
		t.eq(libutil.dirname("/" .. long .. "/file"), "/" .. long,
			"dirname spills to the heap")
		t.eq(libutil.basename("/" .. long .. "/file"), "file",
			"basename spills to the heap")
	end)

	t.test("the Lua string is never modified in place", function()
		local path = "/a/b/"
		libutil.basename(path)
		libutil.dirname(path)
		t.eq(path, "/a/b/", "argument string is untouched")
	end)
end
