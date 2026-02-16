-- ============================================================================
-- ZettelHub navigation module
-- ============================================================================
-- Provides wikilink navigation (gf), create-on-missing, and jump history.
--
-- Features:
--   - follow_link(): Navigate to wikilink under cursor
--   - create_or_follow(): Navigate or offer to create if missing
--   - jump_back(): Return to previous note (uses jumplist)
-- ============================================================================

local M = {}

-- Extract wikilink ID from text at cursor position
-- Supports: [[id]], [[id|title]], [[@name]]
-- Returns: { id = string, display = string, is_alias = boolean } or nil
function M.extract_wikilink_at_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1 -- 1-indexed

  -- Find all wikilinks in the line
  -- Pattern matches [[...]] including nested content
  for start_pos, content, end_pos in line:gmatch('()%[%[(.-)%]%]()') do
    if col >= start_pos and col < end_pos then
      -- Cursor is within this wikilink
      local is_alias = content:sub(1, 1) == '@'
      local id, display

      if is_alias then
        -- [[@Name]] format - this is an alias, search by it
        display = content:sub(2) -- Remove @
        id = display -- Will be resolved by zh resolve
      elseif content:find('|') then
        -- [[id|title]] format
        id, display = content:match('^([^|]+)|(.*)$')
      else
        -- [[id]] format
        id = content
        display = content
      end

      return {
        id = vim.trim(id or ''),
        display = vim.trim(display or ''),
        is_alias = is_alias,
        raw = content,
      }
    end
  end

  return nil
end

-- Resolve a wikilink ID to an absolute file path using zh resolve
-- Returns: path string or nil
function M.resolve_link(id)
  if not id or id == '' then
    return nil
  end

  local zettelhub = require('zettelhub')
  local cmd = string.format('%s resolve %s 2>/dev/null', zettelhub.config.zh_command, vim.fn.shellescape(id))
  local handle = io.popen(cmd)
  if not handle then
    return nil
  end

  local result = handle:read('*a')
  local success = handle:close()

  if not success then
    return nil
  end

  result = vim.trim(result)
  if result == '' then
    return nil
  end

  return result
end

-- Navigate to the wikilink under cursor
-- If the link doesn't exist, returns false
-- Returns: true if navigation succeeded, false otherwise
function M.follow_link()
  local link = M.extract_wikilink_at_cursor()
  if not link then
    vim.notify('No wikilink under cursor', vim.log.levels.WARN)
    return false
  end

  local path = M.resolve_link(link.id)
  if not path then
    vim.notify(string.format('Note not found: %s', link.display), vim.log.levels.WARN)
    return false
  end

  if not vim.fn.filereadable(path) then
    vim.notify(string.format('File not found: %s', path), vim.log.levels.WARN)
    return false
  end

  -- Add current position to jumplist before navigating
  vim.cmd("normal! m'")
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  return true
end

-- Navigate to wikilink, or offer to create if missing
-- Prompts user with options: [y]es create, [t]ype select, [n]o
function M.create_or_follow()
  local link = M.extract_wikilink_at_cursor()
  if not link then
    vim.notify('No wikilink under cursor', vim.log.levels.WARN)
    return
  end

  local path = M.resolve_link(link.id)
  if path and vim.fn.filereadable(path) == 1 then
    -- Note exists, navigate to it
    vim.cmd("normal! m'")
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
    return
  end

  -- Note doesn't exist, offer to create
  local title = link.display ~= '' and link.display or link.id
  vim.ui.select(
    { 'Yes (note)', 'Choose type...', 'No' },
    {
      prompt = string.format("Note '%s' not found. Create it?", title),
    },
    function(choice)
      if not choice then
        return
      end

      if choice == 'No' then
        return
      end

      local zettelhub = require('zettelhub')

      if choice == 'Yes (note)' then
        -- Create with default note type
        local cmd = string.format(
          '%s add note --title %s',
          zettelhub.config.zh_command,
          vim.fn.shellescape(title)
        )
        local output = vim.fn.system(cmd)
        if vim.v.shell_error == 0 then
          -- Extract path from output and open
          local new_path = output:match('Created: ([^\n]+)')
          if new_path then
            vim.cmd('edit ' .. vim.fn.fnameescape(vim.trim(new_path)))
          else
            vim.notify('Note created, run zh find to locate it', vim.log.levels.INFO)
          end
        else
          vim.notify('Failed to create note: ' .. output, vim.log.levels.ERROR)
        end
      elseif choice == 'Choose type...' then
        -- Let user pick the type
        M.create_with_type_picker(title)
      end
    end
  )
end

-- Show type picker and create note with selected type
function M.create_with_type_picker(title)
  local types = { 'note', 'person', 'organization', 'meeting', 'bookmark' }

  vim.ui.select(types, {
    prompt = 'Select note type:',
  }, function(note_type)
    if not note_type then
      return
    end

    local zettelhub = require('zettelhub')
    local cmd = string.format(
      '%s add %s --title %s',
      zettelhub.config.zh_command,
      note_type,
      vim.fn.shellescape(title)
    )
    local output = vim.fn.system(cmd)
    if vim.v.shell_error == 0 then
      local new_path = output:match('Created: ([^\n]+)')
      if new_path then
        vim.cmd('edit ' .. vim.fn.fnameescape(vim.trim(new_path)))
      else
        vim.notify('Note created, run zh find to locate it', vim.log.levels.INFO)
      end
    else
      vim.notify('Failed to create note: ' .. output, vim.log.levels.ERROR)
    end
  end)
end

-- Jump back to previous location (uses Vim's jumplist)
function M.jump_back()
  vim.cmd('normal! <C-o>')
end

return M
