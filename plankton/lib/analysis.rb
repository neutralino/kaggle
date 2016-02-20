require 'logger'
require 'descriptive_statistics'
require_relative 'plankton'
require '/usr/lib/root/libRuby'

# Basic analysis class that will loop through all images in the training and
# testing set, compute the features, and create ntuples.
class Analysis
  def initialize
    @logger = Logger.new(STDOUT)
    @training_array = []                                       # list of all image filenames used for training
    @testing_array = []                                        # list of all image filenames used for testing
    @plankton_types = []                                       # plankton superclass names
    @lu_plankton_class = Hash.new{|hash, key| hash[key] = [] } # lookup table for the superclass of a plankton class
    @all_plankton = []                                         # each element is itself an array of plankton objects of a particular class
  end

  def load_dataset(input_file_name)
    array = []
    File.open(input_file_name, "r") do |f|
      f.each_line do |line|
        array.push line.chomp
      end
    end
    array
  end

  #  build a hash of the plankton identification classes
  def load_classification_table
    File.open(File.join(File.dirname(__FILE__),"data","plankton_types.txt"), "r") do |f|
      f.each_line do |line|
        @plankton_types.push line.chomp
      end
    end

    @plankton_types.each do |line|
      plankton_class = line.split("_")[0].to_sym
      @lu_plankton_class[plankton_class].push line
    end
    @lu_plankton_class
  end

  # load all images of a particular class into an array
  def load_class_of_plankton(class_name, files)
    class_files = []
    files.each do |file|
      class_files << file if file.include? (class_name+'/')
    end
    plankton_array = []
    class_files.each do |file|
      #look up the plankton superclass
      superclass_name = @lu_plankton_class.select { |key,value| value.include? (class_name)}.keys.first.to_s
      plankton_array << Plankton.new(class_name, superclass_name, file)
    end
    plankton_array
  end

  def get_features(plankton_array)
    feature_array = []
    plankton_array.each do |plankton|
      feature = yield(plankton)
      feature_array << feature
    end
    feature_array
  end

  # each element of the features_array is a feature_array
  # a feature_array consists of an array of values for each plankton class
  # Ex: features_array = [ [[1,2],[3,4],[1,1]] , [[1,6],[5,4],[5,5]] ]
  #                        whiteness             centroid
  #                         shrimp,fish          shrimp,fish
  #                          values                values
  def create_training_ntuple(features, features_arrays)
    @training_file = TFile.new("/tmp/ntuple_plankton_training.root","recreate")
    if features_arrays.first.size != @plankton_types.size
      @logger.error("features array is not the same size as the number of plankton types.")
      abort
    end

    @plankton_types.each_with_index do |type, index|
      ntuple = TNtuple.new("#{type}", "#{type}", features.join(":"))

      # retrieve all the features for a particular plankton type
      feature_set_plankton_type = features_arrays.map{|ar| ar[index]}
      n_images = feature_set_plankton_type.first.size

      unless n_images.zero?
        (0..n_images).each do |i|
          feature_set_values = feature_set_plankton_type.map{ |sa| sa[i] }
          ntuple.Fill(*feature_set_values)
        end
      end
    end
    @training_file.Write
  end

  def create_testing_ntuple(features, features_arrays)
    @testing_file = TFile.new("/tmp/ntuple_plankton_testing.root","recreate")
    ntuple = TNtuple.new("testclass", "testclass", features.join(":"))

    # retrieve all the features for a particular plankton type
    feature_set_plankton_type = features_arrays.map{|ar| ar[0]}
    n_images = feature_set_plankton_type.first.size
    unless n_images.zero?
      (0..n_images).each do |i|
        feature_set_values = feature_set_plankton_type.map{ |sa| sa[i] }
        ntuple.Fill(*feature_set_values)
      end
    end
    @testing_file.Write
  end

  def main
    @logger.info("Loading classification table")
    load_classification_table
    @logger.info("Loading list of training images for import")
    @training_array = load_dataset(File.join(File.dirname(__FILE__),"data","training_files.txt"))
    #@training_array = load_dataset(File.join(File.dirname(__FILE__),"data","training_file_iso_small.txt"))

    # Load the training images
    @logger.info("Loading training images")
    @plankton_types.each_with_index do |type, index|
      @logger.info("\t Loading plankton class #{index+1}/#{@plankton_types.size}: #{type}")
      @all_plankton.push load_class_of_plankton(type, @training_array)
    end
    total_training_images = @all_plankton.map{ |array| array.size }.sum.to_i
    @logger.info("Total training images loaded: #{total_training_images}")

    # Collect the training image features
    @logger.info("Extracting features...")
    features_training_all = Hash.new {|h,k| h[k]=[]}
    @all_plankton.each do |plankton_array|
      Plankton::FEATURES.each do |feature|
        features = get_features(plankton_array) { |plankton| plankton.method(feature).call }
        features_training_all[feature] << features
      end
    end
    @logger.info("Creating training ntuples")
    create_training_ntuple(Plankton::FEATURES.map{ |feature| feature.to_s}, features_training_all.values)


    # Load the testing images
    @logger.info("Loading list of testing images to import")
    #@testing_array = load_dataset(File.join(File.dirname(__FILE__),"data","training_file_iso_small.txt"))
    @testing_array = load_dataset(File.join(File.dirname(__FILE__),"data","testing_files.txt"))
    @logger.info("Loading testing images")
    test_plankton_array = []
    @testing_array.each do |file|
      test_plankton_array << Plankton.new("test_class", "test_superclass", file)
    end
    total_testing_images = test_plankton_array.size
    @logger.info("Total testing images loaded: #{total_testing_images}")

    #Collect testing image features
    features_testing_all = Hash.new {|h,k| h[k]=[]}
    Plankton::FEATURES.each do |feature|
      features = get_features(test_plankton_array) { |plankton| plankton.method(feature).call }
      features_testing_all[feature] << features
    end
    @logger.info("Creating testing ntuples")
    create_testing_ntuple(Plankton::FEATURES.map{ |feature| feature.to_s}, features_testing_all.values)

    @logger.info("All done!")
  end
end
