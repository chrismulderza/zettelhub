-- ============================================================================
-- ZettelHub wikilink conceal module
-- ============================================================================
-- Uses Neovim's decoration provider to conceal wikilink syntax, showing only
-- the display text when the cursor is not on the line.
--
-- Supported formats:
--   [[id|Title]]  -> Title
--   [[id]]        -> 🔗id (or just id with link icon)
--   [[@Name]]     -> @Name
--
-- Requires:
--   vim.opt.conceallevel = 2  (or 1 to show replacement char)
--   vim.opt.concealcursor = '' (show full syntax on cursor line)
-- ============================================================================

local M = {}

-- Namespace for extmarks
local ns = vim.api.nvim_create_namespace('zettelhub_conceal')

-- Configuration (set via setup)
M.config = {
  enabled = false,
  -- Icon shown for [[id]] links without display text
  link_icon = '🔗',
  -- Highlight group for the visible link text
  link_hl = 'markdownLinkText',
}

-- Check if position is inside a fenced code block
-- Simple heuristic: count ``` above the line
local function in_code_block(bufnr, lnum)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, lnum, false)
  local fence_count = 0
  for _, line in ipairs(lines) do
    if line:match('^%s*```') then
      fence_count = fence_count + 1
    end
  end
  return fence_count % 2 == 1
end

-- Apply conceal extmarks to wikilinks in visible range
local function apply_conceal(bufnr, topline, botline)
  -- Clear existing marks in range
  vim.api.nvim_buf_clear_namespace(bufnr, ns, topline, botline)

  local lines = vim.api.nvim_buf_get_lines(bufnr, topline, botline, false)

  for i, line in ipairs(lines) do
    local lnum = topline + i - 1

    -- Skip if inside code block
    if in_code_block(bufnr, lnum) then
      goto continue
    end

    local pos = 1
    while pos <= #line do
      -- Pattern 1: [[id|title]] - standard wikilink with display text
      local s1, e1, id, title = line:find('%[%[([a-f0-9A-F]+)|([^%]]+)%]%]', pos)

      -- Pattern 2: [[@Name]] - person alias
      local s2, e2, name = line:find('%[%[@([^%]]+)%]%]', pos)

      -- Pattern 3: [[id]] - wikilink without display text
      local s3, e3, id_only = line:find('%[%[([a-f0-9A-F]+)%]%]', pos)

      -- Find the earliest match
      local matches = {}
      if s1 then table.insert(matches, { s = s1, e = e1, type = 'titled', id = id, title = title }) end
      if s2 then table.insert(matches, { s = s2, e = e2, type = 'alias', name = name }) end
      if s3 then table.insert(matches, { s = s3, e = e3, type = 'id_only', id = id_only }) end

      if #matches == 0 then
        break
      end

      -- Sort by start position
      table.sort(matches, function(a, b) return a.s < b.s end)
      local match = matches[1]

      if match.type == 'titled' then
        -- [[id|title]] -> conceal [[id| and ]]
        local prefix_len = 2 + #match.id + 1 -- [[id|

        -- Conceal [[id|
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, match.s - 1, {
          end_col = match.s - 1 + prefix_len,
          conceal = '',
          hl_mode = 'combine',
        })

        -- Highlight the title
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, match.s - 1 + prefix_len, {
          end_col = match.e - 2,
          hl_group = M.config.link_hl,
        })

        -- Conceal ]]
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, match.e - 2, {
          end_col = match.e,
          conceal = '',
        })

      elseif match.type == 'alias' then
        -- [[@Name]] -> @Name (conceal [[ and ]])

        -- Conceal [[
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, match.s - 1, {
          end_col = match.s + 1,
          conceal = '',
        })

        -- Highlight @Name
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, match.s + 1, {
          end_col = match.e - 2,
          hl_group = M.config.link_hl,
        })

        -- Conceal ]]
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, match.e - 2, {
          end_col = match.e,
          conceal = '',
        })

      elseif match.type == 'id_only' then
        -- [[id]] -> show with link icon

        -- Conceal [[ and replace with icon
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, match.s - 1, {
          end_col = match.s + 1,
          conceal = M.config.link_icon,
        })

        -- Highlight the id
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, match.s + 1, {
          end_col = match.e - 2,
          hl_group = M.config.link_hl,
        })

        -- Conceal ]]
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, match.e - 2, {
          end_col = match.e,
          conceal = '',
        })
      end

      pos = match.e + 1
    end

    ::continue::
  end
end

-- Setup the decoration provider
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend('force', M.config, opts)

  if not M.config.enabled then
    return
  end

  -- Set recommended conceal options if not already set
  -- Users can override these in their config
  if vim.opt.conceallevel:get() == 0 then
    vim.opt_local.conceallevel = 2
  end

  -- Register decoration provider
  vim.api.nvim_set_decoration_provider(ns, {
    on_win = function(_, winid, bufnr, topline, botline)
      -- Only process markdown files
      if vim.bo[bufnr].filetype ~= 'markdown' then
        return false
      end

      -- Apply concealment
      apply_conceal(bufnr, topline, botline)

      return false -- Don't invalidate
    end,
  })

  -- Set up FileType autocmd to configure conceallevel for markdown
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'markdown',
    group = vim.api.nvim_create_augroup('ZettelHubConceal', { clear = true }),
    callback = function()
      vim.opt_local.conceallevel = 2
      vim.opt_local.concealcursor = '' -- Show full link on cursor line
    end,
  })
end

-- Manual refresh (useful after bulk changes)
function M.refresh()
  local bufnr = vim.api.nvim_get_current_buf()
  local topline = vim.fn.line('w0') - 1
  local botline = vim.fn.line('w$')
  apply_conceal(bufnr, topline, botline)
end

-- Disable concealment
function M.disable()
  vim.api.nvim_set_decoration_provider(ns, {})
  -- Clear all extmarks
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    end
  end
end

-- Toggle concealment
function M.toggle()
  M.config.enabled = not M.config.enabled
  if M.config.enabled then
    M.setup(M.config)
  else
    M.disable()
  end
  vim.notify('Wikilink conceal: ' .. (M.config.enabled and 'enabled' or 'disabled'))
end

return M
