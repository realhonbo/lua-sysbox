--
-- syscall: thin wrappers around open(2), read(2), write(2), close(2) and
-- sendfile(2).  Everything here is Linux specific.
--
local syscall = require("syscall")

local tmpdir = os.getenv("TMPDIR") or "/tmp"
local seq = 0

-- Unique, not-yet-existing path.  os.tmpname() is avoided on purpose: on some
-- Lua versions it creates the file, which would defeat the ENOENT tests.
local function tmp()
	seq = seq + 1
	return ("%s/lua-sysbox-%d-%d.tmp"):format(tmpdir, os.time(), seq)
end

-- Bit flags are disjoint, so plain addition is safe on every Lua version
-- (there are no bitwise operators before 5.3).
local function O(...)
	local flags = 0
	for _, f in ipairs({ ... }) do
		flags = flags + f
	end
	return flags
end

return function(t)
	local E = t.E

	t.test("exports the open(2) flags", function()
		local names = {
			"O_RDONLY", "O_WRONLY", "O_RDWR", "O_CREAT", "O_EXCL",
			"O_TRUNC", "O_APPEND", "O_NONBLOCK", "O_CLOEXEC",
			"O_DIRECTORY", "O_NOFOLLOW", "O_SYNC",
		}
		for _, name in ipairs(names) do
			t.eq(type(syscall[name]), "number", name .. " is a number")
		end
		t.eq(syscall.O_RDONLY, 0, "O_RDONLY is 0")
		t.eq(syscall.O_RDWR, 2, "O_RDWR is 2")
		t.eq(syscall.O_CREAT, 64, "O_CREAT is 64")
		t.eq(syscall.O_TRUNC, 512, "O_TRUNC is 512")
	end)

	t.test("open reports ENOENT for a missing file", function()
		t.fails(E.ENOENT, "open(missing)", function()
			return syscall.open(tmp(), syscall.O_RDONLY)
		end)
	end)

	t.test("open rejects non-string paths", function()
		for _, bad in ipairs({ 42, true, {} }) do
			t.fails(E.EINVAL, "open(" .. tostring(bad) .. ")", function()
				return syscall.open(bad, syscall.O_RDONLY)
			end)
		end
	end)

	t.test("open rejects paths with an embedded NUL", function()
		t.fails(E.EINVAL, "open(a\\0b)", function()
			return syscall.open("a\0b", syscall.O_RDONLY)
		end)
	end)

	t.test("open requires numeric flags", function()
		t.fails(E.EINVAL, "open(path, '0')", function()
			return syscall.open(tmp(), "0")
		end)
		t.fails(E.EINVAL, "open(path, 1.5)", function()
			return syscall.open(tmp(), 1.5)
		end)
		t.fails(E.EINVAL, "open(path)", function()
			return syscall.open(tmp())
		end)
	end)

	t.test("open with O_CREAT requires a valid mode", function()
		local path = tmp()
		local flags = O(syscall.O_WRONLY, syscall.O_CREAT, syscall.O_EXCL)

		t.fails(E.EINVAL, "O_CREAT without a mode", function()
			return syscall.open(path, flags)
		end)
		t.fails(E.EINVAL, "O_CREAT with mode '999'", function()
			return syscall.open(path, flags, "999")
		end)
		t.fails(E.EINVAL, "O_CREAT with mode 'rwx'", function()
			return syscall.open(path, flags, "rwx")
		end)
		t.fails(E.EINVAL, "O_CREAT with a negative mode", function()
			return syscall.open(path, flags, -1)
		end)
		t.fails(E.EINVAL, "O_CREAT with a table mode", function()
			return syscall.open(path, flags, {})
		end)

		local fd = syscall.open(path, flags, "0640")
		t.eq(type(fd), "number", "valid mode creates the file")
		t.eq(syscall.close(fd), true, "close succeeds")
		os.remove(path)
	end)

	t.test("open with O_CREAT|O_EXCL fails on an existing file", function()
		local path = tmp()
		local flags = O(syscall.O_WRONLY, syscall.O_CREAT, syscall.O_EXCL)

		local fd = syscall.open(path, flags, "0600")
		t.eq(type(fd), "number", "first open succeeds")
		syscall.close(fd)

		t.fails(E.EEXIST, "second open with O_EXCL", function()
			return syscall.open(path, flags, "0600")
		end)
		os.remove(path)
	end)

	t.test("open with O_DIRECTORY on a regular file fails", function()
		local path = tmp()
		local flags = O(syscall.O_WRONLY, syscall.O_CREAT, syscall.O_EXCL)
		local fd = syscall.open(path, flags, "0600")
		syscall.close(fd)

		t.fails(E.ENOTDIR, "open(file, O_DIRECTORY)", function()
			return syscall.open(path, O(syscall.O_RDONLY, syscall.O_DIRECTORY))
		end)
		os.remove(path)
	end)

	t.test("write/read round trip including binary data", function()
		local path = tmp()
		local payload = "hello\0world"
		local flags = O(syscall.O_RDWR, syscall.O_CREAT, syscall.O_TRUNC)

		local fd = syscall.open(path, flags, "0600")
		t.eq(type(fd), "number", "open returns an fd")
		t.eq(syscall.write(fd, payload), #payload, "write returns the byte count")
		t.eq(syscall.close(fd), true, "close succeeds")

		local rfd = syscall.open(path, syscall.O_RDONLY)
		t.eq(syscall.read(rfd, 64), payload, "read returns the whole payload")
		t.eq(syscall.read(rfd, 64), "", "read at EOF returns an empty string")
		t.eq(syscall.read(rfd, 0), "", "read of 0 bytes returns an empty string")
		t.eq(syscall.close(rfd), true, "close of the read fd succeeds")
		os.remove(path)
	end)

	t.test("read validates its arguments", function()
		local path = tmp()
		local flags = O(syscall.O_WRONLY, syscall.O_CREAT, syscall.O_TRUNC)
		local fd = syscall.open(path, flags, "0600")

		t.fails(E.EINVAL, "read(fd, -1)", function()
			return syscall.read(fd, -1)
		end)
		t.fails(E.EINVAL, "read(fd, 1.5)", function()
			return syscall.read(fd, 1.5)
		end)
		t.fails(E.EINVAL, "read(fd)", function()
			return syscall.read(fd)
		end)

		syscall.close(fd)
		os.remove(path)
	end)

	t.test("write validates its arguments", function()
		local path = tmp()
		local flags = O(syscall.O_WRONLY, syscall.O_CREAT, syscall.O_TRUNC)
		local fd = syscall.open(path, flags, "0600")

		t.fails(E.EINVAL, "write(fd, table)", function()
			return syscall.write(fd, {})
		end)
		t.fails(E.EINVAL, "write(fd)", function()
			return syscall.write(fd)
		end)

		syscall.close(fd)
		os.remove(path)
	end)

	t.test("bad file descriptors fail with EBADF", function()
		t.fails(E.EBADF, "read(9999, 1)", function()
			return syscall.read(9999, 1)
		end)
		t.fails(E.EBADF, "write(9999, 'x')", function()
			return syscall.write(9999, "x")
		end)
		t.fails(E.EBADF, "close(9999)", function()
			return syscall.close(9999)
		end)
		t.fails(E.EBADF, "read('x', 1)", function()
			return syscall.read("x", 1)
		end)
		t.fails(E.EBADF, "read(-1, 1)", function()
			return syscall.read(-1, 1)
		end)
	end)

	t.test("closing an fd twice fails with EBADF", function()
		local path = tmp()
		local flags = O(syscall.O_WRONLY, syscall.O_CREAT, syscall.O_TRUNC)
		local fd = syscall.open(path, flags, "0600")

		t.eq(syscall.close(fd), true, "first close succeeds")
		t.fails(E.EBADF, "second close", function()
			return syscall.close(fd)
		end)
		os.remove(path)
	end)

	-- Helpers for the sendfile(2) cases below.
	local function make_src(content)
		local path = tmp()
		local fd = syscall.open(path, O(syscall.O_WRONLY, syscall.O_CREAT,
			syscall.O_TRUNC), "0600")
		syscall.write(fd, content)
		syscall.close(fd)
		return path
	end

	local function slurp(path)
		local fd = syscall.open(path, syscall.O_RDONLY)
		local data = syscall.read(fd, 4096)
		syscall.close(fd)
		return data
	end

	t.test("sendfile copies a range from an explicit offset", function()
		local srcpath = make_src("0123456789")
		local dstpath = tmp()
		local src = syscall.open(srcpath, syscall.O_RDONLY)
		local dst = syscall.open(dstpath, O(syscall.O_WRONLY, syscall.O_CREAT,
			syscall.O_TRUNC), "0600")

		local n, off = syscall.sendfile(dst, src, 4, 3)
		t.eq(n, 3, "bytes sent")
		t.eq(off, 7, "the next offset is returned")
		t.eq(syscall.read(src, 2), "01",
			"an explicit offset does not move the input file position")

		syscall.close(dst)
		syscall.close(src)
		t.eq(slurp(dstpath), "456", "only the requested range was copied")

		os.remove(srcpath)
		os.remove(dstpath)
	end)

	t.test("sendfile with a nil offset uses the file position", function()
		local srcpath = make_src("abcdef")
		local dstpath = tmp()
		local src = syscall.open(srcpath, syscall.O_RDONLY)
		local dst = syscall.open(dstpath, O(syscall.O_WRONLY, syscall.O_CREAT,
			syscall.O_TRUNC), "0600")

		local n = syscall.sendfile(dst, src, nil, 4)
		t.eq(n, 4, "bytes sent")
		t.eq(syscall.read(src, 2), "ef",
			"the input file position advanced")

		syscall.close(dst)
		syscall.close(src)
		t.eq(slurp(dstpath), "abcd", "the leading bytes were copied")

		os.remove(srcpath)
		os.remove(dstpath)
	end)

	t.test("sendfile past the end of the input copies nothing", function()
		local srcpath = make_src("abc")
		local dstpath = tmp()
		local src = syscall.open(srcpath, syscall.O_RDONLY)
		local dst = syscall.open(dstpath, O(syscall.O_WRONLY, syscall.O_CREAT,
			syscall.O_TRUNC), "0600")

		local n = syscall.sendfile(dst, src, 100, 10)
		t.eq(n, 0, "no bytes sent past EOF")

		syscall.close(dst)
		syscall.close(src)
		t.eq(slurp(dstpath), "", "the output file stays empty")

		os.remove(srcpath)
		os.remove(dstpath)
	end)

	t.test("sendfile validates its arguments", function()
		t.fails(E.EBADF, "sendfile('x', 0, nil, 1)", function()
			return syscall.sendfile("x", 0, nil, 1)
		end)
		t.fails(E.EBADF, "sendfile(1, 'x', nil, 1)", function()
			return syscall.sendfile(1, "x", nil, 1)
		end)
		t.fails(E.EINVAL, "sendfile(1, 0, nil, -1)", function()
			return syscall.sendfile(1, 0, nil, -1)
		end)
		t.fails(E.EINVAL, "sendfile(1, 0, -1, 1)", function()
			return syscall.sendfile(1, 0, -1, 1)
		end)
		t.fails(E.EINVAL, "sendfile(1, 0, 'x', 1)", function()
			return syscall.sendfile(1, 0, "x", 1)
		end)
	end)
end
