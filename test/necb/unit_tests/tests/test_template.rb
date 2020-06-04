require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/create_doe_prototype_helper'
require 'json'

class YourTestName_Test < Minitest::Test

  def test_what_are_you_testing()

    # File paths.
    @output_folder = File.join(__dir__, 'output/test_daylight_sensor')
    @expected_results_file = File.join(__dir__, '../expected_results/daylighting_expected_results.json')
    @test_results_file = File.join(__dir__, '../expected_results/daylighting_test_results.json')
    @sizing_run_dir = File.join(@output_folder, 'sizing_folder')

    # Intial test condition
    @test_passed = true

    #Range of test options.
    @templates = ['NECB2011']
    @building_types = ["FullServiceRestaurant"]
    @epw_files = ['CAN_AB_Banff.CS.711220_CWEC2016.epw']
    @primary_heating_fuels = ['DefaultFuel']
    @dcv_types = ['No DCV']

    # Test results storage array.
    @test_results_array = []

    @templates.sort.each do |template|
      @epw_files.sort.each do |epw_file|
        @building_types.sort.each do |building_type|
          @primary_heating_fuels.sort.each do |primary_heating_fuel|
            @dcv_types.sort.each do |dcv_type|

              # make an empty model
              model = OpenStudio::Model::Model.new
              #set up basic model.
              standard = Standard.build(template)

              #loads osm geometry and spactypes from library.
              model = standard.load_building_type_from_library(building_type: building_type)

              # this runs the step in the model. You can remove steps after what you want to test if you wish to make the test run faster.
              standard.apply_weather_data(model: model, epw_file: epw_file)
              standard.apply_loads(model: model)
              standard.apply_envelope(model: model)
              standard.apply_fdwr_srr_daylighting(model: model)
              standard.apply_auto_zoning(model: model, sizing_run_dir: @sizing_run_dir)
              standard.apply_systems(model: model, primary_heating_fuel: primary_heating_fuel, sizing_run_dir: @sizing_run_dir, dcv_type: dcv_type)
              standard.apply_standard_efficiencies(model: model, sizing_run_dir: @sizing_run_dir)
              model = standard.apply_loop_pump_power(model: model, sizing_run_dir: @sizing_run_dir)
              standard.model_add_daylighting_controls(model)

              # gather results from this iteration and store it into the test_result_array.
              # for example:
              result = {}
              result['template'] = template
              result['epw_file'] = epw_file
              result['building_type'] = building_type
              result['primary_heating_fuel'] = primary_heating_fuel
              result['dcv_type'] = dcv_type
              result['dcv_value_to_validate'] = 123456
              #then store it into the array that contains all the scenario results.
              @test_results_array << result
            end
          end
        end
      end
    end
    # Save test results to file.
    File.open(@test_results_file, 'w') {|f| f.write(JSON.pretty_generate(@test_results_array))}

    # Compare results
    compare_message = ''
    # Check if expected file exists.
    if File.exist?(@expected_results_file)
      # Load expected results from file.
      @expected_results = JSON.parse(File.read(@expected_results_file))
      if @expected_results.size == @test_results_array.size
        # Iterate through each test result.
        @expected_results.each_with_index do |expected, row|
          # Compare if row /hash is exactly the same.
          if expected != @test_results_array[row]
            #if not set test flag to false
            @test_passed = false
            compare_message << "\nERROR: This row was different expected/result\n"
            compare_message << "EXPECTED:#{expected.to_s}\n"
            compare_message << "TEST:    #{@test_results_array[row].to_s}\n\n"
          end
        end
      else
        assert(false, "#{@expected_results_file} # of rows do not match the #{@test_results_array}..cannot compare")
      end
    else
      assert(false, "#{@expected_results_file} does not exist..cannot compare")
    end
    puts compare_message
    assert(@test_passed, "Error: This test failed to produce the same result as in the #{@expected_results_file}\n")
  end

end
