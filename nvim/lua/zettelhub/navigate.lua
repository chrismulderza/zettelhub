-- ============================================================================
-- ZettelHub navigation module
-- ============================================================================
-- Provides wikilink and markdown link navigation (gf), create-on-missing,
-- and jump history.
--
-- Features:
--   - follow_link(): Navigate to wikilink or markdown link under cursor
--   - create_or_follow(): Navigate or offer to create if missing
--   - jump_back(): Return to previous note (uses jumplist)
--
-- Supported link formats:
--   - Wikilinks: [[id]], [[id|title]], [[@name]]
--   - Markdown links: [text](path.md), [text](../relative/path.md)
-- ============================================================================

local M = {}

-- Get the notebook root path from zh config
-- Returns: notebook path string or nil
function M.get_notebook_path()
  local zettelhub = require('zettelhub')
  local cmd = string.format('%s resolve --notebook-path 2>/dev/null', zettelhub.config.zh_command)
  local handle = io.popen(cmd)
  if not handle then
    -- Fallback: try to find .zh directory by walking up
    local current = vim.fn.expand('%:p:h')
    while current and current ~= '/' do
      if vim.fn.isdirectory(current .. '/.zh') == 1 then
        return current
      end
      current = vim.fn.fnamemodify(current, ':h')
    end
    return nil
  end

  local result = handle:read('*a')
  handle:close()
  result = vim.trim(result)

  -- If zh resolve --notebook-path fails, fall back to directory walk
  if result == '' then
    local current = vim.fn.expand('%:p:h')
    while current and current ~= '/' do
      if vim.fn.isdirectory(current .. '/.zh') == 1 then
        return current
      end
      current = vim.fn.fnamemodify(current, ':h')
    end
    return nil
  end

  return result
end

-- Extract wikilink ID from text at cursor position
-- Supports: [[id]], [[id|title]], [[@name]]
-- Returns: { type = 'wikilink', id = string, display = string, is_alias = boolean } or nil
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
        type = 'wikilink',
        id = vim.trim(id or ''),
        display = vim.trim(display or ''),
        is_alias = is_alias,
        raw = content,
      }
    end
  end

  return nil
end

-- Extract markdown link from text at cursor position
-- Supports: [text](path.md), [text](../relative/path.md), [text](/root/path.md)
-- Skips external links (http, https, mailto, ftp, file)
-- Returns: { type = 'markdown', url = string, display = string } or nil
function M.extract_markdown_link_at_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1 -- 1-indexed

  -- Find all markdown links in the line: [text](url)
  -- We need to track positions carefully
  local search_start = 1
  while true do
    -- Find next [ character
    local bracket_start = line:find('%[', search_start)
    if not bracket_start then
      break
    end

    -- Find matching ] and (
    local bracket_end = line:find('%]%(', bracket_start)
    if not bracket_end then
      search_start = bracket_start + 1
      goto continue
    end

    -- Find closing )
    local paren_start = bracket_end + 2
    local paren_end = line:find('%)', paren_start)
    if not paren_end then
      search_start = bracket_start + 1
      goto continue
    end

    -- Check if cursor is within this link
    local link_end = paren_end
    if col >= bracket_start and col <= link_end then
      local display = line:sub(bracket_start + 1, bracket_end - 1)
      local url = line:sub(paren_start, paren_end - 1)

      -- Skip external links
      if url:match('^https?://') or url:match('^mailto:') or
         url:match('^ftp://') or url:match('^file://') then
        return nil
      end

      -- Skip anchor-only links
      if url:sub(1, 1) == '#' then
        return nil
      end

      return {
        type = 'markdown',
        url = url,
        display = display,
      }
    end

    search_start = bracket_start + 1
    ::continue::
  end

  return nil
end

-- Extract any link (wikilink or markdown) at cursor position
-- Tries wikilink first, then markdown link
-- Returns: link table with type field, or nil
function M.extract_link_at_cursor()
  -- Try wikilink first (more specific syntax)
  local wikilink = M.extract_wikilink_at_cursor()
  if wikilink then
    return wikilink
  end

  -- Fall back to markdown link
  return M.extract_markdown_link_at_cursor()
end

