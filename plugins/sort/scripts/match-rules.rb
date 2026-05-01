#!/usr/bin/env ruby
# frozen_string_literal: true

# match-rules.rb — show which sort rules apply to one or more files.
#
# Usage:
#   match-rules.rb [-v] [--rules-only] [<file>...]
#
# Loads every rule file the dispatcher would load (in priority order):
#   1. $PWD/.claude/sort.local.md
#   2. $PWD/.claude/sort.md
#   3. ~/.claude/sort.local.md
#   4. ~/.claude/sort.md
# Concatenates rules in that order and, for each input file, walks the combined
# list top-to-bottom reporting the winning rule (first match) and — with -v —
# every rule that was considered along with why it did or didn't match.
#
# Phase rules are not file-level matchers; they're listed in --rules-only output
# but skipped when matching against a file path.

require "yaml"
require "shellwords"

# ---------- helpers ----------

def home_collapse(path)
  home = Dir.home
  path.start_with?(home) ? path.sub(home, "~") : path
end

def parse_size(s)
  return s.to_i if s.is_a?(Numeric)
  m = s.to_s.strip.upcase.match(/\A(\d+(?:\.\d+)?)\s*([KMGT]?B?)\z/)
  return 0 unless m
  num = m[1].to_f
  factor = { "" => 1, "B" => 1, "K" => 1024, "KB" => 1024,
             "M" => 1024**2, "MB" => 1024**2,
             "G" => 1024**3, "GB" => 1024**3,
             "T" => 1024**4, "TB" => 1024**4 }[m[2]] || 1
  (num * factor).to_i
end

def normalize_ext(e)
  s = e.to_s.downcase
  s.start_with?(".") ? s : ".#{s}"
end

# ---------- rule loading ----------

RULE_FILES = [
  File.join(Dir.pwd, ".claude", "sort.local.md"),
  File.join(Dir.pwd, ".claude", "sort.md"),
  File.join(Dir.home, ".claude", "sort.local.md"),
  File.join(Dir.home, ".claude", "sort.md"),
].freeze

def load_frontmatter(path)
  content = File.read(path)
  return nil unless content.start_with?("---\n") || content.start_with?("---\r\n")
  lines = content.lines
  closer = nil
  lines.each_with_index do |line, i|
    next if i == 0
    if line.strip == "---"
      closer = i
      break
    end
  end
  return nil unless closer
  front_text = lines[1...closer].join
  YAML.safe_load(front_text)
rescue Psych::SyntaxError => e
  warn "match-rules.rb: bad YAML in #{home_collapse(path)}: #{e.message}"
  nil
end

def load_all_rules
  combined = []
  scalars = {}
  errors = []
  RULE_FILES.each do |path|
    next unless File.exist?(path)
    front = load_frontmatter(path)
    next unless front.is_a?(Hash)

    %w[sources sensitive_dir].each do |k|
      scalars[k] = front[k] if front.key?(k) && !scalars.key?(k)
    end

    Array(front["rules"]).each_with_index do |rule, i|
      unless rule.is_a?(Hash)
        errors << "#{home_collapse(path)}:rule index #{i + 1} is not a mapping"
        next
      end
      combined << { rule: rule, source: path, index: i + 1 }
    end
  end
  [combined, scalars, errors]
end

# ---------- matching ----------

def match_predicate(matcher, file_path)
  # Returns [bool_result, reason_string]
  return [true, "(empty matcher — matches everything)"] unless matcher.is_a?(Hash) && !matcher.empty?

  matcher.each do |key, val|
    ok, why = single_predicate(key, val, file_path)
    return [false, why] unless ok
  end
  [true, "all sub-matchers passed"]
end

def single_predicate(key, val, file_path)
  basename = File.basename(file_path)
  case key
  when "ext"
    have = File.extname(file_path).downcase
    want = Array(val).map { |e| normalize_ext(e) }
    if want.include?(have)
      [true, "ext #{have} ∈ #{want.inspect}"]
    else
      [false, "ext #{have.empty? ? "(none)" : have} ∉ #{want.inspect}"]
    end
  when "filename_glob"
    if File.fnmatch?(val.to_s, basename, File::FNM_DOTMATCH | File::FNM_PATHNAME)
      [true, "glob #{val.inspect} matched #{basename.inspect}"]
    else
      [false, "glob #{val.inspect} did not match #{basename.inspect}"]
    end
  when "filename_regex"
    re = Regexp.new(val.to_s)
    if re.match?(basename)
      [true, "regex #{val.inspect} matched #{basename.inspect}"]
    else
      [false, "regex #{val.inspect} did not match #{basename.inspect}"]
    end
  when "mime_type"
    return [false, "file does not exist (mime check skipped)"] unless File.exist?(file_path)
    mime = `file --mime-type -b #{Shellwords.escape(file_path)}`.strip
    if mime == val.to_s
      [true, "mime #{mime.inspect} == #{val.inspect}"]
    else
      [false, "mime #{mime.inspect} != #{val.inspect}"]
    end
  when "size_gt"
    return [false, "file does not exist (size check skipped)"] unless File.exist?(file_path)
    threshold = parse_size(val)
    sz = File.size(file_path)
    sz > threshold ? [true, "size #{sz} > #{threshold}"] : [false, "size #{sz} ≤ #{threshold}"]
  when "size_lt"
    return [false, "file does not exist (size check skipped)"] unless File.exist?(file_path)
    threshold = parse_size(val)
    sz = File.size(file_path)
    sz < threshold ? [true, "size #{sz} < #{threshold}"] : [false, "size #{sz} ≥ #{threshold}"]
  when "phase"
    [false, "phase matcher (#{val}) — not a file-level rule, skipped"]
  when "all"
    return [false, "all: expected a list, got #{val.class}"] unless val.is_a?(Array)
    val.each_with_index do |sub, i|
      ok, why = match_predicate(sub, file_path)
      return [false, "all[#{i}] failed: #{why}"] unless ok
    end
    [true, "all sub-matchers passed (#{val.length})"]
  when "any"
    return [false, "any: expected a list, got #{val.class}"] unless val.is_a?(Array)
    val.each_with_index do |sub, i|
      ok, _ = match_predicate(sub, file_path)
      return [true, "any[#{i}] passed"] if ok
    end
    [false, "any: no sub-matcher passed"]
  when "missing"
    [false, "missing: only valid inside a phase matcher"]
  else
    [false, "unknown matcher key: #{key.inspect}"]
  end
