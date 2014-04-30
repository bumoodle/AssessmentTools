#!/usr/bin/env ruby

require 'trollop'
require 'csv'

opts = Trollop::options do
  opt :tablename, "The name of the table to be updateed", :default => "mdl_quiz_attempts"
end

#Iterate over each of the rows in the CSV.
CSV.foreach("/tmp/sumgrades.csv", :headers => true) do |row|

  #Skip any rows that don't have definitive IDs.
  next unless row[0]

  #Build a list of values to be composed.
  #TODO: Escape these?
  updates = []
  row.headers[1..-1].each { |header| updates << "#{header} = #{row[header]}" }

  #And print the list to the screen.
  puts "UPDATE #{opts[:tablename]} SET #{updates.join(',')} WHERE #{row.headers[0]} = #{row[0]};"

end


