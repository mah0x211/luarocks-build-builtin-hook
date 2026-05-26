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
local new_queries = require('luarocks.queries').new
local pick_installed_rock = require('luarocks.search').pick_installed_rock
local load_manifest = require('luarocks.manif').load_rock_manifest
local path = require('luarocks.path')
local persist = require('luarocks.persist')
local util = require('luarocks.build.hooks.lib.util')
local normalize_path = util.normalize_path
local trim_path_prefix = util.trim_path_prefix
local prepend_path_prefix = util.prepend_path_prefix
local deep_equal = util.deep_equal

local PCFILE_FORMAT = 1

--- Apply `fn` to every string value of the subtable at `tbl[key]`. Used to
--- convert dir/file path fields between absolute and tree-relative forms.
--- @param tbl table Target table to mutate.
--- @param key string Top-level key whose subtable holds path strings.
--- @param fn fun(s:string):string Transformation applied to every string value.
local function transform_path_table(tbl, key, fn)
    local sub = tbl[key]
    if type(sub) ~= 'table' then
        return
    end
    for k, v in pairs(sub) do
        if type(v) == 'string' then
            sub[k] = fn(v)
        end
    end
end

--- Build a self-only metadata table from `manifest.conf` header entries.
--- The headers exposed by the package itself are listed in `headers`, and the
--- include directories needed by a consumer (the CONFDIR plus any header
--- subdirectories) are listed in `incdirs`.
--- @param pkgname string Package name.
--- @param version string Package version.
--- @param confdir string Absolute path to the package CONFDIR.
--- @param manifest table Rock manifest as loaded by load_rock_manifest.
--- @param deps string[] Raw dependency strings (lua excluded).
--- @return luarocks.build.hooks.pkginfo.metadata metadata Self-only metadata seed.
local function build_self_metadata(pkgname, version, confdir, manifest, deps)
    local nodup = {}
    local headers = {}
    local incdirs = {}

    for pathname in pairs(manifest and manifest.conf or {}) do
        local filename = pathname:match('([^/]+%.h)$')
        if filename then
            local dirname = pathname:match('^(.*)/[^/]*$')
            if dirname then
                dirname = confdir .. '/' .. normalize_path(dirname)
            else
                dirname = confdir
            end
            if not nodup[dirname] then
                nodup[dirname] = true
                incdirs[#incdirs + 1] = dirname
            end
            local hkey = 'h:' .. pathname
            if not nodup[hkey] then
                nodup[hkey] = true
                headers[#headers + 1] = filename
            end
        end
    end

    return {
        format = PCFILE_FORMAT,
        package = pkgname,
        version = version,
        headers = headers,
        incdirs = incdirs,
        dependencies = deps,
    }
end

--- @class luarocks.build.hooks.pkginfo.dir
--- @field bin string The directory for binary files.
--- @field lua string The directory for Lua files.
--- @field lib string The directory for library files.
--- @field doc string The directory for documentation files.
--- @field conf string The directory for configuration files.
--- @field versions string The directory for version files.
--- @field install string The directory for installation files.

--- @class luarocks.build.hooks.pkginfo.file
--- @field rock_manifest string The path to the rock manifest file.
--- @field rockspec string The path to the rockspec file.
--- @field rock_namespace string The path to the rock namespace file.
--- @field incdirs_metadata string The path to the <pkgname>.pc.lua metadata file.

--- @class luarocks.build.hooks.pkginfo.metadata
--- @field format integer Metadata format version.
--- @field package string Package name this metadata describes.
--- @field version string Package version this metadata describes.
--- @field headers string[] Header file names exposed by the resolved closure.
--- @field incdirs string[] Include directories needed by the resolved closure (absolute paths).
--- @field dependencies string[] Raw dependency strings preserved from rockspec.

--- @class luarocks.build.hooks.pkginfo
--- @field name string The name of the package.
--- @field version string The version of the package.
--- @field tree string Absolute tree where the package is installed.
--- @field dir luarocks.build.hooks.pkginfo.dir Package directories (absolute paths in memory).
--- @field file luarocks.build.hooks.pkginfo.file Package files (absolute paths in memory).
--- @field namespace string? The namespace of the package, if any.
--- @field manifest table The rock manifest loaded from the rock_manifest file.
--- @field dependencies string[] Raw dependency strings from the installed rockspec (lua excluded).
--- @field metadata luarocks.build.hooks.pkginfo.metadata Self or fully-resolved include metadata.

--- Compose the .pc.lua metadata file path for a package.
--- @param confdir string Absolute path of the package CONFDIR.
--- @param pkgname string Package name (already normalized by LuaRocks).
--- @return string pcpath Absolute path to <confdir>/<pkgname>.pc.lua.
local function pcfile_path(confdir, pkgname)
    return normalize_path(confdir) .. '/' .. pkgname .. '.pc.lua'
end

--- Validate that a loaded .pc.lua table is a coherent pkginfo entry for the
--- given installed rock. Only structural and identity checks are performed;
--- per-field reconciliation against the live LuaRocks state is done later.
--- @param tbl any Raw value returned by persist.load_into_table.
--- @param name string Resolved package name.
--- @param version string Resolved package version.
--- @param tree string Resolved tree root.
--- @return boolean ok True when the table can be treated as a candidate pkginfo.
local function is_valid_pcfile(tbl, name, version, tree)
    if type(tbl) ~= 'table' then
        return false
    elseif type(tbl.metadata) ~= 'table' then
        return false
    elseif tbl.metadata.format ~= PCFILE_FORMAT then
        return false
    elseif tbl.name ~= name or tbl.version ~= version then
        return false
    elseif tbl.tree ~= tree then
        return false
    elseif tbl.metadata.package ~= name or tbl.metadata.version ~= version then
        return false
    elseif type(tbl.metadata.headers) ~= 'table' then
        return false
    elseif type(tbl.metadata.incdirs) ~= 'table' then
        return false
    end
    for _, v in ipairs(tbl.metadata.incdirs) do
        if type(v) ~= 'string' then
            return false
        end
    end
    for _, v in ipairs(tbl.metadata.headers) do
        if type(v) ~= 'string' then
            return false
        end
    end
    return true
end

--- Try to load `<CONFDIR>/<pkgname>.pc.lua` and return it with tree-relative
--- paths re-expanded to absolute paths. Missing files and structurally
--- invalid content are not errors; they return nil so the caller can fall
--- back to building metadata from the live manifest.
--- @param pcpath string Absolute path to the .pc.lua file.
--- @param name string Resolved package name.
--- @param version string Resolved package version.
--- @param tree string Resolved tree root.
--- @return luarocks.build.hooks.pkginfo? loaded Pkginfo as persisted, or nil.
local function try_load_pcfile(pcpath, name, version, tree)
    local tbl = persist.load_into_table(pcpath)
    if not is_valid_pcfile(tbl, name, version, tree) then
        return nil
    end
    transform_path_table(tbl, 'dir', function(s)
        return prepend_path_prefix(tree, s)
    end)
    transform_path_table(tbl, 'file', function(s)
        return prepend_path_prefix(tree, s)
    end)
    return tbl
end

--- Load raw dependency strings from the installed rockspec. Entries that
--- target the `lua` interpreter itself are skipped because they are not real
--- package dependencies.
--- @param rockspec_path string Absolute path of the installed rockspec.
--- @return string[] deps Raw dependency strings (lua excluded).
local function load_dependencies(rockspec_path)
    local rs = persist.load_into_table(rockspec_path)
    if type(rs) ~= 'table' then
        return {}
    elseif type(rs.dependencies) ~= 'table' then
        return {}
    end

    local deps = {}
    for _, depstr in ipairs(rs.dependencies) do
        if type(depstr) == 'string' then
            local first = depstr:match('^%s*([%w%._%-]+)')
            if first and first:lower() ~= 'lua' then
                deps[#deps + 1] = depstr
            end
        end
    end
    return deps
end

--- Construct a freshly derived pkginfo table directly from LuaRocks library
--- calls, without consulting any persisted `.pc.lua` cache.
--- @param name string Resolved package name.
--- @param version string Resolved package version.
--- @param tree string Resolved tree root.
--- @param rock_manifest table Rock manifest loaded by load_rock_manifest.
--- @return luarocks.build.hooks.pkginfo info Live pkginfo with self-only metadata.
local function build_live_info(name, version, tree, rock_manifest)
    local confdir = path.conf_dir(name, version, tree)
    local rockspec_file = path.rockspec_file(name, version, tree)
    local info = {
        name = name,
        version = version,
        tree = tree,
        namespace = path.read_namespace(name, version, tree),
        manifest = rock_manifest,
        dir = {
            bin = path.bin_dir(name, version, tree),
            lua = path.lua_dir(name, version, tree),
            lib = path.lib_dir(name, version, tree),
            doc = path.doc_dir(name, version, tree),
            conf = confdir,
            versions = path.versions_dir(name, tree),
            install = path.install_dir(name, version, tree),
        },
        file = {
            rock_manifest = path.rock_manifest_file(name, version, tree),
            rockspec = rockspec_file,
            rock_namespace = path.rock_namespace_file(name, version, tree),
            incdirs_metadata = pcfile_path(confdir, name),
        },
    }
    info.dependencies = load_dependencies(rockspec_file)
    info.metadata = build_self_metadata(name, version, normalize_path(confdir),
                                        rock_manifest, info.dependencies)
    return info
end

--- Reconcile a pkginfo loaded from `.pc.lua` against the live state derived
--- from LuaRocks. Each managed top-level field is compared with the live
--- value; any discrepancy causes the live value to overwrite the loaded one
--- and the result is marked stale so the caller can re-persist it.
---
--- The cached include closure (`metadata.headers` / `metadata.incdirs`) is
--- intentionally NOT validated here - that is the whole point of the cache
--- and is refreshed only by the dependency-graph resolver in incdirs.lua.
--- @param loaded luarocks.build.hooks.pkginfo Pkginfo loaded from .pc.lua.
--- @param live luarocks.build.hooks.pkginfo Pkginfo derived from LuaRocks state.
--- @return luarocks.build.hooks.pkginfo merged Reconciled pkginfo (loaded mutated).
--- @return boolean fresh True when nothing needed to be overwritten.
local function reconcile_pcfile(loaded, live)
    local fresh = true
    local fields = {
        'name',
        'version',
        'tree',
        'namespace',
        'dir',
        'file',
        'manifest',
        'dependencies',
    }
    for _, f in ipairs(fields) do
        if not deep_equal(loaded[f], live[f]) then
            loaded[f] = live[f]
            fresh = false
        end
    end
    local lmeta = loaded.metadata
    local rmeta = live.metadata
    if lmeta.format ~= rmeta.format then
        lmeta.format = rmeta.format
        fresh = false
    end
    if lmeta.package ~= rmeta.package then
        lmeta.package = rmeta.package
        fresh = false
    end
    if lmeta.version ~= rmeta.version then
        lmeta.version = rmeta.version
        fresh = false
    end
    if not deep_equal(lmeta.dependencies, rmeta.dependencies) then
        lmeta.dependencies = rmeta.dependencies
        fresh = false
    end
    return loaded, fresh
end

--- Return the package information for the currently installed version of a
--- package. The third return value indicates whether the persisted `.pc.lua`
--- file was fully in sync with the live LuaRocks state (`true`) or had to be
--- reconstructed in whole or in part (`false`); the latter case signals that
--- the resolver should re-persist the file once the dependency closure is
--- finalized.
--- @param pkgname string The name of the package to get the information for.
--- @param constraints table? Optional constraints for the package version.
--- @return luarocks.build.hooks.pkginfo? pkginfo Resolved pkginfo, or nil when
---     the package is not installed.
--- @return any err Error message when the package exists but cannot be read.
--- @return boolean? ispcfile True when the returned pkginfo matched the
---     persisted .pc.lua exactly.
local function get(pkgname, constraints)
    assert(type(pkgname) == 'string', 'pkgname must be a string')
    assert(constraints == nil or type(constraints) == 'table',
           'constraints must be a table if provided')

    local query = new_queries(pkgname, nil, nil, false)
    query.constraints = constraints or query.constraints
    local name, version, tree = pick_installed_rock(query,
                                                    path.root_from_rocks_dir(
                                                        path.rocks_dir()))
    if not name then
        return
    end

    local rock_manifest, err = load_manifest(name, version, tree)
    if not rock_manifest then
        return nil, err
    end

    local live = build_live_info(name, version, tree, rock_manifest)
    local loaded = try_load_pcfile(live.file.incdirs_metadata, name, version,
                                   tree)
    if loaded then
        local merged, fresh = reconcile_pcfile(loaded, live)
        return merged, nil, fresh
    end
    return live, nil, false
end

--- Shallow-copy a pkginfo and tree-relativize its dir/file path subtables so
--- the resulting table can be serialized to `.pc.lua` without baking in
--- absolute paths that would break under a tree relocation. The original
--- pkginfo is left untouched. `metadata.incdirs` / `metadata.headers` are
--- preserved as absolute paths because they are consumed by the compiler.
--- @param info luarocks.build.hooks.pkginfo Live pkginfo.
--- @return luarocks.build.hooks.pkginfo cloned Save-ready pkginfo copy.
local function pkginfo_for_save(info)
    local tree = info.tree
    local copy = {}
    for k, v in pairs(info) do
        if k == 'dir' or k == 'file' then
            local sub = {}
            for sk, sv in pairs(v) do
                sub[sk] = sv
            end
            copy[k] = sub
        else
            copy[k] = v
        end
    end
    transform_path_table(copy, 'dir', function(s)
        return trim_path_prefix(tree, s)
    end)
    transform_path_table(copy, 'file', function(s)
        return trim_path_prefix(tree, s)
    end)
    return copy
end

--- Persist `info` to its `<CONFDIR>/<pkgname>.pc.lua` file with all
--- tree-internal dir/file paths stripped of their tree prefix so the file
--- remains portable across tree relocations.
--- @param info luarocks.build.hooks.pkginfo Pkginfo to persist.
--- @return boolean? ok True on successful save, nil on failure.
--- @return any err Error message when the file cannot be saved.
local function save(info)
    local pcpath = info.file and info.file.incdirs_metadata
    if not pcpath then
        return nil, 'missing incdirs_metadata path'
    end
    return persist.save_from_table(pcpath, pkginfo_for_save(info))
end

return {
    save = save,
    get = get,
}
