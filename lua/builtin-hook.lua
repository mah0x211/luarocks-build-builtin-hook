local builtin = require("luarocks.build.builtin")
local fs = require("luarocks.fs")
local util = require("luarocks.util")

--- Create a shallow copy of a table, recursively copying any nested tables.
local function copy_table(tbl, visited)
    if tbl == nil then
        return nil
    end

    visited = visited or {}
    if visited[tbl] then
        return visited[tbl]
    end

    local t2 = {}
    visited[tbl] = t2
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            v = copy_table(v, visited)
        end
        t2[k] = v
    end
    return t2
end

--- Create an environment table for executing hook scripts.
local function getenv()
    local env = {
        _G = nil, -- placeholder
        _VERSION = _VERSION,

        -- Lua 5.1
        assert = assert,
        collectgarbage = collectgarbage,
        dofile = dofile,
        error = error,
        getfenv = getfenv,
        getmetatable = getmetatable,
        ipairs = ipairs,
        load = load,
        loadfile = loadfile,
        loadstring = loadstring,
        module = module,
        next = next,
        pairs = pairs,
        pcall = pcall,
        print = print,
        rawequal = rawequal,
        rawget = rawget,
        rawset = rawset,
        require = require,
        select = select,
        setfenv = setfenv,
        setmetatable = setmetatable,
        tonumber = tonumber,
        tostring = tostring,
        type = type,
        xpcall = xpcall,

        coroutine = copy_table(coroutine),
        debug = copy_table(debug),
        io = copy_table(io),
        math = copy_table(math),
        os = copy_table(os),
        package = copy_table(package),
        string = copy_table(string),
        table = copy_table(table),

        unpack = unpack or table.unpack, -- table.unpack in Lua 5.2+
        bit32 = copy_table(_G.bit32), -- Lua 5.2+
        warn = _G.warn, -- Lua 5.4+
        utf8 = copy_table(_G.utf8), -- Lua 5.3+
    }
    env._G = env
    return env
end

local function load_hook(hook_file, env)
    local chunk, err
    if _G.setfenv then
        chunk, err = loadfile(hook_file)
        if chunk then
            _G.setfenv(chunk, env)
        end
    else
        chunk, err = loadfile(hook_file, "bt", env) -- luacheck: no max line length
    end
    return chunk, err
end

local function execute_hook(rockspec, name)
    local build = rockspec.build
    local hook_file = build[name]
    if not hook_file then
        return true
    end

    if not fs.exists(hook_file) then
        return nil, "Hook script not found: " .. hook_file
    end

    util.printout("Running hook: " .. hook_file)

    local env = getenv()
    local chunk, err = load_hook(hook_file, env)
    if not chunk then
        return nil,
               "Failed to load " .. name .. ": " .. (err or "unknown error")
    end

    local ok, run_err = pcall(chunk, rockspec)
    if not ok then
        return nil,
               "Failed to run " .. name .. ": " .. (run_err or "unknown error")
    end
    return true
end

local function run(rockspec, no_install)
    -- 1. Run before_build if present
    local ok, err = execute_hook(rockspec, "before_build")
    if not ok then
        return nil, err
    end

    -- 2. Delegate to standard builtin backend
    ok, err = builtin.run(rockspec, no_install)
    if not ok then
        return nil, err
    end

    -- 3. Run after_build if present
    ok, err = execute_hook(rockspec, "after_build")
    if not ok then
        return nil, err
    end

    return true
end

return {
    run = run,
}
