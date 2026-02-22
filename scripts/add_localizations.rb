#!/usr/bin/env ruby
require 'xcodeproj'

# 57 new languages to add
NEW_LANGUAGES = %w[
  pt-PT ru tr pl nl sv da nb fi el cs hu ro uk vi th id ms fil
  he fa ur bn ta te mr gu kn ml pa si my km lo ne am sw zu af
  ha yo ig so sr hr bs sk sl bg mk sq lt lv et is ca eu
]

project_path = 'ElioChat.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the Resources group
def find_group(group, path_components)
  return group if path_components.empty?
  child = group.children.find { |c| c.name == path_components.first || c.path == path_components.first }
  return nil unless child
  find_group(child, path_components[1..-1])
end

resources_group = find_group(project.main_group, ['LocalAIAgent', 'Resources'])

if resources_group.nil?
  puts "❌ Resources group not found"
  exit 1
end

added_count = 0
skipped_count = 0

NEW_LANGUAGES.each do |lang_code|
  lproj_name = "#{lang_code}.lproj"

  # Check if already exists
  existing = resources_group.children.find { |c| c.path == lproj_name }

  if existing
    puts "⚠️  #{lproj_name} already exists, skipping"
    skipped_count += 1
    next
  end

  # Create variant group for Localizable.strings
  localizable_ref = resources_group.children.find { |c| c.path == "Localizable.strings" }

  unless localizable_ref
    # Create the variant group if it doesn't exist
    localizable_ref = resources_group.new_variant_group('Localizable.strings')
  end

  # Add language to variant group
  file_ref = localizable_ref.new_file("#{lang_code}.lproj/Localizable.strings")
  file_ref.last_known_file_type = 'text.plist.strings'

  puts "✅ Added #{lproj_name}"
  added_count += 1
end

# Add known regions to project
known_regions = project.root_object.known_regions || []
NEW_LANGUAGES.each do |lang|
  unless known_regions.include?(lang)
    known_regions << lang
  end
end
project.root_object.known_regions = known_regions.uniq

project.save

puts ""
puts "🎉 Localization setup complete!"
puts "   Added: #{added_count} languages"
puts "   Skipped: #{skipped_count} (already existed)"
puts "   Total languages: #{known_regions.count}"
