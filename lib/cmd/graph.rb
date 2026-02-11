#!/usr/bin/env ruby
# frozen_string_literal: true

require 'sqlite3'
require_relative '../config'
require_relative '../utils'
require_relative '../debug'

# Graph command: output link graph (DOT format or ASCII) for a note and its neighbourhood.
class GraphCommand
  include Debug

  # Handles --completion and --help; outputs link graph (DOT or ASCII) for note and neighbourhood.
  def run(*args)
    return output_completion(args) if args.first == '--completion'
    return output_help if args.first == '--help' || args.first == '-h'

    format_arg = 'dot'
    fmt_idx = args.index('--format') || args.index('-f')
    format_arg = args[fmt_idx + 1].to_s.downcase if fmt_idx && args[fmt_idx + 1]
    skip_after_format = fmt_idx && args[fmt_idx + 1] ? [args[fmt_idx + 1]] : []
    note_arg = args.find { |a| !a.to_s.start_with?('-') && !skip_after_format.include?(a) }

    if note_arg.to_s.strip.empty?
      $stderr.puts 'Usage: zh graph NOTE_ID [--format dot|ascii]'
      $stderr.puts 'NOTE_ID can be note id (8-char hex), title, or alias.'
      exit 1
    end

    config = Config.load_with_notebook(debug: debug?)
    db_path = Config.index_db_path(config['notebook_path'])
    unless File.exist?(db_path)
      $stderr.puts 'No index found. Run zh reindex first.'
      exit 1
    end

    db = SQLite3::Database.new(db_path)
    note_id = Utils.resolve_wikilink_to_id(note_arg.to_s.strip, db)
    db.close

    unless note_id
      $stderr.puts "Note not found: #{note_arg}"
      exit 1
    end

    db = SQLite3::Database.new(db_path)
    all_links = db.execute('SELECT source_id, target_id FROM links')
    db.close

    # Build edges from/to note_id (outgoing and incoming)
    nodes = [note_id].to_set
    all_links.each do |src, tgt|
      if src == note_id || tgt == note_id
        nodes << src << tgt
      end
    end

    case format_arg.to_s.downcase
    when 'ascii'
      output_ascii(note_id, all_links, nodes)
    else
      output_dot(note_id, all_links, nodes)
    end
  end

  private

  def output_dot(center_id, all_links, nodes)
    edges = all_links.select { |src, tgt| nodes.include?(src) && nodes.include?(tgt) }
    puts 'digraph links {'
    nodes.each { |n| puts "  \"#{n}\";" }
    edges.each { |src, tgt| puts "  \"#{src}\" -> \"#{tgt}\";" }
    puts "  \"#{center_id}\" [style=bold];"
    puts '}'
  end

  def output_ascii(center_id, all_links, nodes)
    edges = all_links.select { |src, tgt| nodes.include?(src) && nodes.include?(tgt) }
    puts "Link graph for #{center_id}:"
    puts ''
    edges.each { |src, tgt| puts "  #{src} -> #{tgt}" }
    puts '' if edges.any?
  end

  # Prints completion candidates for shell completion.
  def output_completion(args)
    if args.include?('--format') || args.include?('-f')
      puts 'dot ascii'
    else
      puts ''
    end
  end

  # Prints command-specific usage and options to stdout.
  def output_help
    puts <<~HELP
      Show link graph for a note

      USAGE:
          zh graph NOTE_ID [--format FORMAT]

      DESCRIPTION:
          Outputs the link graph (notes and links) for the given note and its
          immediate neighbourhood. NOTE_ID can be the note's 8-character id,
          title, or alias.

      FORMATS:
          dot (default)  Graphviz DOT format; pipe to 'dot -Tpng -o out.png' to render
          ascii          Plain list of edges (source -> target)

      OPTIONS:
          --format, -f FORMAT   Output format: dot or ascii (default: dot)
          --help, -h            Show this help message
          --completion          Output shell completion candidates

      EXAMPLES:
          zh graph abc12345
          zh graph abc12345 --format ascii
          zh graph abc12345 | dot -Tpng -o graph.png
    HELP
  end
end

GraphCommand.new.run(*ARGV) if __FILE__ == $PROGRAM_NAME
