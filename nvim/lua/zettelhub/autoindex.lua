-- ============================================================================
-- ZettelHub auto-index module
-- ============================================================================
-- Automatically reindexes notes when saved, but only for files within the
-- configured notebook directory.
--
-- Features:
--   - Triggers on BufWritePost for markdown files
--   - Checks if file is within notebook path before indexing
--   - Runs indexing asynchronously to avoid blocking the editor
--   - Configurable: can be disabled via setup options
-- ============================================================================

local M = {}

-- Check if a file path is within the notebook directory
-- @param filepath: Absolute path to check
-- @param notebook_path: Absolute notebook root path
-- @return: true if filepath is inside notebook_path
function M.is_in_notebook(filepath, notebook_path)
  if not filepath or not notebook_path then
    return false
  end
  -- Normalize paths (ensure trailing slash for comparison)
  local norm_notebook = notebook_path:gsub('/$', '') .. '/'
  local norm_file = filepath:gsub('/$', '')
  return norm_file:sub(1, #norm_notebook) == norm_notebook
end

-- Index a single note asynchronously
-- @param filepath: Absolute path to the note file
function M.index_note_async(filepath)
  local zettelhub = require('zettelhub')

  -- Try plenary.job for async execution
  local ok, Job = pcall(require, 'plenary.job')
  if ok then
    Job:new({
      command = zettelhub.config.zh_command,
      args = { 'reindex', '--file', filepath },
      on_exit = function(_, return_val)
        if return_val == 0 and zettelhub.config.autoindex_notify then
          vim.schedule(function()
            vim.notify('Indexed: ' .. vim.fn.fnamemodify(filepath, ':t'), vim.log.levels.INFO)
          end)
        end
      end,
    }):start()
  else
    -- Fallback: use vim.fn.jobstart for async execution without plenary
    vim.fn.jobstart({
      zettelhub.config.zh_command, 'reindex', '--file', filepath,
    }, { detach = true })
  end
end

-- Handler for BufWritePost autocommand
-- Checks if file is in notebook and triggers indexing
function M.on_buf_write()
  local zettelhub = require('zettelhub')

  -- Skip if autoindex is disabled
  if not zettelhub.config.autoindex then
    return
  end

  local filepath = vim.fn.expand('%:p')

  -- Skip non-markdown files
  if not filepath:match('%.md$') then
    return
  end

  -- Get notebook path
  local navigate = require('zettelhub.navigate')
  local notebook_path = navigate.get_notebook_path()

  if not notebook_path then
    return
  end

  -- Only index if file is within notebook
  if M.is_in_notebook(filepath, notebook_path) then
    M.index_note_async(filepath)
  end
end

-- Setup autocommand for auto-indexing
function M.setup()
  vim.api.nvim_create_autocmd('BufWritePost', {
    pattern = '*.md',
    group = vim.api.nvim_create_augroup('ZettelHubAutoIndex', { clear = true }),
    callback = M.on_buf_write,
    desc = 'ZettelHub: Auto-index note on save',
  })
end

return M
