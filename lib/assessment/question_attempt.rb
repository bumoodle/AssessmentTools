require 'zbar'
require 'RMagick'

#
# Extend the ZBar module to include better handling of Color images.
#
module ZBar
  class Image

    # Creates a ZBar Image from a JPEG image; enhanced for recognizing Black-and-White
    # barcodes in color JPEG images. 
    #
    # @param [String, File] image The image file to be wrapped with a ZBar Image object.
    # @param [Float] image The "darkness" threshold a pixel must meet to be considered black. Pixels which 
    #                      do not meed this threshold are considered white.
    # 
    # @return [Image] The ZBar Image object that wraps the given image.
    #
    def self.from_color_jpeg(image, threshold=0.65)
  
        magick_image_provided = image.is_a? Magick::Image

        #If necessary, convert the image into an ImageMagick object.
        unless magick_image_provided
          image = Magick::Image.read(image).first
        end

        #convert the image into black-and-white using a mid-range threshold
        image = image.threshold(Magick::QuantumRange * threshold)

        #and remove the ImageMagick wrapper
        image.format = 'JPEG' 

        #wrap the image in a ZBar parsing class
        self.from_jpeg(image.to_blob)

    ensure
       
        #If we created an ImageMagick image during this routine,
        #ensure that it's properly destroyed.
        image.destroy! unless magick_image_provided

    end
  end
end

