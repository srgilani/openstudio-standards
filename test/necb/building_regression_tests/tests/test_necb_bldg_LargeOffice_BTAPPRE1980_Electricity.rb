require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/create_doe_prototype_helper'
require_relative '../../../helpers/compare_models_helper'
require_relative '../resources/regression_helper'

class Test_LargeOffice_BTAPPRE1980_Electricity < NECBRegressionHelper
  def setup()
    super()
  end
  def test_BTAPPRE1980_LargeOffice_regression_Electricity()
    result, diff = create_model_and_regression_test(building_type: 'LargeOffice',primary_heating_fuel: 'Electricity', epw_file:  'CAN_AB_Calgary.Intl.AP.718770_CWEC2016.epw',template: 'BTAPPRE1980', run_simulation: @run_simulation)
    if result == false
      puts "JSON terse listing of diff-errors."
      puts diff
      puts "Pretty listing of diff-errors for readability."
      puts JSON.pretty_generate( diff )
      puts "You can find the saved json diff file here test/necb/regression_models/LargeOffice-BTAPPRE1980-#\{@Electricity_location\%>.epw_diffs.json"
      puts "outputing errors here. "
      puts diff["diffs-errors"] if result == false
    end
    assert(result, diff)
  end
end