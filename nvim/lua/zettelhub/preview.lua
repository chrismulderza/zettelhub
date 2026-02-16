-- ============================================================================
-- ZettelHub preview module
-- ============================================================================
-- Provides hover preview for wikilinks in a floating window.
--
-- Features:
--   - hover(): Show floating preview of wikilink under cursor
--   - close(): Close the preview window
--   - Window is scrollable and can be closed with q or Escape
-- ============================================================================

local M = {}

-- Store state for the preview window
M.preview_win = nil
M.preview_buf = nil

-- Get preview content for a note ID using zh show
-- Returns: string content or nil
function M.get_preview_content(id, max_lines)
  if not id or id == '' then
    return nil
  end

  max_lines = max_lines or 20
  local zettelhub = require('zettelhub')
  local cmd = string.format(
    '%s show %s --lines %d 2>/dev/null',
    zettelhub.config.zh_command,
    vim.fn.shellescape(id),
    max_lines
  )

  local handle = io.popen(cmd)
  if not handle then
    return nil
  end

  local result = handle:read('*a')
  local success = handle:close()

  if not success or result == '' then
    return nil
  end

  return result
end

-- Close the preview window if it exists
function M.close()
  if M.preview_win and vim.api.nvim_win_is_valid(M.preview_win) then
    vim.api.nvim_win_close(M.preview_win, true)
  end
  M.preview_win = nil
  M.preview_buf = nil
end

-- Show hover preview for wikilink under cursor
function M.hover()
  -- Close any existing preview
  M.close()

  -- Get the wikilink under cursor
  local navigate = require('zettelhub.navigate')
  local link = navigate.extract_wikilink_at_cursor()

  if not link then
    vim.notify('No wikilink under cursor', vim.log.levels.WARN)
    return
  end

  -- Get preview content
  local content = M.get_preview_content(link.id, 25)
  if not content then
    vim.notify(string.format('Could not load preview for: %s', link.display), vim.log.levels.WARN)
    return
  end

  -- Create buffer for preview
  M.preview_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(M.preview_buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(M.preview_buf, 'filetype', 'markdown')

  -- Set content
  local lines = vim.split(content, '\n')
  vim.api.nvim_buf_set_lines(M.preview_buf, 0, -1, false, lines)

  -- Calculate window size
  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(#lines, 20, vim.o.lines - 4)

  -- Get cursor position for window placement
  local cursor = vim.api.nvim_win_get_cursor(0)
  local win_row = cursor[1]
  local screen_row = vim.fn.screenpos(0, win_row, 1).row

  -- Position window below cursor if there's room, otherwise above
  local row_offset
  if screen_row + height + 2 < vim.o.lines then
    row_offset = 1
  else
    row_offset = -height - 1
  end

  -- Create floating window
  M.preview_win = vim.api.nvim_open_win(M.preview_buf, false, {
    relative = 'cursor',
    row = row_offset,
    col = 0,
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. (link.display or link.id) .. ' ',
    title_pos = 'center',
  })

  -- Set window options
  vim.api.nvim_win_set_option(M.preview_win, 'wrap', true)
  vim.api.nvim_win_set_option(M.preview_win, 'linebreak', true)
  vim.api.nvim_win_set_option(M.preview_win, 'cursorline', false)

  -- Set buffer keymaps for the preview window
  local buf_opts = { buffer = M.preview_buf, nowait = true }

  -- Close with q or Escape
  vim.keymap.set('n', 'q', M.close, buf_opts)
  vim.keymap.set('n', '<Esc>', M.close, buf_opts)

  -- Enter to navigate to the note
  vim.keymap.set('n', '<CR>', function()
    M.close()
    navigate.follow_link()
  end, buf_opts)

  -- Focus the preview window so user can scroll
  vim.api.nvim_set_current_win(M.preview_win)

  -- Add footer hint
  vim.api.nvim_buf_set_lines(M.preview_buf, -1, -1, false, { '', '─────────────────────────────────', '[q] close  [Enter] open  [j/k] scroll' })
end

-- Show preview without focusing (for quick peek)
function M.peek()
  -- Close any existing preview
  M.close()

  -- Get the wikilink under cursor
  local navigate = require('zettelhub.navigate')
  local link = navigate.extract_wikilink_at_cursor()

  if not link then
    return
  end

  -- Get preview content
  local content = M.get_preview_content(link.id, 15)
  if not content then
    return
  end

  -- Create buffer for preview
  M.preview_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(M.preview_buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(M.preview_buf, 'filetype', 'markdown')

  -- Set content
  local lines = vim.split(content, '\n')
  vim.api.nvim_buf_set_lines(M.preview_buf, 0, -1, false, lines)

  -- Calculate window size
  local width = math.min(60, vim.o.columns - 4)
  local height = math.min(#lines, 12, vim.o.lines - 4)

  -- Create floating window (don't focus)
  M.preview_win = vim.api.nvim_open_win(M.preview_buf, false, {
    relative = 'cursor',
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
    focusable = false,
  })

  -- Auto-close when cursor moves
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'BufLeave' }, {
    callback = function()
      M.close()
    end,
    once = true,
  })
end

return M
