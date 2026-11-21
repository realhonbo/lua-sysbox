--
-- Test runner for lua-sysbox.
--
-- Deliberately dependency free: the suite has to run on a bare interpreter
-- (Lua 5.1 plus the build toolchain), with no LuaRocks and no test framework.
--
--   make test
--   lua tests/run.lua
--
-- Every test file returns a function that takes the runner table and registers
-- cases with t.test(name, function () ... end).  Assertions raise on failure.
--

local script = (arg and arg[0]) or "tests/run.lua"
local root = script:match("^(.*)[/\\][^/\\]*$") or "."
root = root:gsub("[/\\]?tests$", "")
if root == "" then root = "." end

-- Pick up the modules built in the source tree, whatever the cwd is.
package.cpath = root .. "/?.so;" .. package.cpath

-- Linux errno values (sendfile(2) is Linux only, so the suite targets Linux).
local E = {
	EPERM = 1,
	ENOENT = 2,
	EBADF = 9,
	ENOMEM = 12,
	EEXIST = 17,
	ENOTDIR = 20,
	EISDIR = 21,
	EINVAL = 22,
}

local function show(v)
	local s = tostring(v):gsub("\n", "\\n")
	if #s > 72 then
		s = s:sub(1, 69) .. "..."
	end
	return s
end

local A = { E = E }

function A.eq(got, want, what)
	if got ~= want then
		error(("%s: want %s, got %s"):format(what, show(want), show(got)), 2)
	end
end

function A.ok(cond, what)
	if not cond then
		error(what .. ": condition is false", 2)
	end
end

-- Assert that fn() failed with the given errno, i.e. returned (nil, errno).
function A.fails(errno, what, fn)
	local val, err = fn()
	if val ~= nil or err ~= errno then
		error(("%s: want (nil, %d), got (%s, %s)"):format(
			what, errno, show(val), show(err)), 2)
	end
end

local files = { "test_libutil.lua", "test_syscall.lua" }
local total, failed = 0, 0

for _, file in ipairs(files) do
	local cases = {}
	local t = setmetatable({}, { __index = A })

	function t.test(name, fn)
		cases[#cases + 1] = { name = name, fn = fn }
	end

	io.write(("# %s\n"):format(file))

	-- The suites require() at file scope, so a broken module shows up as a
	-- load error instead of taking the whole run down with a traceback.
	-- A suite file returns function (t) ... end, which is then called with the
	-- runner so that it can register its cases.
	local chunk, err = loadfile(root .. "/tests/" .. file)
	local ok = false
	if chunk then
		local register
		ok, register = pcall(chunk)
		if ok then
			ok, err = pcall(register, t)
		end
	end

	if not ok then
		total = total + 1
		failed = failed + 1
		io.write(("  FAIL suite failed to load\n       %s\n\n"):format(
			(tostring(err):gsub("\n", "\n       "))))
	else
		for _, case in ipairs(cases) do
			total = total + 1
			local passed, cerr = pcall(case.fn)
			if passed then
				io.write(("  ok   %s\n"):format(case.name))
			else
				failed = failed + 1
				io.write(("  FAIL %s\n       %s\n"):format(
					case.name, (tostring(cerr):gsub("\n", "\n       "))))
			end
		end
		io.write("\n")
	end
end

io.write(("%d test(s), %d failed\n"):format(total, failed))

-- A runner that silently collects nothing is worse than a red build.
if total == 0 then
	io.write("FAIL: no test cases were collected\n")
	os.exit(1)
end

if failed > 0 then
	os.exit(1)
end
