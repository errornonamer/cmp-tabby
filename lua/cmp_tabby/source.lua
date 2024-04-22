local cmp = require('cmp')
local api = vim.api
local fn = vim.fn
local conf = require('cmp_tabby.config')

local function dump(...)
    local objects = vim.tbl_map(vim.inspect, { ... })
    print(unpack(objects))
end

local function json_decode(data)
    local status, result = pcall(vim.fn.json_decode, data)
    if status then
        return result
    else
        return nil, result
    end
end

local function is_win()
    return package.config:sub(1, 1) == '\\'
end

local function get_path_separator()
    if is_win() then
        return '\\'
    end
    return '/'
end

local function script_path()
    local str = debug.getinfo(2, 'S').source:sub(2)
    if is_win() then
        str = str:gsub('/', '\\')
    end
    return str:match('(.*' .. get_path_separator() .. ')')
end

local function get_parent_dir(path)
    local separator = get_path_separator()
    local pattern = '^(.+)' .. separator
    -- if path has separator at end, remove it
    path = path:gsub(separator .. '*$', '')
    local parent_dir = path:match(pattern) .. separator
    return parent_dir
end

-- do this once on init, otherwise on restart this dows not work
local binary = get_parent_dir(get_parent_dir(script_path())) .. 'tabby/target/release/tabby'

local function server_ran_locally()
    return conf:get('endpoint') == 'http://localhost'
end

local port = 0

local function get_endpoint()
    if server_ran_locally() then
        return conf:get('endpoint') .. ':' .. port
    end
    return conf:get('endpoint')
end

---@class CompletionServer
---@field job integer
local CompletionServer = {
    job = 0,
}
---@class CompletionClient
---@field job integer
---@field ctx cmp.SourceCompletionApiParams?
---@field callback fun(completion_item: lsp.CompletionResponse|nil)?
local CompletionClient = {
    ctx = nil,
    callback = nil,
}
---@class Source
---@field server_job CompletionServer?
---@field completion_job CompletionClient?
local Source = {
    server_job = nil,
    completion_job = nil,
}
local last_server_instance = nil
local last_instance = nil

function CompletionServer.new()
    last_server_instance = setmetatable({}, { __index = CompletionServer })
    last_server_instance:on_exit(0)
    return last_server_instance
end

function CompletionServer.on_exit(self, job, code)
    if job ~= self.job then
        return
    end
    -- restart..
    if code == 143 then
        -- nvim is exiting. do not restart
        return
    end

    -- if it works it ain't stupid
    port = math.random(49152, 65535)
    self.job = fn.jobstart({
        binary,
        'serve',
        '--port',
        port,
        '--model',
        conf:get('model'),
        '--device',
        conf:get('device'),
    }, {
        on_exit = function(j, c, _)
            self:on_exit(j, c)
        end,
    })
end

function CompletionClient.new(ctx, callback)
    local instance = setmetatable({
        ctx = ctx,
        callback = callback,
    }, {
        __index = CompletionClient,
    })
    instance:do_complete()
    return instance
end

function CompletionClient.do_complete(self)
    local max_lines = conf:get('max_lines')
    local cursor = self.ctx.context.cursor
    local cur_line = self.ctx.context.cursor_line
    -- properly handle utf8
    local cur_line_before = vim.fn.strpart(cur_line, 0, math.max(cursor.col - 1, 0), true)

    -- properly handle utf8
    local cur_line_after = vim.fn.strpart(cur_line, math.max(cursor.col - 1, 0), vim.fn.strdisplaywidth(cur_line), true) -- include current character

    local lines_before = api.nvim_buf_get_lines(0, math.max(0, cursor.line - max_lines), cursor.line, false)
    table.insert(lines_before, cur_line_before)
    local before = table.concat(lines_before, '\n')

    local lines_after = api.nvim_buf_get_lines(0, cursor.line + 1, cursor.line + max_lines, false)
    table.insert(lines_after, 1, cur_line_after)
    local after = table.concat(lines_after, '\n')

    ---@alias LanguageType 'rust' | 'python' | 'javascript' | 'typescript' | 'go' | 'ruby' | 'java' | 'kotlin' | 'c' | 'cpp' | 'php' | 'csharp' | 'unknown'
    --
    ---@class Segment
    ---@field prefix string
    ---@field suffix string?
    ---@field clipboard string?
    ---@class CompletionRequest
    ---@field language LanguageType?
    ---@field segments Segment
    ---@field user string
    ---@field temperature number?
    local req = {
        language = vim.filetype.match({ buf = 0 }) or 'unknown',
        segments = {
            prefix = before,
            suffix = after,
        },
        temperature = conf:get('temperature'),
    }
	local auth = {}
	local token = conf:get('token')
	if token ~= nil then
		auth = { '-H', 'Authorization: Bearer ' .. token }
	end
    self.job = fn.jobstart({
        'curl',
        '-s',
        '-H',
        'Content-type: application/json',
        '-H',
        'Accept: application/json',
        '-X',
        'POST',
        '-d',
        vim.json.encode(req),
        get_endpoint() .. '/v1/completions',
		unpack(auth)
    }, {
        on_stdout = function(_, data, _)
            self:on_stdout(data)
        end,
    })
