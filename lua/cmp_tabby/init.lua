local cmp = require('cmp')
local source = require('cmp_tabby.source')

local M = {}

M.setup = function()
    vim.schedule(function()
        M.tabby_source = source.new()
        cmp.register_source('cmp_tabby', M.tabby_source)
    end)
end

return M
