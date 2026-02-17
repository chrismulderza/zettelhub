#!/usr/bin/env ruby
# frozen_string_literal: true

require 'date'
require 'pathname'
require 'fileutils'
require 'erb'
require 'ostruct'
require_relative '../config'
require_relative '../indexer'
require_relative '../models/note'
require_relative '../utils'
require_relative '../debug'
require_relative '../git_service'

# Import command: bulk import markdown notes with new IDs, link resolution, and optional dry run.
class ImportCommand
  include Debug

  # Handles --completion and --help; bulk imports markdown with new IDs and link resolution.
  def run(*args)
    return output_completion(args) if args.first == '--completion'
    return output_help if args.first == '--help' || args.first == '-h'

    config = Config.load_with_notebook(debug: debug?)
    notebook_path = File.expand_path(config['notebook_path'])
    debug_print("notebook_path: #{notebook_path}")

    dry_run, target_dir, recursive, path_args = parse_args(args)
    debug_print("Parsed: dry_run=#{dry_run}, target_dir=#{target_dir.inspect}, recursive=#{recursive}, path_args=#{path_args.inspect}")

    source_paths = collect_source_paths(path_args, recursive)
    debug_print("Source discovery: #{source_paths.size} path(s)#{source_paths.size <= 5 ? ": #{source_paths.inspect}" : " (first 5: #{source_paths.first(5).inspect})"}")

    if source_paths.empty?
      $stderr.puts 'No markdown files to import. Specify paths or use --recursive with a directory.'
      exit 1
    end

    target_dir = resolve_target_dir(config, target_dir)
    target_dir = target_dir.to_s.strip.empty? ? '.' : target_dir
    slug_replacement = Config.get_engine_slugify_replacement(config)
    debug_print("target_dir: #{target_dir}, slug_replacement: #{slug_replacement.inspect}")

    # Pass 1: parse all, assign new IDs, build maps
    parsed = []
    old_id_to_new = {}
    title_to_new = {}
    alias_to_new = {}
    source_abs_to_new_rel = {}
    source_basename_to_candidates = {}
    failures = []

    debug_print("Pass 1: parsing #{source_paths.size} source(s), building id/title/path maps")
    source_paths.each do |abs_path|
      begin
        content = File.read(abs_path)
        metadata, body = Utils.parse_front_matter(content)
      rescue StandardError => e
        failures << { path: abs_path, reason: e.message }
        debug_print("Pass 1 parse failure: #{abs_path}: #{e.message}")
        next
      end

      old_id = metadata['id']&.to_s&.strip
      title = metadata['title'].to_s.strip
      new_id = Utils.generate_id
      slug = Utils.slugify(title, replacement_char: slug_replacement)
      type = metadata['type'].to_s.strip

      template_default_tags = nil
      template_alias_pattern = nil
      template_fm_for_merge = nil
      filename = slug.empty? ? "#{new_id}.md" : "#{new_id}-#{slug}.md"
      dest_relative = Pathname.new(target_dir).join(filename).to_s

      if type && !type.empty?
        debug_print("Import type-aware: type=#{type}")
        template_config = Config.get_template(config, type, debug: debug?)
        if template_config
          debug_print("Import type-aware: template=#{template_config['template_file']}")
          template_file = Utils.find_template_file(notebook_path, template_config['template_file'], debug: debug?)
          if template_file
            debug_print("Import type-aware: template file=#{template_file}")
            template_content = File.read(template_file)
            template_fm, = Utils.parse_front_matter(template_content)
            template_fm_for_merge = template_fm.dup
            template_fm_for_merge.delete('config')
            template_default_tags = template_fm.dig('config', 'default_tags')
            template_default_tags = nil if template_default_tags && !template_default_tags.is_a?(Array)
            template_alias_pattern = template_fm.dig('config', 'default_alias')
            template_alias_pattern = Config.get_engine_default_alias(config) if template_alias_pattern.to_s.strip.empty?
            path_pattern = template_fm.dig('config', 'path')
            if path_pattern && !path_pattern.to_s.strip.empty?
              path_vars = build_path_variables(metadata, new_id, title, type, config)
              rendered_path = render_template_path(path_pattern, path_vars, config)
              if rendered_path && !rendered_path.to_s.strip.empty?
                dest_relative = Pathname.new(target_dir).join(rendered_path.strip).to_s
                debug_print("Import type-aware: path_pattern=#{path_pattern.inspect} rendered=#{rendered_path} dest_relative=#{dest_relative}")
              end
            end
          else
            debug_print("Import type-aware: template file not found for #{template_config['template_file']}")
          end
        else
          debug_print("Import type-aware: no template for type=#{type}")
        end
      end

      dest_relative = dest_relative.gsub(%r{^\./}, '') if dest_relative.start_with?('./')
      dest_abs = File.join(notebook_path, dest_relative)

      old_id_to_new[old_id] = new_id if old_id && !old_id.empty?
      title_to_new[title] = new_id if title && !title.empty?
      expanded_abs = File.expand_path(abs_path)
      source_abs_to_new_rel[expanded_abs] = dest_relative

      bn = File.basename(abs_path)
      source_basename_to_candidates[bn] ||= []
      source_basename_to_candidates[bn] << [expanded_abs, dest_relative]

      Array(metadata['aliases']).each do |a|
        alias_str = a.to_s.strip
        alias_to_new[alias_str] = new_id if alias_str != ''
      end

      debug_print("Pass 1: #{abs_path} -> old_id=#{old_id.inspect} title=#{title.inspect} new_id=#{new_id} dest_relative=#{dest_relative}")
      parsed << {
        source_path: abs_path,
        metadata: metadata,
        body: body,
        old_id: old_id,
        title: title,
        new_id: new_id,
        dest_relative: dest_relative,
        dest_abs: dest_abs,
        slug: slug,
        template_default_tags: template_default_tags,
        template_alias_pattern: template_alias_pattern,
        template_fm_for_merge: template_fm_for_merge
      }
    end
    unique_basenames = source_basename_to_candidates.count { |_, v| v.is_a?(Array) && v.size == 1 }
    duplicate_basenames = source_basename_to_candidates.count { |_, v| v.is_a?(Array) && v.size > 1 }
    debug_print("Pass 1 done: parsed=#{parsed.size}, failures=#{failures.size}, old_id_to_new=#{old_id_to_new.size}, title_to_new=#{title_to_new.size}, source_abs_to_new_rel=#{source_abs_to_new_rel.size}, basename_registry unique=#{unique_basenames} duplicate_basenames=#{duplicate_basenames}, alias_to_new=#{alias_to_new.size}")

    # Pass 2: resolve links, optionally write and index (or collect report)
    would_import = []
    indexer = Indexer.new(config) unless dry_run
    debug_print("Pass 2: dry_run=#{dry_run}, processing #{parsed.size} note(s)")

    parsed.each do |item|
      metadata = if item[:template_fm_for_merge]
                   Utils.deep_merge(item[:template_fm_for_merge], item[:metadata])
                 else
                   item[:metadata].dup
                 end
      metadata.delete('config')
      metadata['id'] = item[:new_id]
      if item[:template_default_tags].is_a?(Array) && item[:template_default_tags].any?
        metadata['tags'] = (item[:template_default_tags] + Array(metadata['tags'])).uniq
        debug_print("Import type-aware Pass 2: merged template_default_tags (#{item[:template_default_tags].size}): #{item[:template_default_tags].inspect}")
      end
      if item[:template_alias_pattern].to_s.strip != ''
        date_format = Config.get_engine_date_format(config)
        ref_date = parse_reference_date(item[:metadata])
        base_time_vars = if ref_date
                           Utils.time_vars_for_date(ref_date, date_format: date_format)
                         else
                           Utils.current_time_vars(date_format: date_format)
                         end
        alias_vars = base_time_vars
          .merge('id' => item[:new_id], 'title' => metadata['title'], 'type' => metadata['type'])
          .merge(metadata)
        metadata['aliases'] = Utils.interpolate_pattern(item[:template_alias_pattern], alias_vars)
        debug_print("Import type-aware Pass 2: set aliases from template => #{metadata['aliases'].inspect}")
      end

      body = item[:body]
      body = resolve_wikilinks(body, old_id_to_new, title_to_new, alias_to_new)
      body = Utils.resolve_markdown_links_with_mapping(body, item[:source_path], source_abs_to_new_rel, source_basename_to_candidates, debug: debug?)

      if dry_run
        changes = collect_changes(item, old_id_to_new, title_to_new, alias_to_new, source_abs_to_new_rel, source_basename_to_candidates)
        would_import << {
          source_path: item[:source_path],
          new_id: item[:new_id],
          dest_path: item[:dest_abs],
          changes: changes
        }
        debug_print("Pass 2 (dry): #{item[:source_path]} -> #{item[:dest_abs]} id=#{item[:new_id]} changes=#{changes.size}")
      else
        content = Utils.reconstruct_note_content(metadata, body)
        FileUtils.mkdir_p(File.dirname(item[:dest_abs]))
        debug_print("Pass 2: Writing #{item[:dest_abs]}")
        File.write(item[:dest_abs], content)
        note = Note.new(path: item[:dest_abs])
        debug_print("Pass 2: Indexing #{item[:dest_abs]} (id=#{item[:new_id]})")
        indexer.index_note(note)
        puts "Imported: #{item[:dest_relative]}"
      end
    end
    debug_print(dry_run ? "Dry run done: would_import=#{would_import.size}, failures=#{failures.size}" : "Imported #{parsed.size} note(s)")

    if dry_run
      print_dry_run_report(would_import, failures)
    else
      puts "Imported #{parsed.size} note(s)." if parsed.size > 1
      if failures.any?
        $stderr.puts "Skipped #{failures.size} file(s) due to errors."
        failures.each { |f| $stderr.puts "  #{f[:path]}: #{f[:reason]}" }
      end

      # Auto-commit imported notes
      auto_commit_import(config, parsed.size) if parsed.any?
    end
  end

  private

  def parse_args(args)
    dry_run = false
    target_dir = nil
    recursive = false
    path_args = []

    i = 0
    while i < args.length
      case args[i]
      when '--dry-run'
        dry_run = true
      when '--into', '--target-dir'
        target_dir = args[i + 1]
        i += 1
      when '--recursive', '-r'
        recursive = true
      else
        path_args << args[i] if args[i] && !args[i].to_s.strip.empty?
      end
      i += 1
    end

    [dry_run, target_dir, recursive, path_args]
  end

  def resolve_target_dir(config, flag_value)
    if flag_value && !flag_value.to_s.strip.empty?
      debug_print("Target dir: from flag (#{flag_value.inspect})")
      return flag_value.to_s.strip
    end
    from_config = Config.get_import_default_target_dir(config).to_s.strip
    debug_print("Target dir: from config (#{from_config.inspect})")
    from_config
  end

  def parse_reference_date(metadata)
    raw = metadata['date']
    return nil if raw.nil? || raw.to_s.strip.empty?
    return raw if raw.is_a?(Date) || raw.is_a?(Time)
    Date.parse(raw.to_s)
  rescue ArgumentError
    nil
  end

  def build_path_variables(metadata, new_id, title, type, config)
    date_format = Config.get_engine_date_format(config)
    ref_date = parse_reference_date(metadata)
    base_vars = if ref_date
                  Utils.time_vars_for_date(ref_date, date_format: date_format)
                else
                  Utils.current_time_vars(date_format: date_format)
                end
    base_vars.merge('id' => new_id, 'title' => title, 'type' => type).merge(metadata)
  end

  def render_template_path(path_pattern, variables, config)
    context = OpenStruct.new(variables)
    replacement_char = Config.get_engine_slugify_replacement(config)
    context.define_singleton_method(:slugify) { |text| Utils.slugify(text, replacement_char: replacement_char) }
    result = ERB.new(path_pattern.to_s).result(context.instance_eval { binding })
    result.to_s.strip.sub(%r{^\./}, '')
  end

  def collect_source_paths(path_args, recursive)
    expanded = path_args.flat_map do |arg|
      path = File.expand_path(arg)
      unless File.exist?(path)
        next []
      end
      if File.file?(path)
        path.end_with?('.md') ? [path] : []
      elsif File.directory?(path)
        if recursive
          Dir.glob(File.join(path, '**', '*.md')).sort
        else
          Dir.glob(File.join(path, '*.md')).sort
        end
      else
        []
      end
    end
    expanded.uniq.sort
  end

  def resolve_wikilinks(body, old_id_to_new, title_to_new, alias_to_new = {})
    body.gsub(Utils::WIKILINK_PATTERN) do
      inner = Regexp.last_match(1).to_s.strip
      new_id, match_type = resolve_wikilink_inner(inner, old_id_to_new, title_to_new, alias_to_new)
      if new_id
        debug_print("resolved wikilink [[#{inner}]] -> [[#{new_id}]] (#{match_type})")
        "[[#{new_id}]]"
      else
        debug_print("wikilink [[#{inner}]] not resolved (no id/title/alias match)")
        "[[#{inner}]]"
      end
    end
  end

  def resolve_wikilink_inner(inner, old_id_to_new, title_to_new, alias_to_new)
    new_id = old_id_to_new[inner]
    return [new_id, :id] if new_id
    new_id = title_to_new[inner]
    return [new_id, :title] if new_id
    new_id = alias_to_new[inner]
    return [new_id, :alias] if new_id
    key = title_to_new.keys.find { |k| k.to_s.casecmp(inner.to_s) == 0 }
    return [title_to_new[key], :title_case_insensitive] if key
    [nil, nil]
  end

  def collect_changes(item, old_id_to_new, title_to_new, alias_to_new, source_abs_to_new_rel, source_basename_to_candidates)
    body = item[:body]
    changes = []
    current_dir = File.dirname(File.expand_path(item[:source_path]))
    changes << "id: #{item[:old_id]} -> #{item[:new_id]}" if item[:old_id] && !item[:old_id].empty?
    body.scan(Utils::WIKILINK_PATTERN) do
      inner = Regexp.last_match(1).to_s.strip
      new_id, = resolve_wikilink_inner(inner, old_id_to_new, title_to_new, alias_to_new)
      changes << "wikilink [[#{inner}]] -> [[#{new_id}]]" if new_id
    end
    body.scan(Utils::MARKDOWN_LINK_PATTERN) do
      url = Regexp.last_match(2).to_s.strip
      next if url.empty? || url.start_with?('#') || (url.include?(':') && url =~ /\A[a-z][a-z0-9+.-]*:/i)
      new_rel, = Utils.resolve_link_target_to_new_path(url, current_dir, source_abs_to_new_rel, source_basename_to_candidates)
      changes << "link (#{url}) -> (#{new_rel})" if new_rel
    end
    changes.uniq
  end

  def print_dry_run_report(would_import, failures)
    puts "Would import (#{would_import.size}):"
    would_import.each do |item|
      puts "  #{item[:source_path]}"
      puts "    -> #{item[:dest_path]} (id: #{item[:new_id]})"
      item[:changes].each { |c| puts "    change: #{c}" } if item[:changes].any?
    end
    if failures.any?
      puts "Would fail (#{failures.size}):"
      failures.each { |f| puts "  #{f[:path]}: #{f[:reason]}" }
    end
  end

  # Auto-commits imported notes if git auto_commit is enabled.
  def auto_commit_import(config, count)
    return unless Config.get_git_auto_commit(config)

    notebook_path = config['notebook_path']
    git = GitService.new(notebook_path)
    return unless git.repo?

    message = "Import #{count} note(s)"
    result = git.commit(message: message, all: true)

    if result[:success]
      debug_print("Auto-committed: #{message}")

      if Config.get_git_auto_push(config)
        remote = Config.get_git_remote(config)
        branch = Config.get_git_branch(config)
        push_result = git.push(remote: remote, branch: branch)
        debug_print("Auto-pushed to #{remote}/#{branch}") if push_result[:success]
      end
    else
      debug_print("Auto-commit failed: #{result[:message]}")
    end
  end

  # Prints completion candidates for shell completion.
  # Returns __DIR__ for options that take directory paths, __FILE__ for file paths.
  def output_completion(args)
    prev = args[1]
    case prev
    when '--into', '--target-dir'
      puts '__DIR__'
    else
      puts '--into --target-dir --recursive --dry-run --help -h'
    end
  end

  # Prints command-specific usage and options to stdout.
  def output_help
    puts <<~HELP
      Import markdown notes into the notebook

      USAGE:
          zh import [OPTIONS] PATH [PATH ...]

      DESCRIPTION:
          Bulk import markdown files: assigns new IDs, updates front matter,
          resolves wikilinks ([[id]]/[[title]]) and Markdown links to notes in the
          same batch, and indexes imported notes. Use --dry-run to preview.

      OPTIONS:
          --into, --target-dir DIR   Directory under notebook_path for imported files (default: config import.default_target_dir or ".")
          --recursive, -r            Recursively include .md files under given directories
          --dry-run                  Show what would be imported and what would fail; no files written
          --help, -h                 Show this help message
          --completion              Output shell completion candidates

      EXAMPLES:
          zh import /path/to/notes/*.md
          zh import --recursive /path/to/notes
          zh import --into imported ./external/*.md
          zh import --dry-run --into imported /path/to/notes
    HELP
  end
end

ImportCommand.new.run(*ARGV) if __FILE__ == $PROGRAM_NAME
