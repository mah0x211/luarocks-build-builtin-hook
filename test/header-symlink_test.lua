require("luacov")

-- Mock luarocks.util
local printout_log = {}
local mock_util = {
    printout = function(msg)
        printout_log[#printout_log + 1] = msg
    end,
}
package.loaded["luarocks.util"] = mock_util

-- Mock luarocks.fs
local mock_fs = {}
mock_fs._is_dir = {}

mock_fs.is_dir = function(path)
    return mock_fs._is_dir[path] or false
end

mock_fs.reset = function()
    mock_fs._is_dir = {}
end

package.loaded["luarocks.fs"] = mock_fs

-- Mock os.execute and os.remove
local original_execute = os.execute
local original_remove = os.remove
local exec_log = {}
local exec_results = {}
local remove_log = {}

_G.os.execute = function(cmd)
    exec_log[#exec_log + 1] = cmd
    if exec_results[cmd] ~= nil then
        return exec_results[cmd]
    end
    return true
end

_G.os.remove = function(path)
    remove_log[#remove_log + 1] = path
    return true
end

-- Load module under test
package.loaded["luarocks.build.hooks.header-symlink"] = nil
local symlink_headers = require("luarocks.build.hooks.header-symlink")

-- Test helpers

local function reset()
    printout_log = {}
    exec_log = {}
    exec_results = {}
    remove_log = {}
    mock_fs.reset()
end

local function run_test(name, func)
    io.write("Running " .. name .. "... ")
    reset()
    local status, err = xpcall(func, debug.traceback)
    if status then
        print("OK")
    else
        print("FAIL")
        print(err)
        os.exit(1)
    end
end

local function assert_equal(expected, actual, msg)
    if expected ~= actual then
        error((msg or "") .. " Expected " .. tostring(expected) .. ", got " ..
                  tostring(actual), 2)
    end
end

local function assert_true(val, msg)
    if val ~= true then
        error((msg or "") .. " Expected true, got " .. tostring(val), 2)
    end
end

local function assert_contains_log(substring, msg)
    for _, entry in ipairs(exec_log) do
        if entry:find(substring, 1, true) then
            return
        end
    end
    error((msg or "") .. " No exec log entry containing " .. substring, 2)
end

local function assert_not_contains_log(substring, msg)
    for _, entry in ipairs(exec_log) do
        if entry:find(substring, 1, true) then
            error(
                (msg or "") .. " Found unexpected exec log entry containing " ..
                    substring, 2)
        end
    end
end

local function assert_printout_contains(substring, msg)
    for _, entry in ipairs(printout_log) do
        if entry:find(substring, 1, true) then
            return
        end
    end
    error((msg or "") .. " No printout containing " .. substring, 2)
end

-- Helper: create a rockspec with given variables and optional install.conf
local function make_rockspec(vars, conf)
    return {
        variables = vars or {},
        build = {
            install = {
                conf = conf,
            },
        },
    }
end

-- ── symlink_headers: LUA_INCDIR not defined ──────────────────────────────────

run_test("Returns true when LUA_INCDIR is nil", function()
    local rockspec = make_rockspec({
        CONFDIR = "/mock/conf",
    }, {
        ["test.h"] = "src/test.h",
    })
    local result = symlink_headers(rockspec)
    assert_true(result)
    assert_printout_contains("LUA_INCDIR variable is not defined")
end)

-- ── symlink_headers: LUA_INCDIR not a directory ──────────────────────────────

run_test("Returns true when LUA_INCDIR is not a directory", function()
    mock_fs._is_dir["/mock/inc"] = false
    local rockspec = make_rockspec({
        LUA_INCDIR = "/mock/inc",
        CONFDIR = "/mock/conf",
    }, {
        ["test.h"] = "src/test.h",
    })
    local result = symlink_headers(rockspec)
    assert_true(result)
    assert_printout_contains("LUA_INCDIR is not a directory")
end)

-- ── symlink_headers: CONFDIR not defined ─────────────────────────────────────

run_test("Returns true when CONFDIR is nil", function()
    mock_fs._is_dir["/mock/inc"] = true
    local rockspec = make_rockspec({
        LUA_INCDIR = "/mock/inc",
    }, {
        ["test.h"] = "src/test.h",
    })
    local result = symlink_headers(rockspec)
    assert_true(result)
    assert_printout_contains("CONFDIR variable is not defined")
end)

-- ── symlink_headers: no install.conf ─────────────────────────────────────────

run_test("Returns true when install.conf is nil", function()
    mock_fs._is_dir["/mock/inc"] = true
    local rockspec = {
        variables = {
            LUA_INCDIR = "/mock/inc",
            CONFDIR = "/mock/conf",
        },
        build = {
            install = {},
        },
    }
    local result = symlink_headers(rockspec)
    assert_true(result)
    assert_not_contains_log("ln -s")
end)

-- ── symlink_headers: no build.install ────────────────────────────────────────

run_test("Returns true when build.install is nil", function()
    mock_fs._is_dir["/mock/inc"] = true
    local rockspec = {
        variables = {
            LUA_INCDIR = "/mock/inc",
            CONFDIR = "/mock/conf",
        },
        build = {},
    }
    local result = symlink_headers(rockspec)
    assert_true(result)
    assert_not_contains_log("ln -s")
end)

-- ── symlink_headers: no build table ──────────────────────────────────────────

run_test("Returns true when build is nil", function()
    mock_fs._is_dir["/mock/inc"] = true
    local rockspec = {
        variables = {
            LUA_INCDIR = "/mock/inc",
            CONFDIR = "/mock/conf",
        },
    }
    local result = symlink_headers(rockspec)
    assert_true(result)
    assert_not_contains_log("ln -s")
end)

-- ── symlink_headers: empty install.conf ──────────────────────────────────────

run_test("Returns true when install.conf is empty", function()
    mock_fs._is_dir["/mock/inc"] = true
    local rockspec = make_rockspec({
        LUA_INCDIR = "/mock/inc",
        CONFDIR = "/mock/conf",
    }, {})
    local result = symlink_headers(rockspec)
    assert_true(result)
    assert_printout_contains("Starting header symlink process")
end)

-- ── symlink_headers: root-level .h file ──────────────────────────────────────

run_test("Creates symlink for root-level .h file", function()
    mock_fs._is_dir["/mock/inc"] = true
    local rockspec = make_rockspec({
        LUA_INCDIR = "/mock/inc",
        CONFDIR = "/mock/conf",
    }, {
        ["mylib.h"] = "src/mylib.h",
    })
    local result = symlink_headers(rockspec)
    assert_true(result)
    assert_contains_log('ln -s "/mock/conf/mylib.h" "/mock/inc/mylib.h"')
end)

-- ── symlink_headers: non-.h file in install.conf is skipped ──────────────────

run_test("Skips non-.h files in install.conf", function()
    mock_fs._is_dir["/mock/inc"] = true
    local rockspec = make_rockspec({
        LUA_INCDIR = "/mock/inc",
        CONFDIR = "/mock/conf",
    }, {
        ["readme.txt"] = "docs/readme.txt",
    })
    local result = symlink_headers(rockspec)
    assert_true(result)
    assert_not_contains_log("ln -s")
end)

-- ── symlink_headers: subdir .h file creates directory symlink ────────────────

run_test("Creates directory symlink for subdir .h file", function()
    mock_fs._is_dir["/mock/inc"] = true
    local rockspec = make_rockspec({
        LUA_INCDIR = "/mock/inc",
        CONFDIR = "/mock/conf",
    }, {
        ["mypkg/core.h"] = "src/core.h",
    })
    local result = symlink_headers(rockspec)
    assert_true(result)
    assert_contains_log('ln -s "/mock/conf/mypkg" "/mock/inc/mypkg"')
end)

-- ── symlink_headers: multiple .h files in same subdir are deduped ────────────

run_test("Deduplicates directory symlinks for same subdir", function()
    mock_fs._is_dir["/mock/inc"] = true
    local rockspec = make_rockspec({
        LUA_INCDIR = "/mock/inc",
        CONFDIR = "/mock/conf",
    }, {
        ["mypkg/core.h"] = "src/core.h",
        ["mypkg/util.h"] = "src/util.h",
    })
    local result = symlink_headers(rockspec)
    assert_true(result)
    -- Only one ln -s for the directory
    local ln_count = 0
    for _, cmd in ipairs(exec_log) do
        if cmd:find("ln -s", 1, true) then
            ln_count = ln_count + 1
        end
    end
    assert_equal(1, ln_count, "Should create exactly 1 symlink for deduped dir")
end)

-- ── symlink_headers: mixed entries ───────────────────────────────────────────

run_test("Handles mixed entries correctly", function()
    mock_fs._is_dir["/mock/inc"] = true
    local rockspec = make_rockspec({
        LUA_INCDIR = "/mock/inc",
        CONFDIR = "/mock/conf",
    }, {
        ["mylib.h"] = "src/mylib.h",
        ["mypkg/core.h"] = "src/core.h",
        ["readme.txt"] = "docs/readme.txt",
    })
    local result = symlink_headers(rockspec)
    assert_true(result)
    assert_contains_log('ln -s "/mock/conf/mylib.h" "/mock/inc/mylib.h"')
    assert_contains_log('ln -s "/mock/conf/mypkg" "/mock/inc/mypkg"')
    local ln_count = 0
    for _, cmd in ipairs(exec_log) do
        if cmd:find("ln -s", 1, true) then
            ln_count = ln_count + 1
        end
    end
    assert_equal(2, ln_count, "Should create exactly 2 symlinks")
end)

-- ── symlink_headers: multiple subdirs ────────────────────────────────────────

run_test("Creates symlinks for multiple subdirs", function()
    mock_fs._is_dir["/mock/inc"] = true
    local rockspec = make_rockspec({
        LUA_INCDIR = "/mock/inc",
        CONFDIR = "/mock/conf",
    }, {
        ["pkgA/a.h"] = "src/a.h",
        ["pkgB/b.h"] = "src/b.h",
    })
    local result = symlink_headers(rockspec)
    assert_true(result)
    assert_contains_log('ln -s "/mock/conf/pkgA" "/mock/inc/pkgA"')
    assert_contains_log('ln -s "/mock/conf/pkgB" "/mock/inc/pkgB"')
    local ln_count = 0
    for _, cmd in ipairs(exec_log) do
        if cmd:find("ln -s", 1, true) then
            ln_count = ln_count + 1
        end
    end
    assert_equal(2, ln_count, "Should create exactly 2 symlinks")
end)

-- ── symlink_headers: nested subdir .h file ───────────────────────────────────

run_test("Creates symlink for nested subdir .h file", function()
    mock_fs._is_dir["/mock/inc"] = true
    local rockspec = make_rockspec({
        LUA_INCDIR = "/mock/inc",
        CONFDIR = "/mock/conf",
    }, {
        ["a/b/core.h"] = "src/core.h",
    })
    local result = symlink_headers(rockspec)
    assert_true(result)
    assert_contains_log('ln -s "/mock/conf/a/b" "/mock/inc/a/b"')
end)

-- ── create_symlink: existing symlink is replaced ─────────────────────────────

run_test("Replaces existing symlink", function()
    mock_fs._is_dir["/mock/inc"] = true
    exec_results[('test -L "/mock/inc/mylib.h"')] = true
    exec_results[('ln -s "/mock/conf/mylib.h" "/mock/inc/mylib.h"')] = true
    local rockspec = make_rockspec({
        LUA_INCDIR = "/mock/inc",
        CONFDIR = "/mock/conf",
    }, {
        ["mylib.h"] = "src/mylib.h",
    })
    local result = symlink_headers(rockspec)
    assert_true(result)
    local found = false
    for _, p in ipairs(remove_log) do
        if p == "/mock/inc/mylib.h" then
            found = true
        end
    end
    assert_true(found, "os.remove should have been called for existing symlink")
    assert_contains_log('ln -s "/mock/conf/mylib.h" "/mock/inc/mylib.h"')
end)

-- ── create_symlink: existing non-symlink file is skipped ─────────────────────

run_test("Skips existing non-symlink file", function()
    mock_fs._is_dir["/mock/inc"] = true
    exec_results[('test -L "/mock/inc/mylib.h"')] = false
    exec_results[('test -e "/mock/inc/mylib.h"')] = true
    local rockspec = make_rockspec({
        LUA_INCDIR = "/mock/inc",
        CONFDIR = "/mock/conf",
    }, {
        ["mylib.h"] = "src/mylib.h",
    })
    local result = symlink_headers(rockspec)
    assert_true(result)
    assert_printout_contains("already exists and is not a symlink")
end)

-- ── create_symlink: ln -s fails ──────────────────────────────────────────────

run_test("Warns when ln -s fails for root-level .h", function()
    mock_fs._is_dir["/mock/inc"] = true
    exec_results[('test -L "/mock/inc/mylib.h"')] = false
    exec_results[('test -e "/mock/inc/mylib.h"')] = false
    exec_results[('ln -s "/mock/conf/mylib.h" "/mock/inc/mylib.h"')] = false
    local rockspec = make_rockspec({
        LUA_INCDIR = "/mock/inc",
        CONFDIR = "/mock/conf",
    }, {
        ["mylib.h"] = "src/mylib.h",
    })
    local result = symlink_headers(rockspec)
    assert_true(result)
    assert_printout_contains("failed to create symlink")
end)

-- ── exec_ok: Lua 5.1 style return (0) ───────────────────────────────────────

run_test("exec_ok handles Lua 5.1 return value (0)", function()
    mock_fs._is_dir["/mock/inc"] = true
    exec_results[('test -L "/mock/inc/test.h"')] = false
    exec_results[('test -e "/mock/inc/test.h"')] = false
    exec_results[('ln -s "/mock/conf/test.h" "/mock/inc/test.h"')] = 0
    local rockspec = make_rockspec({
        LUA_INCDIR = "/mock/inc",
        CONFDIR = "/mock/conf",
    }, {
        ["test.h"] = "src/test.h",
    })
    local result = symlink_headers(rockspec)
    assert_true(result)
    assert_printout_contains("  symlink: /mock/inc/test.h -> /mock/conf/test.h")
end)

-- ── exec_ok: Lua 5.1 nonzero return ─────────────────────────────────────────

run_test("exec_ok handles Lua 5.1 nonzero return", function()
    mock_fs._is_dir["/mock/inc"] = true
    exec_results[('test -L "/mock/inc/test.h"')] = false
    exec_results[('test -e "/mock/inc/test.h"')] = false
    exec_results[('ln -s "/mock/conf/test.h" "/mock/inc/test.h"')] = 1
    local rockspec = make_rockspec({
        LUA_INCDIR = "/mock/inc",
        CONFDIR = "/mock/conf",
    }, {
        ["test.h"] = "src/test.h",
    })
    local result = symlink_headers(rockspec)
    assert_true(result)
    assert_printout_contains("failed to create symlink")
end)

-- ── create_symlink: subdir symlink failure ───────────────────────────────────

run_test("Warns when subdir symlink creation fails", function()
    mock_fs._is_dir["/mock/inc"] = true
    exec_results[('test -L "/mock/inc/mypkg"')] = false
    exec_results[('test -e "/mock/inc/mypkg"')] = false
    exec_results[('ln -s "/mock/conf/mypkg" "/mock/inc/mypkg"')] = false
    local rockspec = make_rockspec({
        LUA_INCDIR = "/mock/inc",
        CONFDIR = "/mock/conf",
    }, {
        ["mypkg/core.h"] = "src/core.h",
    })
    local result = symlink_headers(rockspec)
    assert_true(result)
    assert_printout_contains("failed to create symlink /mock/inc/mypkg")
end)

-- ── create_symlink: subdir existing non-symlink ──────────────────────────────

run_test("Warns when subdir target exists as non-symlink", function()
    mock_fs._is_dir["/mock/inc"] = true
    exec_results[('test -L "/mock/inc/mypkg"')] = false
    exec_results[('test -e "/mock/inc/mypkg"')] = true
    local rockspec = make_rockspec({
        LUA_INCDIR = "/mock/inc",
        CONFDIR = "/mock/conf",
    }, {
        ["mypkg/core.h"] = "src/core.h",
    })
    local result = symlink_headers(rockspec)
    assert_true(result)
    assert_printout_contains(
        "/mock/inc/mypkg already exists and is not a symlink")
end)

-- ── create_symlink: subdir existing symlink is replaced ──────────────────────

run_test("Replaces existing subdir symlink", function()
    mock_fs._is_dir["/mock/inc"] = true
    exec_results[('test -L "/mock/inc/mypkg"')] = true
    exec_results[('ln -s "/mock/conf/mypkg" "/mock/inc/mypkg"')] = true
    local rockspec = make_rockspec({
        LUA_INCDIR = "/mock/inc",
        CONFDIR = "/mock/conf",
    }, {
        ["mypkg/core.h"] = "src/core.h",
    })
    local result = symlink_headers(rockspec)
    assert_true(result)
    local found = false
    for _, p in ipairs(remove_log) do
        if p == "/mock/inc/mypkg" then
            found = true
        end
    end
    assert_true(found, "os.remove should have been called for existing symlink")
    assert_contains_log('ln -s "/mock/conf/mypkg" "/mock/inc/mypkg"')
end)

-- Restore originals
_G.os.execute = original_execute
_G.os.remove = original_remove

print("\nAll tests passed!")
