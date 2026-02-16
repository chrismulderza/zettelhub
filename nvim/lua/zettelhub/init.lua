-- ZettelHub Neovim integration
-- Core module providing search, completion context, and utilities

local M = {}

-- Default configuration
M.config = {
  zh_command = 'zh',
  search_limit = 30,
  person_alias_prefix = '@',
  tag_prefix = '#',
  tag_completion_in_body = true,
}

-- Parse JSON from zh search output
function M.parse_search_results(json_str)
  if not json_str or json_str == '' then
    return {}
  end
  local ok, results = pcall(vim.json.decode, json_str)
  if not ok then
    return {}
  end
  return results or {}
end

-- Synchronous search using io.popen
function M.search(query, opts)
  opts = opts or {}
  local args = { 'search', '--format', 'json', '--limit', tostring(opts.limit or M.config.search_limit) }
  if opts.type then
    table.insert(args, '--type')
    table.insert(args, opts.type)
  end
  if query and query ~= '' then
    table.insert(args, query)
  end
  local cmd = M.config.zh_command .. ' ' .. table.concat(args, ' ') .. ' 2>/dev/null'
  local handle = io.popen(cmd)
  if not handle then
    return {}
  end
  local result = handle:read('*a')
  handle:close()
  return M.parse_search_results(result)
end

-- Asynchronous search using plenary.job (if available)
function M.search_async(query, opts, callback)
  opts = opts or {}
  local ok, Job = pcall(require, 'plenary.job')
  if not ok then
    -- Fallback to sync if plenary not available
    vim.schedule(function()
      callback(M.search(query, opts))
    end)
    return
  end

  local args = { 'search', '--format', 'json', '--limit', tostring(opts.limit or M.config.search_limit) }
  if opts.type then
    table.insert(args, '--type')
    table.insert(args, opts.type)
  end
  if query and query ~= '' then
    table.insert(args, query)
  end

  Job:new({
    command = M.config.zh_command,
    args = args,
    on_exit = function(job, return_val)
      vim.schedule(function()
        if return_val ~= 0 then
          callback({})
          return
        end
        local result = table.concat(job:result(), '\n')
        callback(M.parse_search_results(result))
      end)
    end,
  }):start()
end

-- Fetch all tags (synchronous)
function M.get_tags(query)
  local cmd = M.config.zh_command .. ' tags 2>/dev/null'
  local handle = io.popen(cmd)
  if not handle then
    return {}
  end
  local result = handle:read('*a')
  handle:close()

  local tags = {}
  for line in result:gmatch('[^\n]+') do
    -- Parse format: "  45  tagname [source]"
    local count, tag = line:match('^%s*(%d+)%s+([^%[]+)')
    if tag then
      tag = vim.trim(tag)
      if not query or query == '' or tag:lower():find(query:lower(), 1, true) then
        table.insert(tags, { name = tag, count = tonumber(count) or 0 })
      end
    end
  end

  table.sort(tags, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    return a.name < b.name
  end)

  return tags
end

-- Async version of get_tags
function M.get_tags_async(query, callback)
  local ok, Job = pcall(require, 'plenary.job')
  if not ok then
    vim.schedule(function()
      callback(M.get_tags(query))
    end)
    return
  end

  Job:new({
    command = M.config.zh_command,
    args = { 'tags' },
    on_exit = function(job, return_val)
      vim.schedule(function()
        if return_val ~= 0 then
          callback({})
          return
        end
        local result = table.concat(job:result(), '\n')
        local tags = {}
        for line in result:gmatch('[^\n]+') do
          local count, tag = line:match('^%s*(%d+)%s+([^%[]+)')
          if tag then
            tag = vim.trim(tag)
            if not query or query == '' or tag:lower():find(query:lower(), 1, true) then
              table.insert(tags, { name = tag, count = tonumber(count) or 0 })
            end
          end
        end
        table.sort(tags, function(a, b)
          if a.count ~= b.count then
            return a.count > b.count
          end
          return a.name < b.name
        end)
        callback(tags)
      end)
    end,
  }):start()
end

-- Get completion context from cursor position
-- Returns: { type = 'wikilink'|'person_alias'|'hashtag', query = string, start_col = number } or nil
function M.get_completion_context(line, col)
  local before_cursor = line:sub(1, col)

  -- [[@... (person alias)
  local at_match = before_cursor:match('%[%[@([^%]]*)$')
  if at_match then
    return { type = 'person_alias', query = at_match, start_col = col - #at_match }
  end

  -- [[... (wikilink)
  local wikilink_match = before_cursor:match('%[%[([^%]]*)$')
  if wikilink_match then
    return { type = 'wikilink', query = wikilink_match, start_col = col - #wikilink_match }
  end

  -- #tag in body
  if M.config.tag_completion_in_body then
    local hashtag_match = before_cursor:match('#([%w%-_]*)$')
    if hashtag_match then
      return { type = 'hashtag', query = hashtag_match, start_col = col - #hashtag_match }
    end
  end

  return nil
end

-- Format a note as wikilink
function M.format_wikilink(note, opts)
  opts = opts or {}
  if opts.use_at_alias and note.type == 'person' then
    local name = note.full_name or note.title or note.id
    return string.format('%s%s', M.config.person_alias_prefix, name)
  end
  return string.format('%s|%s', note.id, note.title or '')
end

-- Setup function (delegates to setup module)
function M.setup(opts)
  require('zettelhub.setup').setup(opts)
end

return M
