require("luacov")

-- Mock luarocks.persist (used by pkginfo.save fallback).
local mock_persist = {
    save_calls = {},
}
mock_persist.reset = function()
    mock_persist.save_calls = {}
end
package.loaded["luarocks.persist"] = {
    save_from_table = function(filepath, tbl)
        mock_persist.save_calls[filepath] = tbl
        return true
    end,
    load_into_table = function()
        return nil
    end,
}

-- Mock pkginfo dependency. The mock exposes `get` and `save`. `get` returns
-- three values matching the new contract: (info, err, ispcfile).
local mock_pkginfo = {
    pkgs = {}, -- pkgname -> { info, err, ispcfile }
    calls = {},
}
mock_pkginfo.reset = function()
    mock_pkginfo.pkgs = {}
    mock_pkginfo.calls = {}
end
package.loaded["luarocks.build.hooks.lib.pkginfo"] = {
    get = function(pkgname, constraints)
        mock_pkginfo.calls[#mock_pkginfo.calls + 1] = {
            pkgname = pkgname,
            constraints = constraints,
        }
        local entry = mock_pkginfo.pkgs[pkgname]
        if not entry then
            return nil
        end
        return entry.info, entry.err, entry.ispcfile
    end,
    save = function(info)
        local pcpath = info.file and info.file.incdirs_metadata
        if pcpath then
            mock_persist.save_calls[pcpath] = info
        end
        return true
    end,
}

-- Mock luarocks.queries.from_dep_string
package.loaded["luarocks.queries"] = {
    from_dep_string = function(depstr)
        -- Simple parser: take the first whitespace-delimited token as the
        -- package name. Constraints are ignored in tests.
        local name = depstr:match("^%s*([%w%._%-]+)")
        if not name then
            return nil, "invalid dep: " .. depstr
        end
        return {
            name = name,
            constraints = {},
        }
    end,
}

-- Load module under test (clear cache so mocks take effect)
package.loaded["luarocks.build.hooks.lib.incdirs"] = nil
local incdirs = require("luarocks.build.hooks.lib.incdirs")

-- Test helpers
local function run_test(name, func)
    io.write("Running " .. name .. "... ")
    mock_pkginfo.reset()
    mock_persist.reset()
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

local function assert_nil(val, msg)
    if val ~= nil then
        error((msg or "") .. " Expected nil, got " .. tostring(val), 2)
    end
end

local function assert_not_nil(val, msg)
    if val == nil then
        error((msg or "") .. " Expected non-nil value", 2)
    end
end

-- Convenience: register a package fixture for the mock pkginfo.
local function register_pkg(name, opts)
    opts = opts or {}
    local incdirs_list = opts.incdirs or {}
    local headers = opts.headers or {}
    local deps = opts.dependencies or {}
    mock_pkginfo.pkgs[name] = {
        ispcfile = opts.ispcfile or false,
        info = {
            name = name,
            version = opts.version or "1.0",
            file = {
                incdirs_metadata = "/conf/" .. name .. "/" .. name .. ".pc.lua",
            },
            dependencies = deps,
            metadata = {
                format = 1,
                package = name,
                version = opts.version or "1.0",
                headers = headers,
                incdirs = incdirs_list,
                dependencies = deps,
            },
        },
    }
end

-- ── pkgstats arg must be a table ────────────────────────────────────────────

run_test("Errors when pkgstats is not a table", function()
    local ok, err = pcall(incdirs, "not-a-table", "mylib")
    assert_equal(false, ok)
    if not tostring(err):match("pkgstats must be a table") then
        error("Unexpected error: " .. tostring(err))
    end
end)

-- ── pkginfo returns nil ─────────────────────────────────────────────────────

run_test("Returns nil when package not found", function()
    local result, err = incdirs({}, "nonexistent")
    assert_nil(result)
    assert_nil(err)
end)

-- ── package with no incdirs ─────────────────────────────────────────────────

run_test("Returns nil when root package has no incdirs", function()
    register_pkg("mylib")
    local result = incdirs({}, "mylib")
    assert_nil(result)
end)

-- ── direct headers from root package ────────────────────────────────────────

