local M = {}

---@alias Device 'cpu' | 'cuda' | 'rocm' | 'metal' | 'experimental_http'

---@class ApiModel Model configuration for `experimental_http` device - UNTESTED!!
---@field kind 'openai' Kind of api the endpoint is running Currently Tabby only supports ClosedAI API
---@field model_name string Name of the model
---@field api_endpoint string Inference endpoint
---@field prompt_template string Template to use for code completion
---@field chat_template string? Template to use for chat

---@class Config cmp-tabby config table
---@field endpoint string Which tabby endpoint to use
---@field token string? Authorization token to send to Tabby
---@field device Device Device to use for model inference
---@field model string | ApiModel Model to use for completion.
---@field temperature number Temperature parameter for model, tune variance - basically model's "creativity". ranges from 0.0 to 1.0
---@field max_lines integer How many lines of buffer context to pass to Tabby
---@field max_num_results integer How many results to return
---@field priority integer
---@field run_on_every_keystroke boolean Generate new completion items on every keystroke.
---@field ignored_file_types string[] Which file types to ignore.
---@field context_disable_patterns string[] Which workspace to disable context provider on

local conf_defaults = {
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
    context_disable_patterns = {},
}

---@param params Config?
function M:setup(params)
    if params == nil then
        vim.api.nvim_err_writeln(
            'Bad call to cmp_tabby.config.setup; Make sure to use setup:(params) -- note the use of a colon (:)'
        )
        params = self or {}
    end
    for k, v in pairs(params or {}) do
        conf_defaults[k] = v
    end
end

function M:get(what)
    return conf_defaults[what]
end

return M