module Assessment

  #Represents a paper version of a Moodle quesion attempt.
  class QuestionAttempt

    #Regular expression used to parse Question Identifier codes
    QUESTION_ID = /(?<copy_id>[0-9]+)\|(?<question_id>[0-9]+)\|(?<attempt_id>[0-9]+)/

    #Regular expression usd to parse Grade Disqualifier codes
    GRADE_DISQUALIFIER = /GRADE([0-9]+)/

    #allow the grade to be read/written externally
    attr_accessor :grade
    attr_accessor :images

    #accessors for the identifiers
    attr_accessor :copy_id
    attr_accessor :question_id
    attr_accessor :attempt_id

    #accessor for the rotation
    attr_accessor :rotation

    # Initializes a new Question Attempt object.
    def initialize(copy_id, question_id, attempt_id, images, grade = nil, rotation = 0)
      @copy_id = copy_id
      @question_id = question_id
      @attempt_id = attempt_id
      @images = images
      @grade = grade
      @rotation = rotation
    end

    # Returns the proper Moodle-uploadable filename for then given Question Attempt.
    # TODO: Perhaps move me, for decoupling?
    #
    # @param [Integer] page The page number to be appended to the filename.
    # @param [String] extension The extension to be appended to the filename, including the leading dot, or nil to use the same filetype as the original image.
    def filename_for_upload(page=0, extension=nil, directory=nil)
      
      #get the original filename used to represent the QA
      original_filename = @images[page][:path]

      #if the extension has not already been set, use the extension from the original filename
      extension ||= File::extname(original_filename)

      #if the directory has not already been set, use the same directory as the original file
      directory ||= File::dirname(original_filename)

      #return the new filename
      "#{directory}/U#{@copy_id}_Q#{@question_id}_A#{@attempt_id}_G#{@grade}_P#{page}#{extension}"
    end

    #
    # Returns true iff the given image has a grade associated with it.
    #
    def graded?
      not @grade.nil?
    end


    #
    # Returns the maximum dimensions of any given page contained in this attempt.
    #
    def maximum_dimensions

      #Get the maximum width and height
      max_width = @images.map { |i| i[:width] }.max
      max_height = @images.map { |i| i[:height] }.max

      #And return them.
      return max_width, max_height

    end

    #
    # Returns true iff at least one question identifier is missing.
    #
    def missing_identifiers?
      @copy_id.nil? or @question_id.nil? or @attempt_id.nil?
    end

    #
    # Converts the given image into an array, suitable for use in a CSV.
    #
    def to_a
      [@copy_id, @question_id, @attempt_id, @grade]
    end

    #
    # Converts the given attempt to a single image.
    #
    def to_image(scale=1, density=300, format='JPEG', footer=nil, quality= 85)

      #Create a new collection of ImageMagick images...
      image_list = Magick::ImageList.new
      
      @images.each do |image_info|
      
        image = nil

        #Load each of the images into memory...
        self.class.quietly do
          image = Magick::Image.read(image_info[:path]) {self.density = density if density; self.quality = quality if quality }
          image = image.first
        end

        #... rotate the given image, so it's upright...
        image.rotate!(image_info[:rotation])

        #If a scale has been provided, use it.
        unless scale == 0 || scale == 1
          image.scale!(scale)
        end

        #and add it to our image list.
        image_list << image

      end

      #If a footer was provided, add it to the image.
      image_list << Magick::Image.read(footer).first unless footer.nil?

      #Merge all of the images in the list into a single, tall JPEG.
      image = image_list.append(true)
      image.format = format unless image.format.nil?

      #Destroy the original ImageList, freeing memory.
      image_list.destroy!

      #And return the image.
      image


    end

    #
    # Returns true iff the given question has a grade of nil.
    #
    def ungraded?
      @grade.nil?
    end


    #
    # Creats a new QuestionAttempt object from a singl eimage.
    #
    #
    def self.from_image(image, autorotate=true, threshold=0.65)
        self.from_images([image], autorotate, threshold)
    end


    # Creates a new QuestionAttempt object from a set of images.
    #
    # @param [Array, string] A filename, or list of filenames, which contain images to be parsed as question attempts.
    #
    def self.from_images(source_images, autorotate=true, threshold=0.65, maximum_grade=10)
     
      #initialize the QA's identifiers to nil
      identifiers = {}

      #and create a list of possible grades
      possible_grades = (0..maximum_grade).to_a

      #Process each image in the file.
      images = []
      source_images.each do |image_file|
          image = barcodes  = nil

          #Read the image, and extract any releavnt barcodes using ZBar
          quietly do 
            image    = Magick::Image.read(image_file).first
            barcodes = ZBar::Image.from_color_jpeg(image, threshold).process
          end

          #TODO: Handle multiple-barcode images. 

          #process each of the extracted barcodes
          barcodes.each do |code|

            #If this is a question identifier, use the given barcode to identify the given attempt.
            identifiers.update(extract_identifiers_from_QR_match(code, image))

            #If this is a grade disqulaifier, remove the grade from the list of possible grades.
            possible_grades.delete(extract_grade_disqualifier(code))

            #If this is a top 
            identifiers.update(extract_identifiers_from_top_barcode(code, image))

          end

          #If we weren't able to figure out the rotation, fall back on some approximation of portrait.
          identifiers[:rotation] ||= (image.rows > image.columns) ? 0 : 90

          #If autorotate is off, ignore the computed rotation.
          identifiers[:rotation] = 0 unless autorotate

          #Add the image to our collection of images.
          images << { :path => File.absolute_path(image_file), :rotation => identifiers[:rotation], :width => image.columns, :height => image.rows }

          #Clean up after RMagick.
          image.destroy! if image
      end

      #if we were able to find a grade, then use it; otherwise, set a grade of nil.
      grade = (possible_grades.count == 1) ? possible_grades[0] : nil

      #Create a new QuestionAttempt object from the parsed data 
      return self.new(identifiers[:copy_id], identifiers[:question_id], identifiers[:attempt_id], images, grade) 

    end

    #
    # Extracts any identifying information from a QR code match, if possible. 
    # This method can be called with any ZBar match; if the match isn't a question
    # identifier, it will return nil.
    #
    # @param code The ZBar barcode scan to be processed.
    # @param image [Magick::Image] An optional ImageMagick image, which will be used to determine
    #     how the given image should be rotated.
    #
    # @return A hash including any data fields extracted from the QR code.
    #
    def self.extract_identifiers_from_QR_match(code, image=nil)

      #Attempt to match the barcode against our Question ID pattern.
      identifiers = code.data.match(QUESTION_ID)

      #If we weren't able to match the data, return an empty hash.
      return {} if identifiers.nil?
      
      #Extract each of the identifiers from the barcode.
      capture_names = identifiers.names.map { |name| name.to_sym }
      identifiers = Hash[capture_names.zip(identifiers.captures)]

      #Attempt to determine how the image should be rotated, based on the QR code's location.
      if image
        identifiers[:rotation] = rotation_from_top_right_location(image.columns, image.rows, code.location) 
      end
    
      identifiers

    end


    #
    # Attempts to extract a "grade disqualifier" from the given barcode,
    # which represents an unfilled grading bubble.
    #
    # @param code The ZBar barcode scan to be processed.
    #
    # @return The integer grade to be disqualified, or nil if this was not a valid grade disqualifier.
    #
    def self.extract_grade_disqualifier(code) 

      #Determine if the barcode matches our grade disqualifier pattern.
      grader = code.data.match(GRADE_DISQUALIFIER)

      #If it didn't; return nil-- otherwise, return the grade.
      grader.nil?() ? nil : grader[1].to_i

    end


    # Extracts any identifying information from a top barcode (CODE-128) match.
    # This method can be called with any ZBar match; if the match isn't a question
    # identifier, it will return nil.
    #
    # @param code The ZBar barcode scan to be processed.
    # @param image [Magick::Image] An optional ImageMagick image, which will be used to determine
    #     how the given image should be rotated.
    #
    # @return A hash including any data fields extracted from the QR code.
    #
    def self.extract_identifiers_from_top_barcode(code, image=nil)

      return {} unless code.symbology == 'CODE-128'

      #Extract the copy ID from the top barcode.
      identifiers  = { :copy_id => code.data }

      #If an image was provided, use it to extract the amount by which
      #the page will need to be rotated.
      if image
        identifiers[:rotation] = rotation_from_top_center_location(image.columns, image.rows, code.location)
      end
      
      identifiers

    end


    def self.rotation_from_top_right_location(width, height, locations)

      #Compute the center-point of the detected barcode.
      left = locations.inject(0.0) { |sum, i| sum + i[0] } / locations.size
      top = locations.inject(0.0) { |sum, i| sum + i[1] } / locations.size

      #And find the X/Y dimension of the centerpoint.
      #Note the integer division.
      h_center = width / 2
      v_center = height / 2

      #Compute the rotation based on which "quadrant" the barcode's center lies in.
      if    left <  h_center && top >  v_center 
        0
      elsif left <  h_center && top <= v_center
        90
      elsif left >= h_center && top <= v_center
        180
      else 
        270 
      end 

    end


    def self.rotation_from_top_center_location(width, height, locations)

      #Compute the center-point of the detected barcode.
      left = locations.inject(0.0) { |sum, i| sum + i[0] } / locations.size
      top = locations.inject(0.0) { |sum, i| sum + i[1] } / locations.size
      
      #Compute the distance from the bottom and from the right. 
      bottom = height - top
      right = width - left

      #Select how many times the page needs to be rotated so the ID
      #is on top.
      case [top, left, bottom, right].min
        when top then 0
        when left then 90
        when bottom then 180
        else 270 
      end

    end


    #
    # Temporarily silences any writing to the standard output.
    # This is used to force the poorly-behaved GhostScript to behave nicely.
    #
    def self.quietly

      #Get a reference to the current handles to the standard output and error.
      orig_stdout = STDOUT.clone
      orig_stderr = STDERR.clone

      #Get a reference to a null file (e.g. /dev/null).
      null = File.open(File::NULL, 'w')

      #Redirect the standard streams to it.
      STDOUT.reopen(null)
      STDERR.reopen(null)

      #And call the relevant block of code.
      yield

    ensure
      #Once we're done restore the standard streams.
      STDOUT.reopen(orig_stdout)
      STDERR.reopen(orig_stderr)
    end


  end

end
