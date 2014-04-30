#!/usr/bin/env ruby

require 'zbar'
require 'RMagick'

THRESHOLD = 0.7
TOP_OF_QUESTION_PADDING = 5 

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

#
# Determines the points at which an image should be cut.
#
def get_cut_points(barcodes)

  #Only use identifying QR codes to generate cut points.
  codes = barcodes.select { |code| code.symbology == "QR-Code" }

  #Ensure codes are sorted by their height on the page.
  codes.sort_by! { |code| code.location.first.last }

  #Don't use the first code, as there's no need to separate the top of the page.
  codes.shift
  
  #Extract the cut points...
  return codes.map { |code| code.location.first.last - TOP_OF_QUESTION_PADDING }
end

#
# Returnst he dimensions for each 
#
def get_image_dimensions(cut_points, image)

  last_top = 0
  dimensions = []

  #Add a single image ending at each cut point...
  cut_points.each do |point|
    dimensions << [0, last_top, image.columns, point - last_top]
    last_top = point 
  end

  #... and a single image from the last cut point to the end.
  dimensions << [0, last_top, image.columns, image.rows - last_top]

  dimensions

end

puts

#For each image specified on the input...
ARGV.each_with_index do |filename, index|

  print "\rProcessing image #{index}/#{ARGV.count}. (#{(index.to_f/ARGV.count*100).round(2)}%)"

  image = barcodes = nil

  #Get the image from the filename, and extract all QR codes from it.
  quietly do
    image    = Magick::Image.read(filename).first
    barcodes = ZBar::Image.from_color_jpeg(image, THRESHOLD).process
  end

  #Split the image into questions.
  cut_points = get_cut_points(barcodes)
  dimensions = get_image_dimensions(cut_points, image)

  #Create an image that starts and ends at each pair of dimensions.
  dimensions.each_with_index do |dimension, index|
 
    #Create a new filename for the image...
    new_filename = File.basename(filename).sub(/\.[^.]+\z/, "-#{index}.jpg")

    #Extract the subimage, and write it to a file...
    subimage = image.crop(*dimension)
    subimage.write(new_filename)
    subimage.destroy!

  end

  image.destroy!

end
