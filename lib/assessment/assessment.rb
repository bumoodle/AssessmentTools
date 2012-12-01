
require 'RMagick'
require 'pdf-reader'
require 'prawn'
require 'prawn/images/jpg'

require_relative 'question_attempt'

module Assessment

  attr_reader :attempts

  #
  # Represents a paper-copy assessment, such as a moodle PaperCopy quiz.
  #
  class Assessment

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
    def self.from_files(files)

      #Create a new, empty assessment.
      assessment = self.new

      #And add each file in the 
      files.each do |file|

        #Handle each file according to its extension
        case File.extname(file)
          when '.pdf' 
            assessment.add_pdf(file)
          else 
            assessment.add_image(file)
          end
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
    def add_image(filename)
      add_attempt(QuestionAttempt.from_image(filename))
    end

    #
    # Adds each page of a PDF file to the assessment.
    #
    def add_pdf(filename)

      #Get a list of pages in the PDF file...
      pages = PDF::Reader.new(filename).pages

      #Add each _page_ as its own question.
      #We take advantage of the way ImageMagick views PDFs- in which each PDF is actually
      #an "array" of images, with filenames name.pdf[0], name.pdf[1], and etc.
      pages.each_index { |i| add_image("#{filename}[#{i}]") }

    end

    def maximum_dimensions

      #Get the maximum width and height for any given attempt.
      width = @attempts.map { |a| a.maximum_dimensions[0] }.max
      height = @attempts.map { |a| a.maximum_dimensions[1] }.max

      #And return them.
      return width, height 

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
    # Iterates over each question in the assessment.
    # Yields |question_id, attempts|.
    #
    def each_question(&block)
      @by_question.each(&block)
    end


    #
    # Creates a single PDF for each student copy of the assessment,
    # in roughly the same format that the student took it, but unordered.
    #
    def to_pdfs_by_copy(path_prefix="", name="assessment")

      #Iterate over the copies of this assessment
      each_copy do |id, attempts|

        #If the caller passed a block, use it to figure out the filename;
        #otherwise, use the defult name and path prefix.
        filename = path_prefix + (block_given? ? (yield id) : "#{name}_#{id}.pdf")

        #Create a PDF from the given collection of attempts.
        self.class.pdf_from_attempt_collection(filename, attempts)

      end    
    end

    #
    # Creates a single PDF for each encountered question variant which contains
    # all attempts at that variant.
    #
    def to_pdfs_by_question(path_prefix="", name="question")

      #Iterate over the copies of this assessment
      each_question do |id, attempts|

        #If the caller passed a block, use it to figure out the filename;
        #otherwise, use the defult name and path prefix.
        filename = path_prefix + (block_given? ? (yield id) : "#{name}_#{id}.pdf")

        #Create a PDF from the given collection of attempts.
        self.class.pdf_from_attempt_collection(filename, attempts)

      end

    end

    #
    # Create a single PDF which contains all of the 
    #
    def to_pdf_by_question(filename)

      #Retrieve a list of all valid attempts
      attempts = valid_attempts.sort_by! { |x| x.question_id }

      #And convert the list of attempts to a single PDF.
      self.class.pdf_from_attempt_collection(filename, attempts)

    end

    #
    # Returns an array of all of the _valid_ question attempts in this assessment.
    #
    def valid_attempts
      @attempts.reject { |x| x.missing_identifiers? }
    end

    #
    # Returns an array of all of the _invalid_ question attempts in this assessment.
    # 
    def invalid_attempts
      @attempts.select { |x| x.missing_identifiers? }
    end

    #
    # Creates a single PDF file from an ordered collection of attempts.
    #
    def self.pdf_from_attempt_collection(filename, attempts)

      #Generate a PDF which contains each of the requested images, in order.
      Prawn::Document.generate(filename, :skip_page_creation => true) do

        attempts.each do |attempt|

          #Convert the given attempt to a JPEG image.
          attempt_image = attempt.to_jpeg

          #Start a new page which is exactly sized to the image.
          start_new_page(:size => [attempt_image.columns, attempt_image.rows], :margin => 0)

          #Convert the image to 
          raw_image = StringIO.new(attempt_image.to_blob)
          image(raw_image)

        end
      end

    end

      

  end

end