end

function CompletionClient.on_stdout(self, data)
    -- {
    --  "id": "cmpl-1b60f3da-f7d4-4e09-9192-833b123a3f49",
    --  "choices": [
    --    {
    --      "index": 0,
    --      "text": "    if n <= 1:\n            return n"
    --    }
    --  ]
    --}

    ---@class CompletionChoice
    ---@field index integer
    ---@field text string

    ---@class CompletionResponse
    ---@field id string
    ---@field choices CompletionChoice[]

    for _, jd in ipairs(data) do
        if jd ~= nil and jd ~= '' and jd ~= 'null' then
            ---@type CompletionResponse?
            local response, debug = json_decode(jd)

            if response == nil then
                dump('Tabby: json decode error: ', response, debug)
            else
                local cursor = self.ctx.context.cursor

                local items = {}
                local results = response.choices

                if results ~= nil then
                    for _, result in ipairs(results) do
                        local newText = result.text

                        if newText:find('.*\n.*') then
                            -- this is a multi line completion.
                            -- remove leading newlines
                            newText = newText:gsub('^\n', '')
                        end

                        local old_prefix = self.ctx.context.cursor_before_line

                        local range = {
                            start = { line = cursor.line, character = cursor.col - #old_prefix - 1 },
                            ['end'] = { line = cursor.line, character = cursor.col + #old_prefix - 1 },
                        }

                        local item = {
                            label = old_prefix .. newText,
                            data = {
                                id = response.id,
                                choice = result.index,
                            },
                            textEdit = {
                                newText = old_prefix .. newText,
                                insert = range,
                                replace = range,
                            },
                            dup = 0,
                            sortText = newText,
                            cmp = {
                                kind_text = 'Tabby',
                                kind_hl_group = 'CmpItemKindTabby',
                            },
                        }

                        if result.text:find('.*\n.*') then
                            item['data']['multiline'] = true
                            item['documentation'] = {
                                kind = cmp.lsp.MarkupKind.Markdown,
                                value = '```'
                                    .. (vim.filetype.match({ buf = 0 }) or '')
                                    .. '\n'
                                    .. old_prefix
                                    .. newText
                                    .. '\n```',
                            }
                        end

                        table.insert(items, item)
                        self.view(response.id, result.index)
                    end
                else
                    dump('no results:', jd)
                end

                items = { unpack(items, 1, conf:get('max_num_results')) }
                ---@type lsp.CompletionList
                local result = {
                    items = items,
                    isIncomplete = conf:get('run_on_every_keystroke'),
                }
                self.callback(result)
            end
        end
    end
end

function CompletionClient.view(id, idx)
    ---@class TabbyEvent
    ---@field type 'view' | 'select' | 'dismiss'
    ---@field completion_id string
    ---@field choice_index integer
    local req = {
        type = 'view',
        completion_id = id,
        choice_index = idx,
    }
    fn.jobstart({
        'curl',
        '-s',
        '-H',
        'Content-type: application/json',
        '-H',
        'Accept: application/json',
        '-X',
        'POST',
        '-d',
        vim.json.encode(req),
        get_endpoint() .. '/v1/events',
    })
end

function Source.new()
    last_instance = setmetatable({}, { __index = Source })
    if server_ran_locally() then
        last_instance.server_job = CompletionServer.new()
    end
    return last_instance
end

function Source.is_available(self)
    return (self.server_job ~= nil and self.server_job.job ~= 0) or (server_ran_locally() == false)
end

function Source.get_debug_name()
    return 'Tabby'
end

--- complete
function Source.complete(self, ctx, callback)
    if conf:get('ignored_file_types')[vim.bo.filetype] then
        callback()
        return
    end
    if self.completion_job ~= nil and self.completion_job.job ~= 0 then
        fn.jobstop(self.completion_job.job)
    end
    self.completion_job = CompletionClient.new(ctx, callback)
end

function Source:execute(item, callback)
    local req = {
        type = 'select',
        completion_id = item.data.id,
        choice_index = item.data.choice,
    }
    fn.jobstart({
        'curl',
        '-s',
        '-H',
        'Content-type: application/json',
        '-H',
        'Accept: application/json',
        '-X',
        'POST',
        '-d',
        vim.json.encode(req),
        get_endpoint() .. '/v1/events',
    })
    callback(item)
end

return Source
