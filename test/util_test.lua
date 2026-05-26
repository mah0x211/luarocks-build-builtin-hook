require("luacov")

local util = require("luarocks.build.hooks.lib.util")

-- Test helpers

local function run_test(name, func)
    io.write("Running " .. name .. "... ")
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
    if not val then
        error((msg or "") .. " Expected truthy, got " .. tostring(val), 2)
    end
end

local function assert_false(val, msg)
    if val then
        error((msg or "") .. " Expected falsy, got " .. tostring(val), 2)
    end
end

local function assert_throws(pattern, fn, ...)
    local ok, err = pcall(fn, ...)
    if ok then
        error("Expected error matching " .. tostring(pattern) ..
                  ", but call succeeded", 2)
    end
    if pattern and not tostring(err):match(pattern) then
        error("Expected error matching " .. tostring(pattern) .. ", got: " ..
                  tostring(err), 2)
    end
end

-- ── normalize_path ────────────────────────────────────────────────────────────

run_test("normalize_path collapses consecutive slashes", function()
    assert_equal("/a/b/c", util.normalize_path("/a//b///c"))
end)

run_test("normalize_path strips a single trailing slash", function()
    assert_equal("/a/b", util.normalize_path("/a/b/"))
end)

run_test("normalize_path strips trailing slashes after collapsing", function()
    assert_equal("/a/b", util.normalize_path("/a//b//"))
end)

run_test("normalize_path leaves a clean path unchanged", function()
    assert_equal("/a/b", util.normalize_path("/a/b"))
end)

run_test("normalize_path leaves an empty string unchanged", function()
    assert_equal("", util.normalize_path(""))
end)

run_test("normalize_path leaves a relative path intact", function()
    assert_equal("a/b", util.normalize_path("a/b"))
end)

run_test("normalize_path errors when p is not a string", function()
    assert_throws("p must be a string", util.normalize_path, nil)
    assert_throws("p must be a string", util.normalize_path, 123)
    assert_throws("p must be a string", util.normalize_path, {})
end)

-- ── trim_path_prefix ──────────────────────────────────────────────────────────

run_test("trim_path_prefix strips the leading prefix", function()
    assert_equal("foo/bar", util.trim_path_prefix("/root", "/root/foo/bar"))
end)

run_test("trim_path_prefix returns empty string when p equals prefix",
         function()
    assert_equal("", util.trim_path_prefix("/root", "/root"))
end)

run_test("trim_path_prefix treats trailing slashes as equal to prefix",
         function()
    assert_equal("", util.trim_path_prefix("/root/", "/root"))
    assert_equal("", util.trim_path_prefix("/root", "/root/"))
end)

run_test("trim_path_prefix returns p unchanged when outside prefix", function()
    assert_equal("/other/path", util.trim_path_prefix("/root", "/other/path"))
end)

run_test("trim_path_prefix does not match a partial component", function()
    assert_equal("/rootless/x", util.trim_path_prefix("/root", "/rootless/x"))
end)

run_test("trim_path_prefix returns p unchanged when prefix is empty", function()
    assert_equal("/a/b", util.trim_path_prefix("", "/a/b"))
end)

run_test("trim_path_prefix normalizes the prefix before matching", function()
    assert_equal("foo", util.trim_path_prefix("/root//", "/root/foo"))
end)

run_test("trim_path_prefix errors when prefix is not a string", function()
    assert_throws("prefix must be a string", util.trim_path_prefix, nil, "/x")
    assert_throws("prefix must be a string", util.trim_path_prefix, 1, "/x")
end)

run_test("trim_path_prefix errors when p is not a string", function()
    assert_throws("p must be a string", util.trim_path_prefix, "/root", nil)
    assert_throws("p must be a string", util.trim_path_prefix, "/root", {})
end)

-- ── prepend_path_prefix ───────────────────────────────────────────────────────

run_test("prepend_path_prefix joins prefix and relative path", function()
    assert_equal("/root/foo/bar", util.prepend_path_prefix("/root", "foo/bar"))
end)

run_test("prepend_path_prefix returns p unchanged when p is absolute",
         function()
    assert_equal("/abs/path", util.prepend_path_prefix("/root", "/abs/path"))
end)

run_test("prepend_path_prefix returns prefix unchanged when p is empty",
         function()
    assert_equal("/root", util.prepend_path_prefix("/root", ""))
end)

run_test("prepend_path_prefix normalizes the prefix before joining", function()
    assert_equal("/root/foo", util.prepend_path_prefix("/root//", "foo"))
end)

run_test("prepend_path_prefix errors when prefix is not a string", function()
    assert_throws("prefix must be a string", util.prepend_path_prefix, nil,
                  "foo")
    assert_throws("prefix must be a string", util.prepend_path_prefix, 1, "foo")
end)

run_test("prepend_path_prefix errors when p is not a string", function()
    assert_throws("p must be a string", util.prepend_path_prefix, "/root", nil)
    assert_throws("p must be a string", util.prepend_path_prefix, "/root", {})
end)

-- ── deep_equal ────────────────────────────────────────────────────────────────

run_test("deep_equal treats identical primitives as equal", function()
    assert_true(util.deep_equal(1, 1))
    assert_true(util.deep_equal("a", "a"))
    assert_true(util.deep_equal(true, true))
    assert_true(util.deep_equal(nil, nil))
end)

run_test("deep_equal returns false for mismatched primitives", function()
    assert_false(util.deep_equal(1, 2))
    assert_false(util.deep_equal("a", "b"))
end)

run_test("deep_equal returns false when one side is not a table", function()
    assert_false(util.deep_equal({}, 1))
    assert_false(util.deep_equal(1, {}))
    assert_false(util.deep_equal({}, nil))
end)

run_test("deep_equal compares flat tables structurally", function()
    assert_true(util.deep_equal({
        1,
        2,
        3,
    }, {
        1,
        2,
        3,
    }))
    assert_false(util.deep_equal({
        1,
        2,
        3,
    }, {
        1,
        2,
        4,
    }))
end)

run_test("deep_equal compares nested tables recursively", function()
    assert_true(util.deep_equal({
        a = {
            b = {
                c = 1,
            },
        },
    }, {
        a = {
            b = {
                c = 1,
            },
        },
    }))
    assert_false(util.deep_equal({
        a = {
            b = {
                c = 1,
            },
        },
    }, {
        a = {
            b = {
                c = 2,
            },
        },
    }))
end)

run_test("deep_equal detects extra keys on either side", function()
    assert_false(util.deep_equal({
        a = 1,
        b = 2,
    }, {
        a = 1,
    }))
    assert_false(util.deep_equal({
        a = 1,
    }, {
        a = 1,
        b = 2,
    }))
end)

run_test("deep_equal treats two empty tables as equal", function()
    assert_true(util.deep_equal({}, {}))
end)

print("All util tests passed!")
