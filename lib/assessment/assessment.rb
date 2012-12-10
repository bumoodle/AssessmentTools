
require 'csv'
require 'prawn'
require 'RMagick'
require 'pdf-reader'

require_relative 'question_attempt'

module Assessment


  #
  # Represents a paper-copy assessment, such as a moodle PaperCopy quiz.
  #
  class Assessment

    #
    # Allow external access to the list of attempts.
    #
    attr_reader :attempts

    #
    # Initializes a new assessment object from a collection of attempts.
    #
    def initialize(attempts=nil)

      #If attempts were provided, use them; otherwise, use an empty array.
      @attempts = attempts || []

      #Create a hashes which sort the attempts by various IDs
      @by_copy = {}
      @by_question = {}

    end

    #
    # Factory method which procudes a new Assessment from a collection of files.
    #
    # If a block is provided, the block will be notified of progress, in the form of
    # |last_index_processed, total|.
    #
    def self.from_files(files, autorotate=true)

      #Create a new, empty assessment.
      assessment = self.new

      #And add each file in the 
      files.each_with_index do |file, index|

        #Handle each file according to its extension
        case File.extname(file)
          when '.pdf' 
            assessment.add_pdf(file, autorotate)
          else 
            assessment.add_image(file, autorotate)
          end

        #If we were given a block, notify it of our progress.
        yield index, files.count if block_given? 

      end

      assessment
    end

    #
    # Add an attempt to the assignment.
    #
    def add_attempt(attempt)

      #Add the hash to our list of attempts
      @attempts << attempt

      #Add the attempt to our by-usage hash...
      unless attempt.copy_id.nil?
        @by_copy[attempt.copy_id] ||= []
        @by_copy[attempt.copy_id] << attempt
      end

      #... and to our by-question hash
      unless attempt.question_id.nil?
        @by_question[attempt.question_id] ||= []
        @by_question[attempt.question_id] << attempt
      end

    end

    #
    # Adds a new single image file to the Assessment.
    #
    def add_image(filename, autorotate=true)
      add_attempt(QuestionAttempt.from_image(filename, autorotate))
    end

    #
    # Adds each page of a small PDF file to the assessment.
    #
    def add_pdf(filename, autorotate=true)

      #Get a list of pages in the PDF file...
      pages = PDF::Reader.new(filename).pages

      #Add each _page_ as its own question.
      #We take advantage of the way ImageMagick views PDFs- in which each PDF is actually
      #an "array" of images, with filenames name.pdf[0], name.pdf[1], and etc.
      pages.each_index { |i| add_image("#{filename}[#{i}]", autorotate) }

    end

    #
    # Returns the number of unique student copies 
    # included in this assessment.
    #
    def copy_count
      @by_copy.count
    end
    

    #
    # Iterates over the question attempts in the assessment.
    # Yields the attempt.
    #
    def each_attempt(&block)
      @attempts.each(&block)
    end

    #
    # Iterates over each copy of the assessment.
    # Yields |copy_id, attempts|.
    #
    def each_copy(&block)
      @by_copy.each(&block)
    end


    #
    # Iterates over each attempt which is missing at least one identifier.
    # Yields the attempt.
    #
    def each_invalid_attempt(&block)
      invalid_attempts.each(&block)
    end

    #
    # Iteraetes over each ungraded attempt in the assessment.
    #
    def each_ungraded_attempt(&block)
      ungraded_attempts.each(&block) 
    end

    #
    # Iterates over each question in the assessment.
    # Yields |question_id, attempts|.
    #
    def each_question(&block)
      @by_question.each(&block)
    end

    #
    # Iterates over each attempt which has all of its identifiers
    # Yields the attempt.
    #
    def each_valid_attempt(&block)
      valid_attempts.each(&block)
    end


    #
    # Returns an array of all of the attempts which are missing information
    # or grades.
    #
    def incomplete_attempts
      @attempts.select { |x| x.missing_identifiers? || x.ungraded? }
    end

    #
    # Returns an array of all of the _invalid_ question attempts in this assessment.
    # 
    def invalid_attempts
      @attempts.select { |x| x.missing_identifiers? }
    end

    #
    # Generates a PDF containing each of the attempts which could not be otherwise identified.
    #
    def invalid_attempts_to_pdf(filename, footer=nil, scale=1.0, density=300)
      self.class.pdf_from_attempt_collection(filename, invalid_attempts, footer, scale, density)
    end


    #
    # Returns the amount of unique question variants in the assessment.
    #
    def question_count 
      @by_question.count
    end



    #
    # Converts the given assessment to a CSV.
    # If a filename is provided, the CSV will be written to that file.
    #
    # @returns A CSV containing all grades in the assessment, sorted by test copy.
    #
    def to_csv_by_copy(filename=nil, &block)
      self.class.csv_from_iterator(each_copy, filename, &block)
    end

    #
    # Creates a single PDF for each student copy of the assessment,
    # in roughly the same format that the student took it, but unordered.
    #
    # Options are the same as the to_pdfs function.
    #
    def to_pdfs_by_copy(options = {}, &block)
      self.class.pdf_from_iterator(each_copy, options, &block)
    end

    #
    # Converts the assessment to a collection of Moodle-uploadable JPEG files,
    # with an identifying file format.
    #
    def to_moodle_images(options = {})

      #Defaults for the "keyword arguments".
      path        = options[:path]       || "."
      scale       = options[:scale]      || 1.0
      density     = options[:density]    || 300
      extension   = options[:extension]  || '.jpg'

      #Convert each attempt to an appropriately named image. 
      @attempts.each_with_index do |attempt, index|
        
        page_number = 0

        #Convert the given attempt to an image.
        image = attempt.to_image(scale, density)

        #yield our current status, if a block was provided
        yield attempt, index if block_given? 

        #Create a file-name which will identify the relevant attempt to Moodle.
        filename = attempt.filename_for_upload(page_number, extension, path)

        #Write the attempt to the given file, and continue.
        image.write(filename)

      end
    end

    

    #
    # Creates a single PDF for each encountered question variant which contains
    # all attempts at that variant.
    #
    def to_pdfs_by_question(options={}, &block)
      self.class.pdf_from_iterator(each_question, options, &block)
    end

    #
    # Create a single PDF which contains all of the 
    #
    def to_pdf_by_question(filename, footer=nil)

      #Retrieve a list of all valid attempts
      attempts = valid_attempts.sort_by! { |x| x.question_id }

      #And convert the list of attempts to a single PDF.
      self.class.pdf_from_attempt_collection(filename, attempts, footer)

    end

    #
    # Returns an array of all of the _ungraded_ question attempts_ in this assessment.
    #
    def ungraded_attempts
      @attempts.select { |x| x.ungraded? }
    end

    #
    # Returns an array of all of the _valid_ question attempts in this assessment.
    #
    def valid_attempts
      @attempts.reject { |x| x.missing_identifiers? }
    end

    #
    # Converts the given CSV to a 
    #
    def self.csv_from_iterator(iterator, filename=nil)

      csv_data = CSV.generate do |csv|

        #For each of the provided attempt collections...
        iterator.each do |identifier, attempts|
        
          #Start off the first column with an identifier...
          header = [block_given?() ? (yield identifier) : identifier]
          
          #Sort the attempts by question ID, establishing a consistent order, when possible.
          attempts = attempts.sort { |a, b| a.question_id <=> b.question_id }

          #Add each of the grades to the CSV.
          csv << header + attempts.collect { |a| a.grade }

        end

      end

      #If we were given a filename...
      unless filename.nil?

        #Write the CSV data to that file.
        File.open(filename, 'w') do |f| 
          f.write(csv_data) 
        end

      end

      #And return the CSV data.
      csv_data

    end



    #
    # Creates a collection of PDFs by iterating over a hash or hash-like object.
    # 
    # The provided iterator should yield:
    # - an id (which is used to determine the appropriate output filename)
    # - a enumerable collection of attempts to be included in the PDF
    #
    # 
    #
    def self.pdf_from_iterator(iterator, options={})

      #Defaults for the "keyword arguments".
      path        = options[:path]     || ""
      prefix      = options[:prefix]   || "attempt"
      scale       = options[:scale]    || 1.0
      density     = options[:density]  || 300
      footer      = options[:footer]

      #Iterate over the copies of this assessment
      iterator.each_with_index do |values, index|

        id, attempts = values 

        #If the caller passed a block, use it to figure out the filename;
        #otherwise, use the defult name and path prefix.
        filename = path +  "#{prefix}_#{id}.pdf"

        #Create a PDF from the given collection of attempts.
        pdf_from_attempt_collection(filename, attempts, footer, scale, density)

        #If a status-requesting block was given, yield the current status to it.
        if block_given?
            yield index, iterator.count
        end

      end    
    end



    #
    # Creates a single PDF file from an ordered collection of attempts.
    #
    def self.pdf_from_attempt_collection(filename, attempts, footer=nil, scale=1, density=300)

      #Generate a PDF which contains each of the requested images, in order.
      Prawn::Document.generate(filename, :skip_page_creation => true) do

        attempts.each_with_index do |attempt, index|

          #Convert the given attempt to a JPEG image.
          attempt_image = attempt.to_image(scale, density, 'JPEG', footer)

          #Start a new page which is exactly sized to the image.
          start_new_page(:size => [attempt_image.columns, attempt_image.rows], :margin => 0)
          
          #Add the image to our PDF...
          raw_image = StringIO.new(attempt_image.to_blob)
          image(raw_image)

          #If a block was provided, pass it the current status.
          if block_given?
            yield index, attempts.count
          end

        end
      end

    end
  end
end
