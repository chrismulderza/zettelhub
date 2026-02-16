-- ZettelHub Telescope pickers
-- Provides browse, insert wikilink, person, organization, and tag pickers

local M = {}

-- Insert wikilink picker
function M.insert_wikilink(opts)
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local zettelhub = require('zettelhub')

  pickers.new(opts or {}, {
    prompt_title = 'Insert Wikilink',
    finder = finders.new_dynamic({
      fn = function(prompt)
        local notes = zettelhub.search(prompt, { limit = 50 })
        local entries = {}
        for _, note in ipairs(notes) do
          table.insert(entries, {
            value = note,
            display = string.format('[%s] %s', note.type or 'note', note.title or note.id),
            ordinal = (note.title or '') .. ' ' .. note.id,
          })
        end
        return entries
      end,
      entry_maker = function(entry)
        return entry
      end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          local note = selection.value
          local wikilink = string.format('[[%s|%s]]', note.id, note.title or '')
          vim.api.nvim_put({ wikilink }, '', true, true)
        end
      end)
      return true
    end,
  }):find()
end

-- Insert person (@mention) picker
function M.insert_person(opts)
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local zettelhub = require('zettelhub')

  pickers.new(opts or {}, {
    prompt_title = 'Insert Person (@mention)',
    finder = finders.new_dynamic({
      fn = function(prompt)
        local notes = zettelhub.search(prompt, { type = 'person', limit = 50 })
        local entries = {}
        for _, note in ipairs(notes) do
          table.insert(entries, {
            value = note,
            display = note.full_name or note.title or note.id,
            ordinal = (note.full_name or '') .. ' ' .. (note.title or '') .. ' ' .. note.id,
          })
        end
        return entries
      end,
      entry_maker = function(entry)
        return entry
      end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          local note = selection.value
          local name = note.full_name or note.title or note.id
          vim.api.nvim_put({ '[[@' .. name .. ']]' }, '', true, true)
        end
      end)
      return true
    end,
  }):find()
end

-- Insert tag picker
function M.insert_tag(opts)
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local zettelhub = require('zettelhub')

  pickers.new(opts or {}, {
    prompt_title = 'Insert Tag',
    finder = finders.new_dynamic({
      fn = function(prompt)
        local tags = zettelhub.get_tags(prompt)
        local entries = {}
        for _, tag in ipairs(tags) do
          table.insert(entries, {
            value = tag,
            display = string.format('#%-20s (%d)', tag.name, tag.count),
            ordinal = tag.name,
          })
        end
        return entries
      end,
      entry_maker = function(entry)
        return entry
      end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          vim.api.nvim_put({ '#' .. selection.value.name }, '', true, true)
        end
      end)
      return true
    end,
  }):find()
end

-- Browse notes picker
function M.browse(opts)
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local zettelhub = require('zettelhub')

  pickers.new(opts or {}, {
    prompt_title = 'Browse ZettelHub',
    finder = finders.new_dynamic({
      fn = function(prompt)
        local notes = zettelhub.search(prompt, { limit = 100 })
        local entries = {}
        for _, note in ipairs(notes) do
          table.insert(entries, {
            value = note,
            display = string.format('[%s] %s', note.type or 'note', note.title or note.id),
            ordinal = (note.title or '') .. ' ' .. note.id,
          })
        end
        return entries
      end,
      entry_maker = function(entry)
        return entry
      end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection and selection.value.full_path then
          vim.cmd('edit ' .. vim.fn.fnameescape(selection.value.full_path))
        end
      end)
      return true
    end,
  }):find()
end

-- Insert organization picker
function M.insert_organization(opts)
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local zettelhub = require('zettelhub')

  pickers.new(opts or {}, {
    prompt_title = 'Insert Organization',
    finder = finders.new_dynamic({
      fn = function(prompt)
        local notes = zettelhub.search(prompt, { limit = 50 })
        local entries = {}
        for _, note in ipairs(notes) do
          if note.type == 'organization' or note.type == 'account' then
            table.insert(entries, {
              value = note,
              display = string.format('[%s] %s', note.type, note.title or note.id),
              ordinal = (note.title or '') .. ' ' .. note.id,
            })
          end
        end
        return entries
      end,
      entry_maker = function(entry)
        return entry
      end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          local note = selection.value
          vim.api.nvim_put({ string.format('[[%s|%s]]', note.id, note.title or '') }, '', true, true)
        end
      end)
      return true
    end,
  }):find()
end

-- Get backlinks for the current note
-- Returns: list of { id, path, title, link_type } or empty table
function M.get_backlinks(note_id)
  local zettelhub = require('zettelhub')
  local cmd = string.format('%s backlinks %s --json 2>/dev/null', zettelhub.config.zh_command, vim.fn.shellescape(note_id))
  local handle = io.popen(cmd)
  if not handle then
    return {}
  end
  local result = handle:read('*a')
  handle:close()

  local ok, links = pcall(vim.json.decode, result)
  if not ok or not links then
    return {}
  end
  return links
end

-- Get forward links for the current note
-- Returns: list of { id, path, title, link_type } or empty table
function M.get_forward_links(note_id)
  local zettelhub = require('zettelhub')
  local cmd = string.format('%s links %s --json 2>/dev/null', zettelhub.config.zh_command, vim.fn.shellescape(note_id))
  local handle = io.popen(cmd)
  if not handle then
    return {}
  end
  local result = handle:read('*a')
  handle:close()

  local ok, links = pcall(vim.json.decode, result)
  if not ok or not links then
    return {}
  end
  return links
end

-- Get note ID from current buffer's file path
function M.get_current_note_id()
  local filepath = vim.fn.expand('%:p')
  if filepath == '' then
    return nil
  end

  -- Extract ID from filename (format: title-id.md or id-title.md)
  local filename = vim.fn.fnamemodify(filepath, ':t:r')

  -- Try pattern: anything-{8char_hex}.md
  local id = filename:match('%-([a-f0-9]+)$')
  if id and #id >= 8 then
    return id:sub(1, 8)
  end

  -- Try pattern: {8char_hex}-anything.md
  id = filename:match('^([a-f0-9]+)%-')
  if id and #id >= 8 then
    return id:sub(1, 8)
  end

  return nil
end

-- Backlinks picker - shows all notes linking TO the current note
function M.backlinks(opts)
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local previewers = require('telescope.previewers')
  local zettelhub = require('zettelhub')

  local note_id = M.get_current_note_id()
  if not note_id then
    vim.notify('Could not determine current note ID', vim.log.levels.WARN)
    return
  end

  local links = M.get_backlinks(note_id)
  if #links == 0 then
    vim.notify('No backlinks to this note', vim.log.levels.INFO)
    return
  end

  local entries = {}
  for _, link in ipairs(links) do
    if not link.broken then
      table.insert(entries, {
        value = link,
        display = string.format('[%s] %s', link.link_type or 'link', link.title or link.id),
        ordinal = (link.title or '') .. ' ' .. link.id,
        path = link.absolute_path,
      })
    end
  end

  pickers.new(opts or {}, {
    prompt_title = 'Backlinks (notes linking here)',
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return entry
      end,
    }),
    sorter = conf.generic_sorter(opts),
    previewer = previewers.new_termopen_previewer({
      get_command = function(entry)
        if entry.path then
          return { zettelhub.config.zh_command, 'show', entry.value.id }
        end
        return { 'echo', 'No preview available' }
      end,
    }),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection and selection.path then
          vim.cmd('edit ' .. vim.fn.fnameescape(selection.path))
        end
      end)
      return true
    end,
  }):find()
end

-- Forward links picker - shows all notes this note links TO
function M.forward_links(opts)
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local previewers = require('telescope.previewers')
  local zettelhub = require('zettelhub')

  local note_id = M.get_current_note_id()
  if not note_id then
    vim.notify('Could not determine current note ID', vim.log.levels.WARN)
    return
  end

  local links = M.get_forward_links(note_id)
  if #links == 0 then
    vim.notify('No outgoing links from this note', vim.log.levels.INFO)
    return
  end

  local entries = {}
  for _, link in ipairs(links) do
    local broken_marker = link.broken and ' (broken)' or ''
    table.insert(entries, {
      value = link,
      display = string.format('[%s] %s%s', link.link_type or 'link', link.title or link.id, broken_marker),
      ordinal = (link.title or '') .. ' ' .. link.id,
      path = link.absolute_path,
    })
  end

  pickers.new(opts or {}, {
    prompt_title = 'Forward Links (this note links to)',
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return entry
      end,
    }),
    sorter = conf.generic_sorter(opts),
    previewer = previewers.new_termopen_previewer({
      get_command = function(entry)
        if entry.path and not entry.value.broken then
          return { zettelhub.config.zh_command, 'show', entry.value.id }
        end
        return { 'echo', 'No preview available (broken link)' }
      end,
    }),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection and selection.path and not selection.value.broken then
          vim.cmd('edit ' .. vim.fn.fnameescape(selection.path))
        elseif selection and selection.value.broken then
          vim.notify('Cannot open broken link: ' .. selection.value.id, vim.log.levels.WARN)
        end
      end)
      return true
    end,
  }):find()
end

return M
