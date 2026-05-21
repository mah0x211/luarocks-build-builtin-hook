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
local util = require('luarocks.util')
local fs = require('luarocks.fs')

--- Execute a shell command and return whether it succeeded.
--- @param cmd string The command to execute.
--- @return boolean ok
local function exec_ok(cmd)
    local ret = os.execute(cmd)
    return ret == true or ret == 0
end

--- Create a symbolic link, handling existing targets.
--- @param source string The path the symlink points to.
--- @param target string The path of the symlink to create.
--- @return boolean? ok
--- @return string? err
local function create_symlink(source, target)
    if exec_ok(('test -L "%s"'):format(target)) then
        os.remove(target)
    elseif exec_ok(('test -e "%s"'):format(target)) then
        return nil, (target .. ' already exists and is not a symlink, skipping')
    end

    util.printout(('  symlink: %s -> %s'):format(target, source))
    if not exec_ok(('ln -s "%s" "%s"'):format(source, target)) then
        return nil,
               ('  failed to create symlink %s -> %s'):format(target, source)
    end
    return true
end

--- Symlink header files from CONFDIR to LUA_INCDIR based on install.conf entries.
--- For subdirectories containing .h files, creates a directory-level symlink.
--- For root-level .h files, creates individual file symlinks.
--- Failures are reported as warnings and do not abort the build.
--- @param rockspec table rockspec table
local function symlink_headers(rockspec)
    util.printout('hooks.header-symlink: Starting header symlink process')
    local install_conf = rockspec.build and rockspec.build.install and
                             rockspec.build.install.conf
    if not install_conf then
        util.printout('  Warning: No install.conf found in rockspec, skipping')
        return true
    end

    local LUA_INCDIR = rockspec.variables.LUA_INCDIR
    if not LUA_INCDIR then
        util.printout('  Warning: LUA_INCDIR variable is not defined')
        return true
    elseif not fs.is_dir(LUA_INCDIR) then
        util.printout(('  Warning: LUA_INCDIR is not a directory: %s'):format(
                          LUA_INCDIR))
        return true
    end

    local CONFDIR = rockspec.variables.CONFDIR
    if not CONFDIR then
        util.printout('  Warning: CONFDIR variable is not defined')
        return true
    end

    local dir_linked = {}
    for dest_path in pairs(install_conf) do
        local filename = dest_path:match('([^/]+%.h)$')
        if filename then
            local dirname = dest_path:match('^(.*)/[^/]*$')
            if dirname then
                if not dir_linked[dirname] then
                    dir_linked[dirname] = true
                    local ok, err = create_symlink(CONFDIR .. '/' .. dirname,
                                                   LUA_INCDIR .. '/' .. dirname)
                    if not ok then
                        util.printout(('  Warning: %s'):format(err))
                    end
                end
            else
                local ok, err = create_symlink(CONFDIR .. '/' .. filename,
                                               LUA_INCDIR .. '/' .. filename)
                if not ok then
                    util.printout(('  Warning: %s'):format(err))
                end
            end
        end
    end

    return true
end

return symlink_headers
