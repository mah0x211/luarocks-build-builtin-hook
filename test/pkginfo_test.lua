require("luacov")

-- Mock framework
local function mock(name, value)
    package.loaded[name] = value
end

-- Mock luarocks.queries
mock("luarocks.queries", {
    new = function(pkgname, a, b, c)
        return {
            name = pkgname,
            a = a,
            b = b,
            c = c,
        }
    end,
})

-- Mock luarocks.search
local mock_pick_installed = {
    result = nil, -- { name, version, tree } or nil
}
mock_pick_installed.reset = function()
    mock_pick_installed.result = nil
end
mock("luarocks.search", {
    pick_installed_rock = function(query, root)
        mock_pick_installed.query = query
        mock_pick_installed.root = root
        if mock_pick_installed.result then
            return mock_pick_installed.result[1], mock_pick_installed.result[2],
                   mock_pick_installed.result[3]
        end
        return nil
    end,
})

-- Mock luarocks.manif
local mock_load_manifest = {
    result = nil, -- { manifest } or nil
    err = nil,
}
mock_load_manifest.reset = function()
    mock_load_manifest.result = nil
    mock_load_manifest.err = nil
end
mock("luarocks.manif", {
    load_rock_manifest = function(name, version, tree)
        mock_load_manifest.args = {
            name,
            version,
            tree,
        }
        return mock_load_manifest.result, mock_load_manifest.err
    end,
})

-- Mock luarocks.path
local mock_path = {
    rocks_dir_val = "/mock/rocks",
    root_val = "/mock/root",
    bin_dir_val = "/mock/bin",
    lua_dir_val = "/mock/lua",
    lib_dir_val = "/mock/lib",
    doc_dir_val = "/mock/doc",
    conf_dir_val = "/mock/conf",
    versions_dir_val = "/mock/versions",
    install_dir_val = "/mock/install",
    rock_manifest_file_val = "/mock/rock_manifest",
    rockspec_file_val = "/mock/rockspec",
    rock_namespace_file_val = "/mock/rock_namespace",
    read_namespace_val = nil,
}
mock_path.reset = function()
    mock_path.rocks_dir_val = "/mock/rocks"
    mock_path.root_val = "/mock/root"
    mock_path.bin_dir_val = "/mock/bin"
    mock_path.lua_dir_val = "/mock/lua"
    mock_path.lib_dir_val = "/mock/lib"
    mock_path.doc_dir_val = "/mock/doc"
    mock_path.conf_dir_val = "/mock/conf"
    mock_path.versions_dir_val = "/mock/versions"
    mock_path.install_dir_val = "/mock/install"
    mock_path.rock_manifest_file_val = "/mock/rock_manifest"
    mock_path.rockspec_file_val = "/mock/rockspec"
    mock_path.rock_namespace_file_val = "/mock/rock_namespace"
    mock_path.read_namespace_val = nil
end
mock("luarocks.path", {
    rocks_dir = function()
        return mock_path.rocks_dir_val
    end,
    root_from_rocks_dir = function(rocks_dir)
        mock_path.root_from_rocks_dir_arg = rocks_dir
        return mock_path.root_val
    end,
    bin_dir = function(name, version, tree)
        return mock_path.bin_dir_val
    end,
    lua_dir = function(name, version, tree)
        return mock_path.lua_dir_val
    end,
    lib_dir = function(name, version, tree)
        return mock_path.lib_dir_val
    end,
    doc_dir = function(name, version, tree)
        return mock_path.doc_dir_val
    end,
    conf_dir = function(name, version, tree)
        return mock_path.conf_dir_val
    end,
    versions_dir = function(name, tree)
        return mock_path.versions_dir_val
    end,
    install_dir = function(name, version, tree)
        return mock_path.install_dir_val
    end,
    rock_manifest_file = function(name, version, tree)
        return mock_path.rock_manifest_file_val
    end,
    rockspec_file = function(name, version, tree)
        return mock_path.rockspec_file_val
    end,
    rock_namespace_file = function(name, version, tree)
        return mock_path.rock_namespace_file_val
    end,
    read_namespace = function(name, version, tree)
        return mock_path.read_namespace_val
    end,
})

