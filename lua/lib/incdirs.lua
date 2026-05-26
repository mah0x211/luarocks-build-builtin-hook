--
-- Copyright (C) 2026 Masatoshi Fukunaga
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
local pkginfo = require('luarocks.build.hooks.lib.pkginfo')
local queries_from_dep_string = require('luarocks.queries').from_dep_string

--- Append elements from `src` array into `dst` array, skipping duplicates.
--- The `seen` set is mutated to track membership; callers must seed it from
--- the initial contents of `dst` before the first call so subsequent rounds
--- can reuse the same set without re-scanning.
--- @param dst string[] Destination array (mutated).
--- @param src string[]? Source array, or nil for no-op.
--- @param seen table<string,boolean> Per-node dedup set (mutated).
--- @return integer added Number of elements actually appended to dst.
local function append_uniques(dst, src, seen)
    if not src then
        return 0
    end
    local added = 0
    for _, v in ipairs(src) do
        if not seen[v] then
            seen[v] = true
            dst[#dst + 1] = v
            added = added + 1
        end
    end
    return added
end

--- Round-robin fixed-point iteration: keep merging dependency metadata into
--- each legacy (non-.pc.lua) node until no node grows in a full pass. After
--- convergence, attempt to persist each non-.pc.lua node's resolved metadata
--- so subsequent builds can hit the fast path. Persist failures are silently
--- ignored: callers continue using the in-memory pkginfo so the build
--- proceeds even when the dependency tree is read-only.
--- @param graph table Dependency graph built by traverse_pkginfo.
local function resolve_pkgmetadata(graph)
    -- Seed per-node dedup sets from the initial self-only metadata so the
    -- fixed-point loop never re-adds entries that were already present at
    -- the start of resolution.
    local seen_headers = {}
    local seen_incdirs = {}
    for _, name in ipairs(graph) do
        local hset, iset = {}, {}
        local meta = graph[name].info.metadata
        for _, v in ipairs(meta.headers) do
            hset[v] = true
        end
        for _, v in ipairs(meta.incdirs) do
            iset[v] = true
        end
        seen_headers[name] = hset
        seen_incdirs[name] = iset
    end

    local stable = false
    while not stable do
        stable = true
        for i = #graph, 1, -1 do
            local name = graph[i]
            local node = graph[name]
            if not node.ispcfile then
                local meta = node.info.metadata
                local added = 0
                for _, depinfo in pairs(node.deps) do
                    local dmeta = depinfo.metadata
                    if dmeta then
                        added = added +
                                    append_uniques(meta.headers, dmeta.headers,
                                                   seen_headers[name])
                        added = added +
                                    append_uniques(meta.incdirs, dmeta.incdirs,
                                                   seen_incdirs[name])
                    end
                end
                if added > 0 then
                    stable = false
                end
            end
        end
    end

    for _, name in ipairs(graph) do
        local node = graph[name]
        if not node.ispcfile then
            pkginfo.save(node.info)
        end
    end
end

--- Recursively walk the dependency graph rooted at `pkgname`, populating
--- both `pkgstats` (build-wide info cache) and `graph` (per-resolution
--- structure). `graph[pkgname] = { info, ispcfile, deps = { name = depinfo } }`
--- and `graph[1..N]` records the visit order in its array part.
--- @param pkgstats table<string,luarocks.build.hooks.pkginfo> Build-wide cache.
--- @param pkgname string Package name to resolve.
--- @param constraints table? Optional version constraints.
--- @param graph table Graph being constructed (mutated).
--- @return luarocks.build.hooks.pkginfo? info Cached/loaded pkginfo, or nil on error.
--- @return any err Error message on failure.
local function traverse_pkginfo(pkgstats, pkgname, constraints, graph)
    local cached = pkgstats[pkgname]
    if cached then
        return cached
    end

    local info, err, ispcfile = pkginfo.get(pkgname, constraints)
    if not info then
        return nil, err
    end

    -- Cache before descending so cycles see a partial info entry.
    pkgstats[pkgname] = info

    local pkgdeps = {}
    for _, depstr in ipairs(info.dependencies or {}) do
        local qry, qerr = queries_from_dep_string(depstr)
        if not qry then
            return nil, qerr
        end
        if qry.name == pkgname then
            return nil, ('self dependency in %q: %q'):format(pkgname, depstr)
        end

        local depinfo, derr = traverse_pkginfo(pkgstats, qry.name,
                                               qry.constraints, graph)
        if derr then
            return nil, derr
        end
        if depinfo then
            pkgdeps[qry.name] = depinfo
        end
    end

    graph[pkgname] = {
        info = info,
        ispcfile = ispcfile,
        deps = pkgdeps,
    }
    graph[#graph + 1] = pkgname
    return info
end

--- Return the resolved include metadata for `pkgname`. Builds a dependency
--- graph rooted at `pkgname`, runs a fixed-point merge of dependency
--- metadata, then returns the root package's completed metadata table.
--- @param pkgstats table Build-wide pkgname -> info cache.
--- @param pkgname string The package to resolve include directories for.
--- @param constraints table? Optional version constraints for the root package.
--- @return luarocks.build.hooks.pkginfo.metadata? metadata Resolved metadata,
---     or nil when the package is not installed.
--- @return any err Error message on failure.
local function incdirs(pkgstats, pkgname, constraints)
    assert(type(pkgstats) == 'table', 'pkgstats must be a table')

    local graph = {}
    local info, err = traverse_pkginfo(pkgstats, pkgname, constraints, graph)
    if not info then
        return nil, err
    end
    resolve_pkgmetadata(graph)
    -- nothing to expose when the root package has no headers / includes at all
    if #info.metadata.incdirs == 0 then
        return nil
    end
    return info.metadata
end

return incdirs
