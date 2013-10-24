#!/usr/bin/env ruby

require 'fileutils'

FILENAME_FORMAT = /U(?<quiz>[0-9]+)_Q(?<question>[0-9]+)_A(?<attempt>[0-9]+)_G(?<grade>[0-9]+)?_P(?<page>[0-9]+).jpg/i

seen = {}

#
# Quick function which generates a unique string for each unique attempt.
#
def file_id(matches)
  "#{matches[:quiz]}-#{matches[:question]}-#{matches[:attempt]}"
end

#Check each of the files in the working directory.
ARGV.each do |file|

  #Parse the filename, and get each of the core components.
  matches = FILENAME_FORMAT.match(file)
  next unless matches

  id = file_id(matches)

  #If we've already seen this file, and it doesn't have a grade, delete it.
  if seen[id] and matches["grade"].nil?
    FileUtils::rm(file)
    next

  #Otherwise, if we have a grade, and this has been seen as non-graded before,
  #delete the previously seen item.
  elsif seen[id] and seen[id]["grade"].nil?
    FileUtils::rm(seen[id][:file])

  #Otherwise, something's wrong.
  elsif seen[id] and seen[id]["grade"]
    puts "--> !!! Apparent conflict between #{seen[id][:file]} and #{file}."
  end

  seen[id] = Hash[matches.names.zip(matches.captures)]
  seen[id][:file] = file


end