-- Mock luarocks.persist
local mock_persist = {
    load_results = {}, -- path -> table
    save_calls = {},
}
mock_persist.reset = function()
    mock_persist.load_results = {}
    mock_persist.save_calls = {}
end
mock("luarocks.persist", {
    load_into_table = function(filepath)
        return mock_persist.load_results[filepath]
    end,
    save_from_table = function(filepath, tbl)
        mock_persist.save_calls[filepath] = tbl
        return true
    end,
})

-- Load module under test (after mocks are in place)
local pkginfo = require("luarocks.build.hooks.lib.pkginfo")

-- Test helpers

local function run_test(name, func)
    io.write("Running " .. name .. "... ")
    mock_pick_installed.reset()
    mock_load_manifest.reset()
    mock_path.reset()
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

local function assert_error(pattern, result, errmsg)
    if result ~= nil then
        error("Expected error matching " .. tostring(pattern) ..
                  ", got result: " .. tostring(result), 2)
    end
    if errmsg == nil then
        error("Expected error matching " .. tostring(pattern) ..
                  ", but errmsg is nil", 2)
    end
    if pattern and not tostring(errmsg):match(pattern) then
        error("Expected error matching " .. tostring(pattern) .. ", got: " ..
                  tostring(errmsg), 2)
    end
end

-- ── pick_installed_rock returns nil ──────────────────────────────────────────

run_test("Returns nil when rock not installed", function()
    mock_pick_installed.result = nil
    local result, err = pkginfo.get("nonexistent")
    assert_nil(result)
    assert_nil(err)
end)

-- ── passes correct args to pick_installed_rock ───────────────────────────────

run_test("Passes query and root to pick_installed_rock", function()
    mock_pick_installed.result = nil
    pkginfo.get("testpkg")
    assert_not_nil(mock_pick_installed.query)
    assert_equal("testpkg", mock_pick_installed.query.name)
    assert_equal("/mock/rocks", mock_path.root_from_rocks_dir_arg)
    assert_equal("/mock/root", mock_pick_installed.root)
end)

-- ── constraints are passed to query ──────────────────────────────────────────

run_test("Passes constraints to query when provided", function()
    mock_pick_installed.result = nil
    local constraints = {
        {
            op = "==",
            version = {
                1,
                0,
            },
        },
    }
    pkginfo.get("testpkg", constraints)
    assert_not_nil(mock_pick_installed.query)
    assert_equal(constraints, mock_pick_installed.query.constraints)
end)

-- ── constraints nil preserves default ────────────────────────────────────────

run_test("Keeps default constraints when nil is passed", function()
    mock_pick_installed.result = nil
    pkginfo.get("testpkg")
    assert_not_nil(mock_pick_installed.query)
    assert_nil(mock_pick_installed.query.constraints)
end)

-- ── load_manifest returns nil with error ─────────────────────────────────────

run_test("Returns nil and error when manifest fails to load", function()
    mock_pick_installed.result = {
        "mylib",
        "1.0",
        "/tree",
    }
    mock_load_manifest.result = nil
    mock_load_manifest.err = "manifest not found"
    local result, err = pkginfo.get("mylib")
    assert_nil(result)
    assert_equal("manifest not found", err)
end)

-- ── passes correct args to load_manifest ─────────────────────────────────────

run_test("Passes name, version, tree to load_manifest", function()
    mock_pick_installed.result = {
        "mypkg",
        "2.0",
        "/mytree",
    }
    mock_load_manifest.result = {
        lib = {},
    }
    pkginfo.get("mypkg")
    assert_equal("mypkg", mock_load_manifest.args[1])
    assert_equal("2.0", mock_load_manifest.args[2])
    assert_equal("/mytree", mock_load_manifest.args[3])
end)

