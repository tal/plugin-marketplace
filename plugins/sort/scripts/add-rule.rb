#!/usr/bin/env ruby
# frozen_string_literal: true

# add-rule.rb — append a rule to a sort config file
#
# Usage:
#   add-rule.rb <file> <match-yaml-inline> <action> [target] [--note=<text>] [--prompt=<text>] [--category=<name>]
#
# Examples:
#   add-rule.rb ~/.claude/sort.local.md '{ext: [.torrent, .nzb]}' delete '' --note="auto-delete torrents"
#   add-rule.rb ~/.claude/sort.md '{filename_glob: "Invoice-*.pdf"}' route 'AI Library/Invoices/'
#   add-rule.rb ~/.claude/sort.md '{ext: [.pdf]}' prompt '' --prompt="Decide if this is a receipt, invoice, or contract."
#   add-rule.rb ~/.claude/sort.local.md '{filename_regex: "(?i)recovery"}' route_sensitive '' --category=credentials
#
# - Creates the target file with a default template if it doesn't exist.
# - Parses existing YAML frontmatter, appends to rules:, writes back.
# - Preserves the markdown body untouched.

require "yaml"
require "fileutils"

def die(msg)
  warn "add-rule.rb: #{msg}"
  exit 1
end

def expand(path)
  File.expand_path(path)
end

usage = <<~USAGE
  Usage: add-rule.rb <file> <match-yaml-inline> <action> [target] [--note=<text>] [--prompt=<text>] [--category=<name>]
USAGE

# Parse args
file = ARGV.shift or die(usage)
match_yaml = ARGV.shift or die(usage)
action = ARGV.shift or die(usage)

target = ""
note = nil
prompt = nil
category = nil
ARGV.each do |arg|
  if arg.start_with?("--note=")
    note = arg.sub("--note=", "")
  elsif arg.start_with?("--prompt=")
    prompt = arg.sub("--prompt=", "")
  elsif arg.start_with?("--category=")
    category = arg.sub("--category=", "")
  else
    target = arg
  end
end

valid_actions = %w[delete route route_sensitive ask skip prompt]
die("invalid action '#{action}', expected one of: #{valid_actions.join(", ")}") unless valid_actions.include?(action)

if action == "route" && target.to_s.empty?
  die("action 'route' requires a target path")
end

if action == "prompt" && prompt.to_s.strip.empty?
  die("action 'prompt' requires --prompt=<text>")
end

canonical_categories = %w[credentials identity financial medical legal other]
if category && !category.to_s.strip.empty?
  if action != "route_sensitive"
    warn "add-rule.rb: --category is only meaningful with action 'route_sensitive'; ignoring."
    category = nil
  elsif !canonical_categories.include?(category.downcase)
    warn "add-rule.rb: category '#{category}' is not in the canonical list (#{canonical_categories.join(", ")}); writing it through verbatim — the dispatcher will Title-Case it as a custom subfolder."
  else
    category = category.downcase
  end
end

# Parse the match expression
begin
  match = YAML.safe_load(match_yaml, permitted_classes: [Symbol])
rescue Psych::SyntaxError => e
  die("could not parse match YAML: #{e.message}\n  input: #{match_yaml}")
end
die("match must be a mapping, got #{match.class}") unless match.is_a?(Hash)

# Resolve file path
file = expand(file)
FileUtils.mkdir_p(File.dirname(file))

# Bootstrap if missing
unless File.exist?(file)
  default = <<~MD
    ---
    rules: []
    ---

    # Sort overrides

    Custom rules for `/sort`. See OVERRIDES.md in the sort plugin for the schema,
    or run `/sort:add-rule` to add more rules interactively.
  MD
  File.write(file, default)
end

# Split frontmatter / body
content = File.read(file)
unless content.start_with?("---\n") || content.start_with?("---\r\n")
  die("file does not start with a YAML frontmatter block: #{file}")
end

# Extract frontmatter — find the second `---` line
lines = content.lines
opener_idx = 0  # the leading ---
closer_idx = nil
lines.each_with_index do |line, i|
  next if i == opener_idx
  if line.strip == "---"
    closer_idx = i
    break
  end
end
die("could not find closing --- of frontmatter in #{file}") unless closer_idx

front_text = lines[(opener_idx + 1)...closer_idx].join
body = lines[(closer_idx + 1)..].join

begin
  front = YAML.safe_load(front_text, permitted_classes: [Symbol]) || {}
rescue Psych::SyntaxError => e
  die("frontmatter is not valid YAML in #{file}: #{e.message}")
end
die("frontmatter must be a mapping at top level in #{file}") unless front.is_a?(Hash)

front["rules"] ||= []

# Build the new rule
rule = { "match" => match, "action" => action }
rule["to"] = target unless target.to_s.empty?
rule["prompt"] = prompt if prompt && !prompt.to_s.empty?
rule["category"] = category if category && !category.to_s.empty?
rule["note"] = note if note

front["rules"] << rule

# Reassemble — strip the leading "---\n" YAML.dump produces, then re-wrap
serialized = YAML.dump(front)
serialized = serialized.sub(/\A---\s*\n/, "")
File.write(file, "---\n#{serialized}---\n#{body}")

# Report
puts "Added rule to #{file}:"
puts YAML.dump(rule).sub(/\A---\s*\n/, "").strip
