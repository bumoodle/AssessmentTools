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
   
        #convert the image into an ImageMagick object
        #image = Magick::Image::from_blob(image).first
        unless image.is_a? Magick::Image
          image = Magick::Image.read(image).first
        end

        #convert the image into black-and-white using a mid-range threshold
        image = image.threshold(Magick::QuantumRange * threshold)

        #and remove the ImageMagick wrapper
        image.format = 'JPEG' 

        #wrap the image in a ZBar parsing class
        self.from_jpeg(image.to_blob)
    end
  end
end

module Assessment

  #Represents a paper version of a Moodle quesion attempt.
  class QuestionAttempt

    #Regular expression used to parse Question Identifier codes
    QUESTION_ID = /([0-9]+)\|([0-9]+)\|([0-9]+)/

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
    def initialize(copy_id, question_id, attempt_id, images, grade = 0, rotation = 0)
      @copy_id = copy_id
      @question_id = question_id
      @attempt_id = attempt_id
      @images = images
      @grade = grade
      @rotation = rotation
    end

    # Returns the proper Moodle-uploadable filename for then given Question Attempt.
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
    # TODO: remove!
    #
    def rename_for_upload!(extension=nil)
      #rename each of the images in the Question Attempt
      @images.each_with_index { |image, i| File::rename(image[:path], filename_for_upload(i)) }
    end


    #
    # Converts the given attempt to a single, JPEG image.
    #
    def to_jpeg(footer=nil, scale=1, density=300, quality=85)
    
      #Create a new collection of ImageMagick images...
      image_list = Magick::ImageList.new
      
      @images.each do |image_info|
       
       #Load each of the images into memory...
        image = Magick::Image.read(image_info[:path]) {self.density = density; self.quality = quality }
        image = image.first

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
      unless footer.nil?
        image_list << Magick::Image.read(footer).first
      end

      #Merge all of the images in the list into a single, tall JPEG.
      image = image_list.append(true)
      image.format = 'JPEG'

      #And return the image.
      image

    end


    def self.from_image(image, threshold=0.65)
        self.from_images([image])
    end

    # Creates a new QuestionAttempt object from a set of images.
    #
    # @param [Array, string] A filename, or list of filenames, which contain images to be parsed as question attempts.
    #
    def self.from_images(source_images, threshold=0.65)
     
      #initialize the QA's identifiers to nil
      copy_id, question_id, attempt_id = nil, nil, nil

      #and create a list of possible grades
      possible_grades = (1..10).to_a

      #Create a new array, which will store information regarding each image.
      images = []

      #process each image in our array
      source_images.each do |image_file|

        image = barcodes = nil

        #Read the image, and extract any releavnt barcodes using ZBar
        quietly do 
          image = Magick::Image.read(image_file).first
          barcodes = ZBar::Image.from_color_jpeg(image, threshold).process
        end

        #Assume a rotation of 0, unless otherwise specified
        rotation = nil

        #process each of the extracted barcodes
        barcodes.each do |code|

          #attempt to match the barcode against our Question ID pattern
          identifier = code.data.match(QUESTION_ID)
          
          #if it matches the identifier pattern
          if identifier

            #use it to determine the QA's identifiers
            copy_id, question_id, attempt_id = identifier[1], identifier[2], identifier[3]

            #use its _location_ to determine this image's rotation, if it's not already known
            rotation ||= rotation_from_top_right_location(image.columns, image.rows, code.location)


          end

          #attempt ot match the barcode against our grade disqualifier pattern
          grader = code.data.match(GRADE_DISQUALIFIER)

          #if the data matches the disqualifier pattern
          if grader
   
            #get the value of the grade that was disqualified
            grade = Integer(grader[1])

            #and remove the disqualified grade from the array of possible grades
            possible_grades.delete(grade)

          end

          #If we have a top-of-the-page identification barcode, use it to get the orientation
          if code.symbology == 'CODE-128'

            #its _location_ to determine this image's rotation
            rotation ||= rotation_from_top_center_location(image.columns, image.rows, code.location)

            #and, if we don't already have a usage id, use it
            copy_id ||= code.data

          end
        end

        #If we weren't able to figure out the rotation, fall back on false.
        rotation ||= 0

        #Add the image to our collection of images.
        images << { :path => image_file, :rotation => rotation, :width => image.columns, :height => image.rows }

      end

      #if we were able to find a grade, then use it; otherwise, set a grade of nil
      grade = (possible_grades.count == 1) ? possible_grades[0] : nil

      #Create a new QuestionAttempt object from the parsed data 
      return self.new(copy_id, question_id, attempt_id, images, grade) 

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