-- Resolve a markdown link URL to an absolute file path
-- Handles relative paths (../path.md) and root-relative paths (/path.md)
-- Returns: absolute path string or nil
function M.resolve_markdown_path(url)
  if not url or url == '' then
    return nil
  end

  local resolved_path

  if url:sub(1, 1) == '/' then
    -- Root-relative path (relative to notebook root)
    local notebook_path = M.get_notebook_path()
    if not notebook_path then
      return nil
    end
    resolved_path = notebook_path .. url
  else
    -- File-relative path (relative to current buffer's directory)
    local current_dir = vim.fn.expand('%:p:h')
    if current_dir == '' then
      return nil
    end
    resolved_path = current_dir .. '/' .. url
  end

  -- Normalize the path (resolve .. and .)
  resolved_path = vim.fn.fnamemodify(resolved_path, ':p')

  -- Check if file exists
  if vim.fn.filereadable(resolved_path) == 1 then
    return resolved_path
  end

  -- Try adding .md extension if not present
  if not url:match('%.md$') then
    local with_md = resolved_path .. '.md'
    if vim.fn.filereadable(with_md) == 1 then
      return with_md
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

-- Navigate to the link under cursor (wikilink or markdown link)
-- If the link doesn't exist, returns false
-- Returns: true if navigation succeeded, false otherwise
function M.follow_link()
  local link = M.extract_link_at_cursor()
  if not link then
    vim.notify('No link under cursor', vim.log.levels.WARN)
    return false
  end

  local path

  if link.type == 'wikilink' then
    -- Resolve wikilink via zh resolve
    path = M.resolve_link(link.id)
    if not path then
      vim.notify(string.format('Note not found: %s', link.display), vim.log.levels.WARN)
      return false
    end
  elseif link.type == 'markdown' then
    -- Resolve markdown link path
    path = M.resolve_markdown_path(link.url)
    if not path then
      vim.notify(string.format('File not found: %s', link.url), vim.log.levels.WARN)
      return false
    end
  else
    vim.notify('Unknown link type', vim.log.levels.ERROR)
    return false
  end

  if vim.fn.filereadable(path) ~= 1 then
    vim.notify(string.format('File not found: %s', path), vim.log.levels.WARN)
    return false
  end

  -- Add current position to jumplist before navigating
  vim.cmd("normal! m'")
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  return true
end

-- Navigate to link (wikilink or markdown), or offer to create if missing
-- For wikilinks: prompts with options to create note
-- For markdown links: prompts to create file at specified path
function M.create_or_follow()
  local link = M.extract_link_at_cursor()
  if not link then
    vim.notify('No link under cursor', vim.log.levels.WARN)
    return
  end

  local path
  local title

  if link.type == 'wikilink' then
    path = M.resolve_link(link.id)
    title = link.display ~= '' and link.display or link.id
  elseif link.type == 'markdown' then
    path = M.resolve_markdown_path(link.url)
    title = link.display ~= '' and link.display or vim.fn.fnamemodify(link.url, ':t:r')
  else
    vim.notify('Unknown link type', vim.log.levels.ERROR)
    return
  end

  if path and vim.fn.filereadable(path) == 1 then
    -- File exists, navigate to it
    vim.cmd("normal! m'")
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
    return
  end

  -- For markdown links pointing to a specific path, offer to create at that path
  if link.type == 'markdown' then
    M.create_markdown_target(link, title)
    return
  end

  -- For wikilinks, offer to create via zh add
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

-- Create a file at the path specified by a markdown link
-- Prompts user for confirmation before creating
function M.create_markdown_target(link, title)
  local url = link.url
  local target_path

  if url:sub(1, 1) == '/' then
    -- Root-relative path
    local notebook_path = M.get_notebook_path()
    if not notebook_path then
      vim.notify('Cannot determine notebook path', vim.log.levels.ERROR)
      return
    end
    target_path = notebook_path .. url
  else
    -- File-relative path
    local current_dir = vim.fn.expand('%:p:h')
    target_path = current_dir .. '/' .. url
  end

  -- Normalize path
  target_path = vim.fn.fnamemodify(target_path, ':p')

  -- Add .md if not present
  if not target_path:match('%.md$') then
    target_path = target_path .. '.md'
  end

  vim.ui.select(
    { 'Yes', 'No' },
    {
      prompt = string.format("Create file '%s'?", vim.fn.fnamemodify(target_path, ':~:.')),
    },
    function(choice)
      if choice ~= 'Yes' then
        return
      end

      -- Ensure parent directory exists
      local parent_dir = vim.fn.fnamemodify(target_path, ':h')
      if vim.fn.isdirectory(parent_dir) ~= 1 then
        vim.fn.mkdir(parent_dir, 'p')
      end

      -- Create basic markdown file with title
      local content = string.format('# %s\n\n', title)
      local file = io.open(target_path, 'w')
      if file then
        file:write(content)
        file:close()
        vim.cmd('edit ' .. vim.fn.fnameescape(target_path))
        vim.notify(string.format('Created: %s', target_path), vim.log.levels.INFO)
      else
        vim.notify(string.format('Failed to create: %s', target_path), vim.log.levels.ERROR)
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
