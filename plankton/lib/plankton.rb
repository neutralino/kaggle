require 'digest/md5'
require 'matrix'
require 'descriptive_statistics'
require 'rmagick'
require 'vips'

# a Plankton object extracts relevant features from the raw image
# upon instantiation.  The raw image is discraded after initialization
# to conserve memory
class Plankton
  FEATURES = [:size, :n_pixels, :whiteness, :centroid, :arspread, :n_constituents]

  attr_accessor :name, :subclass_name, :raw_image_digest,
                :size, :n_pixels, :whiteness, :centroid, :arspread, :n_constituents

  def initialize(name, subclass_name, filename)
    @name = name
    @subclass_name = subclass_name
    raw_image = Magick::Image.read(filename).first.quantize(256, Magick::GRAYColorspace)
    @raw_image_digest = Digest::MD5.hexdigest raw_image.export_pixels.join
    @size = compute_size(raw_image)
    @n_pixels = compute_n_pixels(raw_image)
    @whiteness = compute_whiteness(raw_image)
    @centroid  = compute_centroid(raw_image)
    @arspread  = compute_arspread(raw_image)
    vips_image = VIPS::Image.new(filename)
    @n_constituents = compute_n_constituents(vips_image)
  end

  def compute_size(raw_image)
    raw_image.columns*raw_image.rows
  end

  def compute_n_pixels(raw_image)
    raw_image_pixels = raw_image.get_pixels(0,0,raw_image.columns,raw_image.rows).map { |pixel| pixel.intensity }
    raw_image_pixels.select{|pixel| remap_intensity(pixel)>0}.size
  end

  def compute_whiteness(raw_image)
    raw_image_pixels = raw_image.get_pixels(0,0,raw_image.columns,raw_image.rows).map { |pixel| pixel.intensity }
    mean_intensity = raw_image_pixels.mean
    processed_image = raw_image.white_threshold(mean_intensity).black_threshold(mean_intensity)
    processed_image.get_pixels(0,0,processed_image.columns,processed_image.rows).map{|pixel| pixel.intensity}.mean/65535
  end

  def compute_centroid(raw_image)
    raw_image_pixels = raw_image.get_pixels(0,0,raw_image.columns,raw_image.rows).map{|pixel| pixel.intensity}
    mean_intensity = raw_image_pixels.mean
    processed_image = raw_image.white_threshold(mean_intensity)
    n_columns, n_rows = processed_image.columns, processed_image.rows
    v_center = Vector[0.5, 0.5]

    proc_image_array = processed_image.get_pixels(0, 0, n_columns, n_rows).map{|pixel| remap_intensity(pixel.intensity)}
    centroid_x = 0
    centroid_y = 0
    num_non_zero_points = 0
    proc_image_array.each_with_index do |element, index|
      column = index % n_columns
      row = index.to_i / n_columns
      if element > 0
        num_non_zero_points += 1
        centroid_x += column
        centroid_y += row
      end
    end

    if(num_non_zero_points > 0)
      centroid_x = centroid_x.to_f / num_non_zero_points.to_f
      centroid_y = centroid_y.to_f / num_non_zero_points.to_f
    else
      return 0
    end

    v_norm_centroid = Vector[centroid_x/n_columns.to_f, centroid_y/n_rows.to_f]
    v_rel_centroid = v_norm_centroid - v_center
    v_rel_centroid.norm
  end

  def compute_arspread(raw_image)
    raw_image_pixels = raw_image.get_pixels(0,0,raw_image.columns,raw_image.rows).map{|pixel| pixel.intensity}
    mean_intensity = raw_image_pixels.mean
    processed_image = raw_image.white_threshold(mean_intensity).white_threshold(mean_intensity/2)
    aspect_ratios = []
    (0..180).step(5) do |angle|
      rotated_image = processed_image.rotate(angle).trim
      ratio = rotated_image.columns / rotated_image.rows
      aspect_ratios.push ratio
    end
    aspect_ratios.standard_deviation
  end

  def compute_n_constituents(image)
    image_invert = image.invert

    #threshold it
    mean = image_invert.stats.first[4]
    image_thresholded = image_invert.more(mean)

    #dilute it
    mask = [
      [255, 255, 255],
      [255, 255, 255],
      [255, 255, 255]
    ]
    image_diluted = image_thresholded.dilate(mask)

    #label the segments
    image_labeled, segments = image_diluted.label_regions

    pixel_array = []
    image_labeled.each_pixel{|value, x, y| pixel_array.push value}

    segment_count = pixel_array.each_with_object(Hash.new(0)) { |word,counts| counts[word] += 1 }
    # exclude segments that are too small (most likely noise)
    # also exclude the background (which is otherwise counted as one segment)
    n_constituents = segment_count.select{|_, v| v>100}.size - 1
    return n_constituents
  end

  # this will do the transformation:
  # white = 65535 to 0
  # black = 0 to 1
  def remap_intensity(intensity)
    intensity.to_f/65535.0 * (-1.0) + 1
  end

end
