local curl = require("llm.curl")
local util = require("llm.util")

local M = {}

function M.authenticate()
  M.api_key = util.env("OPENAI_API_KEY")
end

function M.request(endpoint, body, opts)
  local defaults = {
    headers = {
      Authorization = "Bearer " .. M.api_key,
      ["Content-Type"] = "application/json"
    },
    compressed = false,
    body = vim.json.encode(body),
    raw = "-N"
  }

  local options = vim.tbl_deep_extend("force", defaults, opts)

  return curl.post(endpoint, options)
end

-- lua function that splits text into multiple strings delimited by a pattern

function M.extract_data(event_string)
  local success, data = pcall(util.json.decode, event_string:gsub('^data: ', ''))

  if success then
    if (data or {}).choices ~= nil then
      return {
        content = (data.choices[1].delta or {}).content,
        finish_reason = data.choices[1].finish_reason
      }
    end
  end
end

---@param prompt string
---@param handlers StreamHandlers
---@return nil
function M.request_completion_stream(prompt, handlers, _params)
  local params = _params or {}

  local all_content = ""

  local function handle_raw(raw_data)
    local items = util.string.split_pattern(raw_data, "\n\ndata: ")

    for _, item in ipairs(items) do
      local data = M.extract_data(item)

      if data ~= nil then
        if data.content ~= nil then
          all_content = all_content .. data.content
          handlers.on_partial(data.content)
        end

        if data.finish_reason ~= nil then
          handlers.on_finish(all_content, data.finish_reason)
        end
      else
        local response = util.json.decode(item)

        if response ~= nil then
          handlers.on_error(response, 'response')
        else
          if not item:match("^%[DONE%]") then
            handlers.on_error(item, 'item')
          end
        end
      end
    end
  end

  local function handle_error()
    handlers.on_error(error, 'response')
  end

  return curl.stream({
    headers = {
      Authorization = 'Bearer ' .. util.env('OPENAI_API_KEY'),
      ['Content-Type']= 'application/json',
    },
    method = 'POST',
    url = 'https://api.openai.com/v1/chat/completions',
    body = vim.tbl_deep_extend("force", {
      stream = true,
      model = "gpt-3.5-turbo",
      messages = {
        { content = prompt,
          role = "user"
        }
      }
    }, params)
  }, handle_raw, handle_error)
end

return M
