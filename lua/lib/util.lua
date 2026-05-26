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
--- Remove duplicate slashes and any trailing slash from a path string.
--- @param p string Raw path.
--- @return string normalized Normalized path with collapsed slashes.
local function normalize_path(p)
    assert(type(p) == 'string', 'p must be a string')
    return (p:gsub('//+', '/'):gsub('/$', ''))
end

--- Strip a leading `prefix` from an absolute path so it can be persisted in
--- a prefix-portable form. If the path does not start with `prefix`, it is
--- returned unchanged (paths outside the prefix stay absolute).
--- @param prefix string Absolute prefix to strip (typically a tree root).
--- @param p string Absolute path that may live under `prefix`.
--- @return string relpath Prefix-relative path, or original when outside prefix.
local function trim_path_prefix(prefix, p)
    assert(type(prefix) == 'string', 'prefix must be a string')
    assert(type(p) == 'string', 'p must be a string')
    if prefix == '' then
        return p
    end
    local pre = normalize_path(prefix)
    local target = normalize_path(p)
    if target == pre then
        return ''
    end
    local plen = #pre
    if target:sub(1, plen) == pre and target:sub(plen + 1, plen + 1) == '/' then
        return target:sub(plen + 2)
    end
    return p
end

--- Prepend `prefix` to a previously stripped relative path. If the input is
--- already absolute it is returned unchanged so cross-prefix paths survive
--- the round trip.
--- @param prefix string Absolute prefix to restore (typically a tree root).
--- @param p string Relative path produced by trim_path_prefix, or absolute path.
--- @return string abspath Absolute path under prefix, or original when absolute.
local function prepend_path_prefix(prefix, p)
    assert(type(prefix) == 'string', 'prefix must be a string')
    assert(type(p) == 'string', 'p must be a string')
    if p:sub(1, 1) == '/' then
        return p
    elseif p == '' then
        return prefix
    end
    return normalize_path(prefix) .. '/' .. p
end

--- Recursive structural equality for plain Lua tables (no metatables).
--- @param a any Left operand.
--- @param b any Right operand.
--- @return boolean equal True when a and b are deeply equal.
local function deep_equal(a, b)
    if a == b then
        return true
    elseif type(a) ~= 'table' or type(b) ~= 'table' then
        return false
    end
    for k, v in pairs(a) do
        if not deep_equal(v, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

return {
    normalize_path = normalize_path,
    trim_path_prefix = trim_path_prefix,
    prepend_path_prefix = prepend_path_prefix,
    deep_equal = deep_equal,
}