-- ── returns full pkginfo table ───────────────────────────────────────────────

run_test("Returns full pkginfo table on success", function()
    mock_pick_installed.result = {
        "mylib",
        "1.0",
        "/tree",
    }
    mock_load_manifest.result = {
        lib = {
            "mylib.so",
        },
        conf = {
            ["mylib.h"] = true,
        },
    }
    mock_path.read_namespace_val = "myns"
    local result, err, ispcfile = pkginfo.get("mylib")
    assert_nil(err)
    assert_not_nil(result)
    assert_equal(false, ispcfile)
    assert_equal("mylib", result.name)
    assert_equal("1.0", result.version)
    assert_equal("/tree", result.tree)
    assert_equal(mock_load_manifest.result, result.manifest)
    assert_equal("/mock/bin", result.dir.bin)
    assert_equal("/mock/lua", result.dir.lua)
    assert_equal("/mock/lib", result.dir.lib)
    assert_equal("/mock/doc", result.dir.doc)
    assert_equal("/mock/conf", result.dir.conf)
    assert_equal("/mock/versions", result.dir.versions)
    assert_equal("/mock/install", result.dir.install)
    assert_equal("/mock/rock_manifest", result.file.rock_manifest)
    assert_equal("/mock/rockspec", result.file.rockspec)
    assert_equal("/mock/rock_namespace", result.file.rock_namespace)
    assert_equal("/mock/conf/mylib.pc.lua", result.file.incdirs_metadata)
    assert_equal("myns", result.namespace)
    -- metadata is built from manifest.conf headers (self-only seed)
    assert_not_nil(result.metadata)
    assert_equal(1, result.metadata.format)
    assert_equal("mylib", result.metadata.package)
    assert_equal("1.0", result.metadata.version)
    assert_equal(1, #result.metadata.incdirs)
    assert_equal("/mock/conf", result.metadata.incdirs[1])
    assert_equal(1, #result.metadata.headers)
    assert_equal("mylib.h", result.metadata.headers[1])
end)

-- ── dependencies are read from installed rockspec, lua excluded ──────────────

run_test("Returns raw dependency strings from rockspec (lua excluded)",
         function()
    mock_pick_installed.result = {
        "mylib",
        "1.0",
        "/tree",
    }
    mock_load_manifest.result = {}
    mock_persist.load_results["/mock/rockspec"] = {
        dependencies = {
            "lua >= 5.1",
            "bar >= 1.0",
            "baz",
        },
    }
    local result = pkginfo.get("mylib")
    assert_not_nil(result)
    assert_equal(2, #result.dependencies)
    assert_equal("bar >= 1.0", result.dependencies[1])
    assert_equal("baz", result.dependencies[2])
end)

-- ── .pc.lua is loaded when present and well-formed ───────────────────────────

local function full_live_pcfile(name, version, tree, headers, incdirs, deps,
                                manifest)
    -- A .pc.lua table that EXACTLY matches what build_live_info would derive
    -- from the current mocks. Reconciliation should leave fresh=true so
    -- ispcfile=true.
    return {
        name = name,
        version = version,
        tree = tree,
        namespace = nil,
        manifest = manifest,
        dir = {
            bin = "/mock/bin",
            lua = "/mock/lua",
            lib = "/mock/lib",
            doc = "/mock/doc",
            conf = "/mock/conf",
            versions = "/mock/versions",
            install = "/mock/install",
        },
        file = {
            rock_manifest = "/mock/rock_manifest",
            rockspec = "/mock/rockspec",
            rock_namespace = "/mock/rock_namespace",
            incdirs_metadata = "/mock/conf/" .. name .. ".pc.lua",
        },
        dependencies = deps,
        metadata = {
            format = 1,
            package = name,
            version = version,
            headers = headers,
            incdirs = incdirs,
            dependencies = deps,
        },
    }
end

run_test("Loads metadata from .pc.lua when fully in sync (ispcfile=true)",
         function()
    mock_pick_installed.result = {
        "mylib",
        "1.0",
        "/tree",
    }
    local manifest = {
        conf = {
            ["mylib.h"] = true,
        },
    }
    mock_load_manifest.result = manifest
    -- Provide a .pc.lua that fully matches the live state.
    mock_persist.load_results["/mock/conf/mylib.pc.lua"] = full_live_pcfile(
                                                               "mylib", "1.0",
                                                               "/tree", {
            "mylib.h",
            "bar.h",
        }, {
            "/mock/conf",
            "/other/conf",
        }, {}, manifest)
    local result, err, ispcfile = pkginfo.get("mylib")
    assert_nil(err)
    assert_not_nil(result)
    assert_equal(true, ispcfile)
    -- cached closure (incdirs/headers) is preserved verbatim from .pc.lua
    assert_equal(2, #result.metadata.incdirs)
    assert_equal("/other/conf", result.metadata.incdirs[2])
end)

-- ── .pc.lua mismatch triggers ispcfile=false to force re-save ────────────────

run_test("Reports ispcfile=false when a managed field mismatches", function()
    mock_pick_installed.result = {
        "mylib",
        "1.0",
        "/tree",
    }
    local manifest = {
        conf = {
            ["mylib.h"] = true,
        },
    }
    mock_load_manifest.result = manifest
    local pc = full_live_pcfile("mylib", "1.0", "/tree", {
        "mylib.h",
    }, {
        "/mock/conf",
    }, {}, manifest)
    -- Simulate a stale namespace in the persisted .pc.lua
    pc.namespace = "stale-ns"
    mock_path.read_namespace_val = nil
    mock_persist.load_results["/mock/conf/mylib.pc.lua"] = pc
    local result, _, ispcfile = pkginfo.get("mylib")
    assert_not_nil(result)
    assert_equal(false, ispcfile)
    -- mismatched field is overwritten with the live value
    assert_nil(result.namespace)
end)

-- ── invalid .pc.lua is ignored, falls back to self-only seed ─────────────────

run_test("Falls back to self-only metadata when .pc.lua format is wrong",
         function()
    mock_pick_installed.result = {
        "mylib",
        "1.0",
        "/tree",
    }
    mock_load_manifest.result = {
        conf = {
            ["mylib.h"] = true,
        },
    }
    mock_persist.load_results["/mock/conf/mylib.pc.lua"] = {
        name = "mylib",
        version = "1.0",
        tree = "/tree",
        metadata = {
            format = 999,
            package = "mylib",
            version = "1.0",
            headers = {},
            incdirs = {},
        },
    }
    local result, _, ispcfile = pkginfo.get("mylib")
    assert_not_nil(result)
    assert_equal(false, ispcfile)
    assert_equal(1, #result.metadata.incdirs)
end)

-- ── nested headers produce subdir incdirs ────────────────────────────────────

run_test("Self-only metadata includes subdir for nested headers", function()
    mock_pick_installed.result = {
        "mylib",
        "1.0",
        "/tree",
    }
    mock_load_manifest.result = {
        conf = {
            ["mylib.h"] = true,
            ["mylib/core.h"] = true,
        },
    }
    local result = pkginfo.get("mylib")
    assert_not_nil(result)
    assert_equal(2, #result.metadata.incdirs)
end)

-- ── pkginfo.save persists with tree-relative paths ───────────────────────────

run_test("pkginfo.save strips tree prefix from dir/file paths", function()
    local info = {
        name = "foo",
        version = "1.0",
        tree = "/tree",
        dir = {
            conf = "/tree/foo/1.0/conf",
            lua = "/tree/foo/1.0/lua",
        },
        file = {
            incdirs_metadata = "/tree/foo/1.0/conf/foo.pc.lua",
            rockspec = "/tree/foo/1.0/foo-1.0-1.rockspec",
        },
        metadata = {
            format = 1,
            package = "foo",
            version = "1.0",
            headers = {
                "foo.h",
            },
            incdirs = {
                "/tree/foo/1.0/conf",
            },
            dependencies = {},
        },
    }
    pkginfo.save(info)
    local saved = mock_persist.save_calls["/tree/foo/1.0/conf/foo.pc.lua"]
    assert_not_nil(saved)
    -- dir/file paths must be stripped of "/tree/" prefix
    assert_equal("foo/1.0/conf", saved.dir.conf)
    assert_equal("foo/1.0/lua", saved.dir.lua)
    assert_equal("foo/1.0/conf/foo.pc.lua", saved.file.incdirs_metadata)
    -- in-memory info must not be mutated
    assert_equal("/tree/foo/1.0/conf", info.dir.conf)
    -- metadata.incdirs (compiler-bound) stays absolute
    assert_equal("/tree/foo/1.0/conf", saved.metadata.incdirs[1])
end)

-- ── pkginfo.save round-trips through tree-relative storage ───────────────────

run_test("pkginfo.save round-trips: load yields the original absolute paths",
         function()
    mock_pick_installed.result = {
        "foo",
        "1.0",
        "/tree",
    }
    mock_path.conf_dir_val = "/tree/foo/1.0/conf"
    mock_path.bin_dir_val = "/tree/foo/1.0/bin"
    mock_path.lua_dir_val = "/tree/foo/1.0/lua"
    mock_path.lib_dir_val = "/tree/foo/1.0/lib"
    mock_path.doc_dir_val = "/tree/foo/1.0/doc"
    mock_path.versions_dir_val = "/tree/foo/1.0/versions"
    mock_path.install_dir_val = "/tree/foo/1.0/install"
    mock_path.rock_manifest_file_val = "/tree/foo/1.0/rock_manifest"
    mock_path.rockspec_file_val = "/tree/foo/1.0/foo-1.0-1.rockspec"
    mock_path.rock_namespace_file_val = "/tree/foo/1.0/rock_namespace"
    local manifest = {
        conf = {
            ["foo.h"] = true,
        },
    }
    mock_load_manifest.result = manifest
    -- First call: no .pc.lua exists; pkginfo builds self-only and returns it.
    local first = pkginfo.get("foo")
    assert_not_nil(first)
    -- Persist it and feed the saved table back as the .pc.lua source.
    pkginfo.save(first)
    local saved = mock_persist.save_calls["/tree/foo/1.0/conf/foo.pc.lua"]
    assert_not_nil(saved)
    mock_persist.load_results["/tree/foo/1.0/conf/foo.pc.lua"] = saved
    -- Second call should load the persisted file and reconstruct absolute
    -- paths so ispcfile=true.
    local second, _, ispcfile = pkginfo.get("foo")
    assert_not_nil(second)
    assert_equal(true, ispcfile)
    assert_equal("/tree/foo/1.0/conf", second.dir.conf)
    assert_equal("/tree/foo/1.0/conf/foo.pc.lua", second.file.incdirs_metadata)
end)

-- ── namespace is nil when read_namespace returns nil ─────────────────────────

run_test("Namespace is nil when read_namespace returns nil", function()
    mock_pick_installed.result = {
        "mylib",
        "1.0",
        "/tree",
    }
    mock_load_manifest.result = {}
    local result = pkginfo.get("mylib")
    assert_not_nil(result)
    assert_nil(result.namespace)
end)

-- ── assertion: pkgname must be a string ──────────────────────────────────────

run_test("Errors when pkgname is not a string", function()
    local ok, err = pcall(pkginfo.get, 123)
    assert_error("pkgname must be a string", ok and true or nil, err)
end)

-- ── assertion: constraints must be a table if provided ───────────────────────

run_test("Errors when constraints is not a table", function()
    local ok, err = pcall(pkginfo.get, "mylib", "not a table")
    assert_error("constraints must be a table", ok and true or nil, err)
end)