end

def render_action(rule)
  action = rule["action"] || "?"
  parts = [action]
  parts << "→ #{rule["to"]}" if rule["to"]
  parts << "[#{rule["category"]}]" if rule["category"]
  if rule["prompt"]
    snippet = rule["prompt"].to_s.gsub(/\s+/, " ").strip
    snippet = "#{snippet[0, 77]}…" if snippet.length > 78
    parts << "→ #{snippet.inspect}"
  end
  parts << "  (#{rule["note"]})" if rule["note"]
  parts.join(" ")
end

# ---------- output ----------

def print_rule_listing(combined)
  if combined.empty?
    puts "No rules loaded. (Looked in #{RULE_FILES.map { home_collapse(_1) }.join(", ")})"
    return
  end
  puts "Loaded #{combined.length} rule#{combined.length == 1 ? "" : "s"} (priority order):"
  combined.each_with_index do |entry, i|
    rule = entry[:rule]
    src = "#{home_collapse(entry[:source])}:#{entry[:index]}"
    matcher = rule["match"].is_a?(Hash) ? rule["match"].inspect : "(invalid match)"
    puts "  #{(i + 1).to_s.rjust(3)}. #{src.ljust(48)} match=#{matcher}  action=#{render_action(rule)}"
  end
end

def print_match_for_file(file_path, combined, verbose:)
  display = file_path
  display = home_collapse(File.expand_path(file_path)) if file_path.start_with?("/", "~") || File.exist?(file_path)

  considered = combined.map do |entry|
    ok, why = match_predicate(entry[:rule]["match"], file_path)
    { entry: entry, ok: ok, why: why }
  end
  matches = considered.select { |c| c[:ok] }
  winner = matches.first

  puts display

  rows_to_show = verbose ? considered : matches

  if rows_to_show.empty?
    if verbose && combined.empty?
      puts "  (no rules loaded)"
    elsif verbose
      considered.each do |c|
        src = "#{home_collapse(c[:entry][:source])}:#{c[:entry][:index]}"
        puts "  ·          #{src.ljust(48)} #{c[:why]}"
      end
    end
  else
    rows_to_show.each do |c|
      is_winner = c[:entry] == winner&.dig(:entry)
      shadowed = c[:ok] && !is_winner
      marker =
        if is_winner then "✓ winner "
        elsif c[:ok] then "✓ shadow"
        else "·       "
        end
      src = "#{home_collapse(c[:entry][:source])}:#{c[:entry][:index]}"
      reason = verbose ? "  #{c[:why]}" : ""
      puts "  #{marker} #{src.ljust(48)} action=#{render_action(c[:entry][:rule])}#{reason}"
    end
  end

  if winner
    src = "#{home_collapse(winner[:entry][:source])}:#{winner[:entry][:index]}"
    puts "  → effective: #{render_action(winner[:entry][:rule])}    [#{src}]"
  else
    puts "  → no rule matched — falls through to default classification"
  end
  puts
end

# ---------- main ----------

verbose = false
rules_only = false
files = []

ARGV.each do |arg|
  case arg
  when "-v", "--verbose" then verbose = true
  when "--rules-only", "--rules" then rules_only = true
  when "-h", "--help"
    puts <<~USAGE
      Usage: match-rules.rb [-v] [--rules-only] [<file>...]

        -v, --verbose       Show every rule considered, with reason
        --rules-only        Print the merged rule list and exit
        -h, --help          This help

      Resolution order (first match wins, lower-priority files still apply
      to files no higher-priority rule matched):

      #{RULE_FILES.map { |p| "  #{home_collapse(p)}" }.join("\n")}
    USAGE
    exit 0
  else
    files << arg
  end
end

combined, scalars, errors = load_all_rules

errors.each { |e| warn "match-rules.rb: #{e}" }

unless scalars.empty?
  puts "Top-level settings (highest-priority file wins per key):"
  scalars.each { |k, v| puts "  #{k}: #{v.inspect}" }
  puts
end

if rules_only || files.empty?
  print_rule_listing(combined)
  exit 0
end

files.each { |f| print_match_for_file(f, combined, verbose: verbose) }
