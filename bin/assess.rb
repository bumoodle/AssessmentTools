
require 'trollop'
require 'docsplit'
require 'assessment'
require 'progressbar'
require 'highline/import'

#
# Splits a PDF and returns an array of relevant images.
# If a non-PDF is provided, its filename is returned unmodified.
# 
def split_pdf(filename, density=300, format=:jpg)

  #If this isn't a PDF, return the unmodified filename.
  return filename unless File.extname(filename) == '.pdf'

  #Get the length of the PDF...
  length = Docsplit.extract_length(filename)

  #If we don't have a multi-page document, abort.
  return filename unless length > 1

  #Otherwise, split the document
  Docsplit.extract_pages(filename)

  # Determine the base name of the file, and the file's length, in pages.
  # We have to use these two parameters to figure out the files generated by docsplit,
  # which doesn't return a list of created files.
  basename = File.basename(filename, '.pdf')

  #... and add the resultant PDFs to the new argument list.
  (1..length).collect { |x| "#{basename}_#{x}.pdf" }

end

#
# Splits a list of PDFs into a collection of single-page PDFs.
#
def split_pdfs!(list, density=300, format=:jpg)

  #Process each of the command-line arguments;
  #potentially transforming them into lists of split files.
  list.map! { |pdf| split_pdf(pdf, density, format) }

  #Flatten the list of files.
  list.flatten!

end

#
# Iteractively requests assessment info for the given assignment.
#
def populate_assessment_info(attempt)

  #establish the format in which the user should enter the identifier 
  #TODO: abstract?
  identifier_format = /^([0-9]+)-([0-9]+)-([0-9]+)$/

  #prompt the user for the question's identifier
  identifier = ask ("\nCouldn't figure out the Attempt ID for '#{attempt.images.first[:path]}'. Enter the attempt ID displayed below the question barcode> ")  { |i| i.validate = identifier_format }

  #once we have a valid identifier, parse it, and extract the user's information
  identifier = identifier.match(identifier_format)
  
  #and use it to fill in the missing fields from the QA
  attempt.usage_id, qa.question_id, qa.attempt_id = identifier[1], identifier[2], identifier[3]

end

#
# Interactively requests a grade for the given assesssment.
#
def populate_grade_information(attempt)

  #TODO: abstract
  grade_range = 0..10

  #get a grade from the user between 0 and 10
  attempt.grade = ask("\nCouldn't find a grade in the image ('#{attempt.images.first[:path]}'). Enter an integer grade between 0 and 10> ", Integer) { |i| i.in = grade_range }

end


# Set up the command-line arguments for the application.
opts = Trollop::options do
  version "PaperCopy assessment helper for Moodle, version 0.1.0"
  
  opt :split,       "Split multi-page PDFs into multiple single-page PDFs."
  opt :outpath,     "Specifies the output folder for multiple-file operations.", :default => Dir::pwd
  opt :interactive, "If set, the system will interactively prompt for fixes when invalid data appears."

  opt :moodle,      "Interactively generates a single JPEG for each attempt in a Moodle-uploadable format."

  opt :csv,         "Generate a single CSV file with all of the extracted assessment data, and writes it to the given filename.", :type => :string

  opt :question,    "Split into several single-question PDFs."
  opt :qprefix,     "The prefix use for single-question PDF files. Ignored unless the --question flag is provided.", :default => 'question'

  opt :attempt,     "Split into several single-attempt PDFs."
  opt :aprefix,     "The prefix use for single-attempt PDF files. Ignored unless the --attempt flag is provided.", :default => 'attempt'

  opt :invalids,    "If provided, dumps any unidentified attempt into the given filename.", :type => :string

  opt :dpi,         "The DPI at which any PDF input should be captured.", :default => 300
  opt :scale,       "The size scale by which the input PDFs' dimensions are multiplied. 1 indicates same size; 0.25 indicates quarter size.", :default => 1.0
  opt :norotate,    "If specified, the provided images will not be rotated."

  opt :footer,      "An image to be appended to each question in the PDF.", :default => nil, :type=> :string

end

#If the split option was provided, split the PDFs into various files, and use those.
split_pdfs!(ARGV, opts[:density]) if opts[:split]

#If we don't have any other operation, abort.
exit unless opts[:question] || opts[:attempt] || opts[:invalids] || opts[:moodle]

#
# Analysis: Analyze each of the provided files, and extract grading information.
# 

#Create a new progress bar, which will track the analysis.
progress = ProgressBar.new('Analyzing', ARGV.count - 1,)

#Create a new assessment, and fill it with each of the given files
assess = Assessment::Assessment.from_files(ARGV, !opts[:norotate]) { |p| progress.set(p) }

#Finish filling the progress bar.
progress.finish

#
# If interactive mode is set, allow the user to repair any invalid data.
#
if opts[:interactive]
  assess.each_invalid_attempt { |a| populate_assessment_info(a) } 
  assess.each_ungraded_attempt { |a| populate_grade_information(a) }
end

#
# Handle generation of the files.
# TODO: abstract the below to a single with_progress method?
#


#Determine the output path
path = opts[:outpath] + '/'

options = {
  :path => path, 
  :footer => opts[:footer], 
  :scale => opts[:scale], 
  :density => opts[:dpi]
}

#Compute the total number of attempts-images to be generated,
#which should roughly correspond to the needed computation time.
to_be_generated = (opts[:question] ? assess.question_count : 0)
to_be_generated += (opts[:attempt] ? assess.copy_count : 0)
to_be_generated += (opts[:invalids] ? assess.invalid_attempts.count : 0)
to_be_generated += (opts[:moodle] ? assess.attempts.count : 0)


#Create a progress bar, which will track the status of the generation.
progress = ProgressBar.new('Generating', to_be_generated)

if opts[:csv]
  assess.to_csv_by_copy(opts[:csv])
end


#Handle the question option...
if opts[:question]

  #Set the file prefix to the question-specific prefix.
  options[:prefix] = opts[:qprefix]

  #Generate the question PDFs, updating the progress bar as we go.
  assess.to_pdfs_by_question(options) { progress.inc }

end

#Handle the question option...
if opts[:attempt]
  
  #Set the file prefix to the question-specific prefix.
  options[:prefix] = opts[:aprefix]

  #Generate the question PDFs, updating the progress bar as we go.
  assess.to_pdfs_by_copy(options) { progress.inc }

end

#Handle the "catch-all" for invalid attempts.
if opts[:invalids]
  assess.invalid_attempts_to_pdf(opts[:invalids], opts[:footer], opts[:scale], opts[:dpi]) { progress.inc }
end

#Handle Moodle-uploadable JPEGs.
if opts[:moodle]
  assess.to_moodle_images(options) { progress.inc }
end

#And terminate the progress bar once we're complete.
progress.finish



