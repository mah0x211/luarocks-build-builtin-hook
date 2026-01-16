require("luacov")

-- Mock framework
local function mock(name, table)
    package.loaded[name] = table
end

-- Mock dependencies
local mock_builtin = {
    run_called = 0,
    run_result = true,
    run_error = nil,
}
mock_builtin.reset = function(self)
    self.run_called = 0
    self.run_result = true
    self.run_error = nil
end
mock_builtin.run = function(rockspec, no_install)
    mock_builtin.run_called = mock_builtin.run_called + 1
    return mock_builtin.run_result, mock_builtin.run_error
end
mock("luarocks.build.builtin", mock_builtin)

local mock_fs = {
    exists_result = true,
}
mock_fs.reset = function(self)
    self.exists_result = true
end
mock_fs.exists = function(path)
    return mock_fs.exists_result
end
mock_fs.Q = function(s)
    return "'" .. s .. "'"
end
mock_fs.execute = function(cmd)
    table.insert(mock_fs.executed_cmds, cmd)
    return mock_fs.execute_result
end
mock("luarocks.fs", mock_fs)

local mock_cfg = {
    variables = {
        LUA = "lua",
    },
}
mock("luarocks.core.cfg", mock_cfg)

local mock_util = {
    printout = function(...)
    end,
}
mock("luarocks.util", mock_util)

-- Global Mock for loadfile and setfenv
local mock_chunk_func = nil
local mock_env_captured = nil

function _G.loadfile(filename, mode, env)
    if env then
        mock_env_captured = env
    end
    return function(...)
        if mock_chunk_func then
            return mock_chunk_func(...)
        end
    end
end

if _G.setfenv then
    local original_setfenv = _G.setfenv
    _G.setfenv = function(f, env)
        mock_env_captured = env
        return original_setfenv(f, env)
    end
end

-- Load module under test
local builtin_hook = require("luarocks.build.builtin-hook")

-- Test Helper
local function run_test(name, func)
    io.write("Running " .. name .. "... ")
    mock_builtin:reset()
    mock_fs:reset()
    mock_chunk_func = nil
    mock_env_captured = nil
    local status, err = pcall(func)
    if status then
        print("OK")
    else
        print("FAIL")
        print(err)
        os.exit(1)
    end
end

local function assert_true(val, msg)
    if not val then
        error((msg or "Expected true") .. ", got " .. tostring(val))
    end
end

local function assert_false(val, msg)
    if val then
        error((msg or "Expected false") .. ", got " .. tostring(val))
    end
end

local function assert_equal(expected, actual, msg)
    if expected ~= actual then
        error((msg or "") .. " Expected " .. tostring(expected) .. ", got " ..
                  tostring(actual))
    end
end

-- Tests

run_test("No Hooks", function()
    local rockspec = {
        build = {},
    }
    local ok, _ = builtin_hook.run(rockspec)
    assert_true(ok)
    assert_equal(1, mock_builtin.run_called, "builtin.run should be called once")
end)

run_test("Before Hook Success", function()
    local rockspec = {
        build = {
            before_build = "pre.lua",
        },
        variables = {
            TARGET = "original"
        }
    }
    -- Verify rockspec is passed as argument (...)
    -- and that modifications are visible to builtin.run
    mock_chunk_func = function(rs)
        rs.variables.TARGET = "modified"
    end

    local original_builtin_run = mock_builtin.run
    local captured_rs_at_run = nil
    mock_builtin.run = function(rs, no_install)
        captured_rs_at_run = rs
        return original_builtin_run(rs, no_install)
    end

    local ok, _ = builtin_hook.run(rockspec)
    mock_builtin.run = original_builtin_run -- restore

    assert_true(ok)
    assert_equal("modified", rockspec.variables.TARGET, "Rockspec should be modified by hook")
    assert_equal("modified", captured_rs_at_run.variables.TARGET, "Builtin should see modifications")
    assert_true(mock_env_captured ~= nil, "Should capture environment")
    assert_true(mock_env_captured.type ~= nil, "Environment should contain type")
end)

run_test("Before Hook Fail", function()
    local rockspec = {
        build = {
            before_build = "pre.lua",
        },
    }
    mock_chunk_func = function() error("Simulated failure") end
    local ok, err = builtin_hook.run(rockspec)
    assert_false(ok, "Should fail")
    assert_true(string.find(err, "Simulated failure"),
                "Should return correct error")
    assert_equal(0, mock_builtin.run_called, "builtin.run should NOT be called")
end)

run_test("After Hook Success", function()
    local rockspec = {
        build = {
            after_build = "post.lua",
        },
    }
    local captured_rs_at_hook = nil
    mock_chunk_func = function(rs)
        captured_rs_at_hook = rs
    end

    local ok, _ = builtin_hook.run(rockspec)
    assert_true(ok)
    assert_equal(rockspec, captured_rs_at_hook, "Should receive rockspec as argument")
    assert_true(mock_env_captured ~= nil, "Should capture environment")
    assert_equal(1, mock_builtin.run_called, "builtin.run should be called")
end)

run_test("After Hook Fail", function()
    local rockspec = {
        build = {
            after_build = "post.lua",
        },
    }
    mock_chunk_func = function() error("Simulated failure") end
    -- Note: verify reset works
    mock_builtin.run_result = true

    local ok, err = builtin_hook.run(rockspec)
    assert_false(ok, "Should fail")
    assert_true(string.find(err, "Simulated failure"),
                "Should return correct error")
    assert_equal(1, mock_builtin.run_called,
                 "builtin.run SHOULD be called before after_build fails")
end)

run_test("Builtin Fail", function()
    local rockspec = {
        build = {
            after_build = "post.lua",
        },
    }
    mock_builtin.run_result = nil
    mock_builtin.run_error = "Builtin error"

    local hook_called = false
    mock_chunk_func = function()
        hook_called = true
    end

    local ok, err = builtin_hook.run(rockspec)
    assert_false(ok)
    assert_equal("Builtin error", err)
    assert_false(hook_called, "After hook should NOT run if builtin fails")
end)

run_test("Invalid Lua Hook", function()
    local rockspec = {
        build = {
            before_build = "invalid.lua",
        },
    }
    -- Mock loadfile to return nil and an error message (simulating syntax error)
    local original_loadfile_wrapped = _G.loadfile
    _G.loadfile = function()
        return nil, "syntax error: unexpected symbol"
    end

    local ok, err = builtin_hook.run(rockspec)
    _G.loadfile = original_loadfile_wrapped -- restore

    assert_false(ok)
    assert_true(string.find(err, "syntax error: unexpected symbol"),
                "Should report syntax error from loadfile")
end)

run_test("Hook File Not Found", function()
    local rockspec = {
        build = {
            before_build = "missing.lua",
        },
    }
    mock_fs.exists_result = false

    local ok, err = builtin_hook.run(rockspec)
    assert_false(ok)
    assert_true(string.find(err, "Hook script not found"),
                "Should report missing file")
end)

print("All tests passed!")
