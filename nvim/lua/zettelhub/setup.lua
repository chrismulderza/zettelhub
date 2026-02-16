-- ============================================================================
-- ZettelHub setup module
-- ============================================================================
-- Configures nvim-cmp source, keymaps, and user commands for ZettelHub.
--
-- This module is called by require('zettelhub').setup(opts) and handles:
--   - Registering the custom cmp completion source
--   - Setting up filetype-specific cmp configuration for markdown
--   - Creating keymaps for navigation, preview, and Telescope pickers
--   - Defining user commands (:ZkBrowse, :ZkLink, :ZkBacklinks, etc.)
-- ============================================================================

local M = {}

function M.setup(opts)
  opts = opts or {}

  -- Merge user options with defaults
  local zettelhub = require('zettelhub')
  zettelhub.config = vim.tbl_deep_extend('force', zettelhub.config, opts)

  -- --------------------------------------------------------------------------
  -- nvim-cmp Integration
  -- --------------------------------------------------------------------------
  local has_cmp, cmp = pcall(require, 'cmp')
  if has_cmp then
    -- Register the ZettelHub completion source
    local cmp_source = require('zettelhub.cmp')
    cmp.register_source('zettelhub', cmp_source.new())

    -- Configure completion sources for markdown files
    -- ZettelHub has highest priority to ensure [[, [[@, and # completions
    -- appear before LSP suggestions (like from marksman)
    cmp.setup.filetype('markdown', {
      sources = cmp.config.sources({
        { name = 'zettelhub', priority = 1000, group_index = 1 },
        { name = 'nvim_lsp', priority = 750, group_index = 1 },
        { name = 'luasnip', priority = 500, group_index = 1 },
      }, {
        { name = 'buffer', priority = 250, group_index = 2 },
        { name = 'path', priority = 100, group_index = 2 },
      }),
    })
  end

  -- --------------------------------------------------------------------------
  -- Navigation Keymaps (Markdown files only)
  -- --------------------------------------------------------------------------
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'markdown',
    callback = function(args)
      local buf_opts = { buffer = args.buf }
      local navigate = require('zettelhub.navigate')
      local preview = require('zettelhub.preview')

      -- gf: Follow wikilink under cursor (override default gf)
      vim.keymap.set('n', 'gf', navigate.follow_link,
        vim.tbl_extend('force', buf_opts, { desc = 'ZettelHub: Follow wikilink' }))

      -- gF: Follow or create if missing
      vim.keymap.set('n', 'gF', navigate.create_or_follow,
        vim.tbl_extend('force', buf_opts, { desc = 'ZettelHub: Follow or create note' }))

      -- K: Hover preview of wikilink (override default K)
      vim.keymap.set('n', 'K', preview.hover,
        vim.tbl_extend('force', buf_opts, { desc = 'ZettelHub: Preview wikilink' }))
    end,
  })

  -- --------------------------------------------------------------------------
  -- Telescope Keymaps
  -- --------------------------------------------------------------------------
  local has_telescope, telescope = pcall(require, 'zettelhub.telescope')
  if has_telescope then
    -- Global keymaps (normal mode) - work in any buffer
    -- Browse and insert pickers
    vim.keymap.set('n', '<leader>zf', telescope.browse,
      { desc = 'ZettelHub: Browse notes' })
    vim.keymap.set('n', '<leader>zl', telescope.insert_wikilink,
      { desc = 'ZettelHub: Insert wikilink' })
    vim.keymap.set('n', '<leader>zp', telescope.insert_person,
      { desc = 'ZettelHub: Insert @person' })
    vim.keymap.set('n', '<leader>zo', telescope.insert_organization,
      { desc = 'ZettelHub: Insert org' })
    vim.keymap.set('n', '<leader>zt', telescope.insert_tag,
      { desc = 'ZettelHub: Insert tag' })

    -- Link navigation pickers
    vim.keymap.set('n', '<leader>zb', telescope.backlinks,
      { desc = 'ZettelHub: Backlinks (notes linking here)' })
    vim.keymap.set('n', '<leader>zL', telescope.forward_links,
      { desc = 'ZettelHub: Forward links (this note links to)' })

    -- Markdown-specific keymaps (insert mode)
    -- These only apply when editing markdown files
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'markdown',
      callback = function(args)
        local buf_opts = { buffer = args.buf }
        vim.keymap.set('i', '<C-l>', telescope.insert_wikilink,
          vim.tbl_extend('force', buf_opts, { desc = 'Insert wikilink' }))
        vim.keymap.set('i', '<C-k>', telescope.insert_person,
          vim.tbl_extend('force', buf_opts, { desc = 'Insert @person' }))
        vim.keymap.set('i', '<C-t>', telescope.insert_tag,
          vim.tbl_extend('force', buf_opts, { desc = 'Insert tag' }))
      end,
    })
  end

  -- --------------------------------------------------------------------------
  -- User Commands
  -- --------------------------------------------------------------------------
  -- These commands can be invoked from command mode in any buffer

  -- Browse and insert commands
  vim.api.nvim_create_user_command('ZkBrowse', function()
    require('zettelhub.telescope').browse()
  end, { desc = 'ZettelHub: Browse notes' })

  vim.api.nvim_create_user_command('ZkLink', function()
    require('zettelhub.telescope').insert_wikilink()
  end, { desc = 'ZettelHub: Insert wikilink' })

  vim.api.nvim_create_user_command('ZkPerson', function()
    require('zettelhub.telescope').insert_person()
  end, { desc = 'ZettelHub: Insert @person' })

  vim.api.nvim_create_user_command('ZkOrg', function()
    require('zettelhub.telescope').insert_organization()
  end, { desc = 'ZettelHub: Insert organization' })

  vim.api.nvim_create_user_command('ZkTag', function()
    require('zettelhub.telescope').insert_tag()
  end, { desc = 'ZettelHub: Insert tag' })

  -- Link navigation commands
  vim.api.nvim_create_user_command('ZkBacklinks', function()
    require('zettelhub.telescope').backlinks()
  end, { desc = 'ZettelHub: Show backlinks' })

  vim.api.nvim_create_user_command('ZkForwardLinks', function()
    require('zettelhub.telescope').forward_links()
  end, { desc = 'ZettelHub: Show forward links' })

  -- Navigation commands
  vim.api.nvim_create_user_command('ZkFollow', function()
    require('zettelhub.navigate').follow_link()
  end, { desc = 'ZettelHub: Follow wikilink under cursor' })

  vim.api.nvim_create_user_command('ZkFollowOrCreate', function()
    require('zettelhub.navigate').create_or_follow()
  end, { desc = 'ZettelHub: Follow or create note' })

  -- Preview commands
  vim.api.nvim_create_user_command('ZkPreview', function()
    require('zettelhub.preview').hover()
  end, { desc = 'ZettelHub: Preview wikilink under cursor' })
end

return M