run_test("Returns root package metadata for direct headers", function()
    register_pkg("mylib", {
        headers = {
            "mylib.h",
        },
        incdirs = {
            "/conf/mylib",
        },
    })
    local result = incdirs({}, "mylib")
    assert_not_nil(result)
    assert_equal(1, #result.incdirs)
    assert_equal("/conf/mylib", result.incdirs[1])
    assert_equal(1, #result.headers)
    assert_equal("mylib.h", result.headers[1])
end)

-- ── transitive: foo depends on bar ──────────────────────────────────────────

run_test("Merges transitive dependency incdirs (foo -> bar)", function()
    register_pkg("foo", {
        headers = {
            "foo.h",
        },
        incdirs = {
            "/conf/foo",
        },
        dependencies = {
            "bar >= 1.0",
        },
    })
    register_pkg("bar", {
        headers = {
            "bar.h",
        },
        incdirs = {
            "/conf/bar",
        },
    })
    local result = incdirs({}, "foo")
    assert_not_nil(result)
    assert_equal(2, #result.incdirs)
    assert_equal("/conf/foo", result.incdirs[1])
    assert_equal("/conf/bar", result.incdirs[2])
    assert_equal(2, #result.headers)
end)

-- ── transitive: 3-level chain foo -> bar -> baz ─────────────────────────────

run_test("Merges 3-level transitive incdirs (foo -> bar -> baz)", function()
    register_pkg("foo", {
        headers = {
            "foo.h",
        },
        incdirs = {
            "/conf/foo",
        },
        dependencies = {
            "bar",
        },
    })
    register_pkg("bar", {
        headers = {
            "bar.h",
        },
        incdirs = {
            "/conf/bar",
        },
        dependencies = {
            "baz",
        },
    })
    register_pkg("baz", {
        headers = {
            "baz.h",
        },
        incdirs = {
            "/conf/baz",
        },
    })
    local result = incdirs({}, "foo")
    assert_not_nil(result)
    assert_equal(3, #result.incdirs)
    assert_equal("/conf/foo", result.incdirs[1])
end)

-- ── duplicate incdirs across deps are deduplicated ──────────────────────────

run_test("Deduplicates incdirs across dependencies", function()
    register_pkg("foo", {
        headers = {
            "foo.h",
        },
        incdirs = {
            "/conf/shared",
        },
        dependencies = {
            "bar",
        },
    })
    register_pkg("bar", {
        headers = {
            "bar.h",
        },
        incdirs = {
            "/conf/shared",
            "/conf/bar",
        },
    })
    local result = incdirs({}, "foo")
    assert_not_nil(result)
    assert_equal(2, #result.incdirs)
end)

-- ── cycle: A -> B -> A is resolved without infinite loop ────────────────────

run_test("Resolves dependency cycles via fixed-point iteration", function()
    register_pkg("a", {
        headers = {
            "a.h",
        },
        incdirs = {
            "/conf/a",
        },
        dependencies = {
            "b",
        },
    })
    register_pkg("b", {
        headers = {
            "b.h",
        },
        incdirs = {
            "/conf/b",
        },
        dependencies = {
            "a",
        },
    })
    local result = incdirs({}, "a")
    assert_not_nil(result)
    assert_equal(2, #result.incdirs)
end)

-- ── self-dependency is an explicit error ────────────────────────────────────

run_test("Errors on explicit self-dependency", function()
    register_pkg("loop", {
        headers = {
            "loop.h",
        },
        incdirs = {
            "/conf/loop",
        },
        dependencies = {
            "loop",
        },
    })
    local result, err = incdirs({}, "loop")
    assert_nil(result)
    if not tostring(err):match("self dependency") then
        error("Unexpected error: " .. tostring(err))
    end
end)

-- ── .pc.lua nodes (ispcfile=true) are not re-saved ──────────────────────────

run_test("Does not re-save .pc.lua nodes (seed metadata)", function()
    register_pkg("foo", {
        ispcfile = true,
        headers = {
            "foo.h",
        },
        incdirs = {
            "/conf/foo",
        },
    })
    incdirs({}, "foo")
    assert_nil(mock_persist.save_calls["/conf/foo/foo.pc.lua"])
end)

-- ── non-.pc.lua nodes are persisted after resolution ────────────────────────

run_test("Persists resolved metadata for non-.pc.lua nodes", function()
    register_pkg("foo", {
        headers = {
            "foo.h",
        },
        incdirs = {
            "/conf/foo",
        },
        dependencies = {
            "bar",
        },
    })
    register_pkg("bar", {
        headers = {
            "bar.h",
        },
        incdirs = {
            "/conf/bar",
        },
    })
    incdirs({}, "foo")
    local saved = mock_persist.save_calls["/conf/foo/foo.pc.lua"]
    assert_not_nil(saved)
    assert_equal(2, #saved.metadata.incdirs)
end)

-- ── pkgstats cache: pkginfo is called once per package across calls ─────────

run_test("Shares pkgstats cache across multiple incdirs() calls", function()
    register_pkg("foo", {
        headers = {
            "foo.h",
        },
        incdirs = {
            "/conf/foo",
        },
    })
    local pkgstats = {}
    incdirs(pkgstats, "foo")
    incdirs(pkgstats, "foo")
    local foo_calls = 0
    for _, c in ipairs(mock_pkginfo.calls) do
        if c.pkgname == "foo" then
            foo_calls = foo_calls + 1
        end
    end
    assert_equal(1, foo_calls)
end)

-- ── passes pkgname and constraints to pkginfo ───────────────────────────────

run_test("Passes pkgname and constraints to pkginfo", function()
    local constraints = {
        {
            op = "==",
            version = {
                1,
                0,
            },
        },
    }
    incdirs({}, "missing", constraints)
    assert_equal("missing", mock_pkginfo.calls[1].pkgname)
    assert_equal(constraints, mock_pkginfo.calls[1].constraints)
end)
