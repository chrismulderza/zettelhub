-- ============================================================================
-- ZettelHub nvim-cmp completion source
-- ============================================================================
-- Provides completion for:
--   - [[wikilinks]] - triggered by typing [[
--   - [[@person]] mentions - triggered by typing [[@
--   - #tags - triggered by typing #
--
-- The source registers with nvim-cmp and provides async completion results
-- by querying the ZettelHub CLI.
-- ============================================================================

local source = {}

-- Create new source instance
source.new = function()
  return setmetatable({}, { __index = source })
end

-- Define trigger characters that activate completion
-- Note: We use '[' to catch '[[' sequences
source.get_trigger_characters = function()
  return { '[', '@', '#' }
end

-- Only available in markdown files
source.is_available = function()
  return vim.bo.filetype == 'markdown'
end

-- Main completion function - called by nvim-cmp when triggered
source.complete = function(self, params, callback)
  local zettelhub = require('zettelhub')
  local line = params.context.cursor_before_line
  local cursor_col = params.context.cursor.col

  -- Detect completion context (wikilink, person, or hashtag)
  local ctx = zettelhub.get_completion_context(line, cursor_col)

  if not ctx then
    callback({ items = {}, isIncomplete = false })
    return
  end

  -- Handle hashtag completion
  if ctx.type == 'hashtag' then
    zettelhub.get_tags_async(ctx.query, function(tags)
      local cmp = require('cmp')
      local items = {}
      for _, tag in ipairs(tags) do
        table.insert(items, {
          label = '#' .. tag.name,
          insertText = tag.name,  -- Just the tag name (# is already typed)
          kind = cmp.lsp.CompletionItemKind.Keyword,
          detail = string.format('%d notes', tag.count),
          sortText = string.format('%05d', 99999 - tag.count),  -- Sort by count desc
        })
      end
      callback({ items = items, isIncomplete = false })
    end)
    return
  end

  -- Handle note completion (wikilink or @person)
  local search_opts = { limit = 30 }
  if ctx.type == 'person_alias' then
    search_opts.type = 'person'
  end

  zettelhub.search_async(ctx.query, search_opts, function(notes)
    local cmp = require('cmp')
    local items = {}

    for _, note in ipairs(notes) do
      local insert_text, label, filter_text

      if ctx.type == 'person_alias' then
        -- [[@Name]] completion
        local name = note.full_name or note.title or note.id
        insert_text = name .. ']]'  -- Complete the [[@Name]]
        label = '@' .. name
        filter_text = name
      else
        -- [[id|title]] completion
        local wikilink_content = note.id .. '|' .. (note.title or '')
        insert_text = wikilink_content .. ']]'  -- Complete the [[id|title]]
        label = note.title or note.id
        filter_text = (note.title or '') .. ' ' .. note.id
      end

      table.insert(items, {
        label = label,
        insertText = insert_text,
        filterText = filter_text,
        kind = cmp.lsp.CompletionItemKind.Reference,
        detail = note.type or 'note',
        documentation = note.description or nil,
      })
    end

    callback({ items = items, isIncomplete = #notes >= 30 })
  end)
end

return source
