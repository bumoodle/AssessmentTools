#!/usr/bin/env ruby

require 'optparse'
require 'csv'

substitutions = {}

# Reads a CSV user-map into a hash mapping Usage ID to its replacement.
def read_substitutions(mapfile)

  new_map = {}

  #for each row in the given mapfile
  CSV.foreach(mapfile, :headers => true, :header_converters => :symbol) do |row|

    id_number = row.fields[0]

    #parse the row into a new hash element
    new_map[id_number] = row.fields[1]
    
  end

  #return the new map
  new_map

end


#set up parsing of the command line arguments
opts = OptionParser.new do |opts|
  opts.banner = "Usage: recordsmap.rb [options] records.txt"

  #allow the user to specify a map file
  opts.on('-s', '--subst SUBCSV') do |mapfile| 
    substitutions = read_substitutions(mapfile)
  end

end

#parse the command line arguments
opts.parse!

#print header
print "Test, ID\n"

ARGF.each_cons(3) do |a, b, c|

  #Remove leading/trailing spaces.
  a, b, c = a.chomp, b.chomp, c.chomp

  #If we have a valid sandwich.
  if a == c 

    #If we have the longer identifier first, swap them.
    a, b = b, a if a.length < b.length

    #If we have a subsitution for the ID, use it.
    a = substitutions.has_key?(a) ? substitutions[a] : a

    #And print the modified row.
    puts "#{a}, #{b}"

  end
end
