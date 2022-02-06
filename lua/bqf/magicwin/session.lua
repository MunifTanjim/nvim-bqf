local utils = require('bqf.utils')

---
---@class BqfMagicWin
---@field winid number
---@field height number
---@field hrtime number
---@field tune_lnum number
---@field wv table
local Win = {}

---
---@param winid number
---@return BqfMagicWin
function Win:new(winid)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    obj.winid = winid
    obj.height = nil
    obj.hrtime = nil
    obj.tune_lnum = nil
    obj.wv = nil
    return obj
end

function Win:set(o)
    self.height = o.height
    self.hrtime = o.hrtime
    self.tune_lnum = o.tune_lnum
    self.wv = o.wv
end

---
---@class BqfMagicWinSession
---@field private pool table<number, BqfMagicWin>
local MagicWinSession = {pool = {}}

---
---@param qbufnr number
---@return table<number, BqfMagicWin>
function MagicWinSession:get(qbufnr)
    if not self.pool[qbufnr] then
        self.pool[qbufnr] = setmetatable({}, {
            __index = function(tbl, winid)
                rawset(tbl, winid, Win:new(winid))
                return tbl[winid]
            end
        })
    end
    return self.pool[qbufnr]
end

---
---@param qbufnr number
---@param winid number
---@return BqfMagicWin
function MagicWinSession:adjacent_win(qbufnr, winid)
    return self:get(qbufnr)[winid]
end

---
---@param qbufnr number
function MagicWinSession:clean(qbufnr)
    if qbufnr then
        self.pool[qbufnr] = nil
    end
    for bufnr in pairs(self.pool) do
        if not utils.is_buf_loaded(bufnr) then
            self.pool[bufnr] = nil
        end
    end
end

return MagicWinSession
