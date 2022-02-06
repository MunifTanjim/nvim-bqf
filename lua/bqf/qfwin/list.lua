local api = vim.api
local fn = vim.fn

---@class BqfQfItem
---@field bufnr number
---@field module string
---@field lnum number
---@field end_lnum number
---@field col number
---@field end_col number
---@field vcol number
---@field nr number
---@field pattern string
---@field text string
---@field type string
---@field valid number

---@class BqfQfDict
---@field changedtick? number
---@field context? table
---@field id? number
---@field idx? number
---@field items? BqfQfItem[]
---@field nr? number
---@field size? number
---@field title? number
---@field winid? number
---@field filewinid? number

---@class BqfQfList
---@field private items_cache BqfQfItemCache
---@field private pool table<string, BqfQfList>
---@field id number
---@field filewinid number
---@field type string
---@field getqflist fun(param:table):BqfQfDict
---@field setqflist fun(param:table):number
---@field private _changedtick number
---@field private _sign QfWinSign
---@field private _context table
local QfList = {
    ---@class BqfQfItemCache
    ---@field id number
    ---@field items BqfQfItem[]
    items_cache = {id = 0, items = {}}
}

QfList.pool = setmetatable({}, {
    __index = function(tbl, id0)
        rawset(tbl, id0, QfList:new(id0))
        return tbl[id0]
    end
})

local function split_id(id0)
    local id, filewinid = unpack(vim.split(id0, ':'))
    return tonumber(id), tonumber(filewinid)
end

local function build_id(qid, filewinid)
    return ('%d:%d'):format(qid, filewinid or 0)
end

---
---@param filewinid number
---@return fun(param:table):BqfQfDict
local function get_qflist(filewinid)
    return function(what)
        local list = filewinid > 0 and fn.getloclist(filewinid, what) or fn.getqflist(what)
        -- TODO
        -- upstream issue vimscript -> lua, function can't be transformed directly
        -- quickfixtextfunc may be a Funcref value.
        -- get the name of function in vimscript instead of function reference
        local qftf = list.quickfixtextfunc
        if type(qftf) == 'userdata' and qftf == vim.NIL then
            local qftf_cmd
            if filewinid > 0 then
                qftf_cmd = [[echo getloclist(0, {'quickfixtextfunc': 0}).quickfixtextfunc]]
            else
                qftf_cmd = [[echo getqflist({'quickfixtextfunc': 0}).quickfixtextfunc]]
            end
            local func_name = api.nvim_exec(qftf_cmd, true)
            local lambda_name = func_name:match('<lambda>%d+')
            if lambda_name then
                func_name = lambda_name
            end
            list.quickfixtextfunc = fn[func_name]
        end
        return list
    end
end

local function set_qflist(filewinid)
    return filewinid > 0 and function(...)
        return fn.setloclist(filewinid, ...)
    end or fn.setqflist
end

---
---@param id0 string
---@return BqfQfList
function QfList:new(id0)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    local id, filewinid = split_id(id0)
    obj.id = id
    obj.filewinid = filewinid
    obj.type = filewinid == 0 and 'qf' or 'loc'
    obj.getqflist = get_qflist(filewinid)
    obj.setqflist = set_qflist(filewinid)
    obj._changedtick = 0
    return obj
end

---
---@param what table
---@return boolean
function QfList:new_qflist(what)
    return self.setqflist({}, ' ', what) ~= -1
end

---
---@param what table
---@return boolean
function QfList:set_qflist(what)
    return self.setqflist({}, 'r', what) ~= -1
end

---
---@param what table
---@return BqfQfDict
function QfList:get_qflist(what)
    return self.getqflist(what)
end

---
---@return number
function QfList:changedtick()
    local cd = self.getqflist({id = self.id, changedtick = 0}).changedtick
    if cd ~= self._changedtick then
        self._context = nil
        self._sign = nil
        QfList.items_cache = {id = 0, items = {}}
    end
    return cd
end

---
---@return table
function QfList:context()
    local ctx
    local cd = self:changedtick()
    if not self._context then
        local qdict = self.getqflist({id = self.id, context = 0})
        self._changedtick = cd
        local c = qdict.context
        self._context = type(c) == 'table' and c or {}
    end
    ctx = self._context
    return ctx
end

---
---@return QfWinSign
function QfList:sign()
    local sg
    local cd = self:changedtick()
    if not self._sign then
        self._changedtick = cd
        self._sign = require('bqf.qfwin.sign'):new()
    end
    sg = self._sign
    return sg
end

---
---@return BqfQfItem[]
function QfList:items()
    local items
    local c = QfList.items_cache
    local c_id, c_items = c.id, c.items
    local cd = self:changedtick()
    if cd == self._changedtick and c_id == self.id then
        items = c_items
    end
    if not items then
        local qdict = self.getqflist({id = self.id, items = 0})
        items = qdict.items
        QfList.items_cache = {id = self.id, items = items}
    end
    return items
end

---
---@param idx number
---@return BqfQfItem
function QfList:item(idx)
    local cd = self:changedtick()

    local e
    local c = QfList.items_cache
    if cd == self._changedtick and c.id == self.id then
        e = c.items[idx]
    else
        local items = self.getqflist({id = self.id, idx = idx, items = 0}).items
        if #items == 1 then
            e = items[1]
        end
    end
    return e
end

function QfList:change_idx(idx)
    local old_idx = self:get_qflist({idx = idx})
    if idx ~= old_idx then
        self:set_qflist({idx = idx})
        self._changedtick = self.getqflist({id = self.id, changedtick = 0}).changedtick
    end
end

---
---@return table
function QfList:get_winview()
    return self.winview
end

---
---@param winview table
function QfList:set_winview(winview)
    self.winview = winview
end

local function verify(pool)
    for id0, o in pairs(pool) do
        if o.getqflist({id = o.id}).id ~= o.id then
            pool[id0] = nil
        end
    end
end

---
---@param qwinid number
---@param id number
---@return BqfQfList
function QfList:get(qwinid, id)
    local qid, filewinid
    if not id then
        qwinid = qwinid or api.nvim_get_current_win()
        local what = {id = 0, filewinid = 0}
        local winfo = fn.getwininfo(qwinid)[1]
        if winfo.quickfix == 1 then
            ---@type BqfQfDict
            local qdict = winfo.loclist == 1 and fn.getloclist(0, what) or fn.getqflist(what)
            qid, filewinid = qdict.id, qdict.filewinid
        else
            return nil
        end
    else
        qid, filewinid = unpack(id)
    end
    verify(self.pool)
    return self.pool[build_id(qid, filewinid or 0)]
end

return QfList
