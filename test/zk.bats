#!/usr/bin/env bats

# ============================================================================
# Help System Tests
# ============================================================================

@test "zh --help shows help and exits 0" {
  run ./bin/zh --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"ZettelHub"* ]]
  [[ "$output" == *"USAGE"* ]]
  [[ "$output" == *"COMMANDS"* ]]
  [[ "$output" == *"add"* ]]
  [[ "$output" == *"init"* ]]
  [[ "$output" == *"completion"* ]]
}

@test "zh -h shows help and exits 0" {
  run ./bin/zh -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"ZettelHub"* ]]
  [[ "$output" == *"USAGE"* ]]
  [[ "$output" == *"COMMANDS"* ]]
}

@test "zh without args shows help and exits 0" {
  run ./bin/zh
  [ "$status" -eq 0 ]
  [[ "$output" == *"ZettelHub"* ]]
  [[ "$output" == *"USAGE"* ]]
  [[ "$output" == *"COMMANDS"* ]]
}

@test "zh add --help shows help and exits 0" {
  run ./bin/zh add --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Create a new note"* ]]
  [[ "$output" == *"USAGE"* ]]
  [[ "$output" == *"zh add"* ]]
}

@test "zh add -h shows help and exits 0" {
  run ./bin/zh add -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Create a new note"* ]]
  [[ "$output" == *"USAGE"* ]]
}

@test "zh init --help shows help and exits 0" {
  run ./bin/zh init --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Initialize a new notebook"* ]]
  [[ "$output" == *"USAGE"* ]]
  [[ "$output" == *"zh init"* ]]
}

@test "zh init -h shows help and exits 0" {
  run ./bin/zh init -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Initialize a new notebook"* ]]
  [[ "$output" == *"USAGE"* ]]
}

@test "zh find --help shows help and exits 0" {
  run ./bin/zh find --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Interactive find"* ]]
  [[ "$output" == *"ripgrep"* ]]
}

@test "zh find -h shows help and exits 0" {
  run ./bin/zh find -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Interactive find"* ]]
  [[ "$output" == *"ripgrep"* ]]
}

# ============================================================================
# Completion Command Tests
# ============================================================================

@test "zh completion generates bash completion script" {
  run ./bin/zh completion
  [ "$status" -eq 0 ]
  [[ "$output" == *"# ZettelHub bash completion"* ]]
  [[ "$output" == *"_zh()"* ]]
  [[ "$output" == *"complete -F _zh zh"* ]]
}

@test "zh _completion is alias for completion" {
  run ./bin/zh _completion
  [ "$status" -eq 0 ]
  [[ "$output" == *"# ZettelHub bash completion"* ]]
  [[ "$output" == *"_zh()"* ]]
  [[ "$output" == *"complete -F _zh zh"* ]]
}

@test "zh completion with args registers those names only" {
  run ./bin/zh completion zk
  [ "$status" -eq 0 ]
  [[ "$output" == *"complete -F _zh zk"* ]]
  run ./bin/zh completion foo bar
  [ "$status" -eq 0 ]
  [[ "$output" == *"complete -F _zh foo"* ]]
  [[ "$output" == *"complete -F _zh bar"* ]]
}

# ============================================================================
# Command Execution Tests
# ============================================================================

@test "zh init" {
  mkdir -p test_init_dir
  cd test_init_dir
  run ../bin/zh init
  [ "$status" -eq 0 ]
  [[ "$output" == *"Initialized"* ]]
  [ -d .zh ]
  [ -f .zh/config.yaml ]
  cd ..
  rm -rf test_init_dir
}

@test "zh add" {
  rm -rf test_add_dir
  mkdir -p test_add_dir
  cd test_add_dir
  ../bin/zh init
  rm .zh/config.yaml
  export HOME="$PWD/home"
  mkdir -p "$HOME/.config/zh/templates"
  cat > "$HOME/.config/zh/templates/note.erb" << 'EOF'
---
id: "<%= id %>"
type: note
date: "<%= date %>"
title: "<%= title %>"
aliases: "<%= aliases %>"
tags: <%= tags %>
config:
  path: "<%= id %>-<%= slugify(title) %>.md"
---
# <%= type %>
Content
EOF
   cat > "$HOME/.config/zh/config.yaml" << 'EOF'
notebook_path: "."
EOF
  export EDITOR=true
  run ../bin/zh add --title "Test Note" --tags "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Note created"* ]]
  [ -f *.md ]
  cd ..
  rm -rf test_add_dir
}

# ============================================================================
# Error Handling Tests
# ============================================================================

@test "zh unknown command shows error and exits 1" {
  run ./bin/zh unknown
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: zh <command> [options]"* ]]
  [[ "$output" == *"Commands: add, init, reindex, tag, tags, search, find, import, links, backlinks, graph, bookmark, git, history, diff, restore, today, yesterday, tomorrow, journal, completion"* ]]
  [[ "$output" == *"Run 'zh --help' for more information."* ]]
}
