
require 'trollop'
require 'assessment'

#Mix the main "assessment" module into main, so we can easily
#use its classes.
include Assessment

# Set up the command-line arguments for the application.
opts = Trollop::options do
  version "PaperCopy assessment helper for Moodle, version 0.1.0"
end

#Create a new assessment, and fill it with each of the given files
assess = Assessment::Assessment.from_files(ARGV)

assess.to_pdf_by_question('/tmp/pdfs.pdf')
