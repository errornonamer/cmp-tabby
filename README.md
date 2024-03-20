# cmp-tabby

[Tabby](https://github.com/tabbyml/tabby) source for [hrsh7th/nvim-cmp](https://github.com/hrsh7th/nvim-cmp)

Should work on all devices supported by Tabby,
although `metal` and `experimental_http` backends are not tested because
I'm too broke to own an Apple device or pay ClosedAI

Roughly based on [tzachar/cmp-tabnine](https://github.com/tzachar/cmp-tabnine)

## Install

### Dependencies

`sh`, `git`, `curl` and [`cargo`](https://www.rust-lang.org/tools/install)

There's no Windows installation script but it shouldn't be that hard to build tabby manually

### Using a plugin manager

Using [Lazy](https://github.com/folke/lazy.nvim/):

```lua
return require("lazy").setup({
 {
     'errornonamer/cmp-tabby',
     build = './install.sh', -- for cpu inference only
     --build = './install.sh --cuda',
     --build = './install.sh --rocm',
     --build = './install.sh --vulkan',
     --build = './install.sh --oapi', -- to use ABSOLUTELY PROPRIETARY models for some reason (just use copilot or smth than smh)
                                      -- or if you have too much ram to spare and would use general purpose language modes for this with openai compatible api server
                                      -- do note that they're untested because I'm too broke to pay the api fee
     dependencies = 'hrsh7th/nvim-cmp',
 }})
```

## Setup

```lua
local tabby = require('cmp_tabby.config')

tabby:setup({
    endpoint = 'http://localhost',
    token = nil,
    device = 'cpu',
    model = 'TabbyML/StarCoder-1B',
    temperature = 0.75,
    max_lines = 1024,
    max_num_results = 10,
    priority = 5000,
    run_on_every_keystroke = true,
    ignored_file_types = { -- default is not to ignore
        -- uncomment to ignore in lua:
        -- 'lua',
    },
})
```

Please note the use of `:` instead of a `.`

See [documentation](https://github.com/errornonamer/cmp-tabby/blob/master/lua/cmp_tabby/config.lua#L3-L23) for description of each options

## Pretty Printing Menu Items

You can use the following to pretty print the completion menu (requires
[lspkind](https://github.com/onsails/lspkind-nvim) and [patched fonts](https://www.nerdfonts.com)):

```lua
local lspkind = require('lspkind')

local source_mapping = {
    buffer = "[Buffer]",
    nvim_lsp = "[LSP]",
    nvim_lua = "[Lua]",
    cmp_tabby = "[LLM]",
    path = "[Path]",
}

require'cmp'.setup {
    sources = {
        { name = 'cmp_tabby' },
    },
    formatting = {
        format = function(entry, vim_item)
            -- if you have lspkind installed, you can use it like
            -- in the following line:
             vim_item.kind = lspkind.symbolic(vim_item.kind, {mode = "symbol"})
             vim_item.menu = source_mapping[entry.source.name]
             if entry.source.name == "cmp_tabby" then
                local detail = (entry.completion_item.labelDetails or {}).detail
                 vim_item.kind = ""
                 if detail and detail:find('.*%%.*') then
                     vim_item.kind = vim_item.kind .. ' ' .. detail
                 end

                 if (entry.completion_item.data or {}).multiline then
                     vim_item.kind = vim_item.kind .. ' ' .. '[ML]'
                 end
             end
             local maxwidth = 80
             vim_item.abbr = string.sub(vim_item.abbr, 1, maxwidth)
             return vim_item
      end,
    },
}
```

## Customize cmp highlight group

The highlight group is `CmpItemKindTabby`, you can change it by:

```lua
vim.api.nvim_set_hl(0, "CmpItemKindTabby", {fg ="#6CC644"})
```

## Multi-Line suggestions

Tabby supports multi-line suggestions. If a suggestion is multi-line, we add
the `entry.completion_item.data.detail.multiline` flag to the completion entry
and the entire suggestion to the `documentation` property of the entry, such
that `cmp` will display the suggested lines in the documentation panel.
