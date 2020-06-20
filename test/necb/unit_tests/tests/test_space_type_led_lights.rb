require_relative '../../../helpers/minitest_helper'



# This class will perform tests that are Spacetype dependant, Test model will be created
# to specifically test aspects of the NECB2011 code that are Spacetype dependant. 
class NECB2011DefaultSpaceTypesTests < Minitest::Test
  #Standards
  Templates = ['NECB2011']#['NECB2011', 'NECB2015', 'NECB2017']#,'90.1-2004', '90.1-2007', '90.1-2010', '90.1-2013'] 'BTAPPRE1980'


  def setup()
    @file_folder = __dir__
    @test_folder = File.join(@file_folder, '..')
    @root_folder = File.join(@test_folder, '..')
    @resources_folder = File.join(@test_folder, 'resources')
    @expected_results_folder = File.join(@test_folder, 'expected_results')
    @test_results_folder = @expected_results_folder
    @top_output_folder = "#{@test_folder}/output/"
  end
  # Tests to ensure that the NECB default schedules are being defined correctly.
  # This is not for compliance, but for archetype development. 
  # @return [Bool] true if successful. 
  def test_schedule_type_defaults()
    #Create new model for testing. 
    @model = OpenStudio::Model::Model.new
    #Create only above ground geometry (Used for infiltration tests) 
    length = 100.0; width = 100.0 ; num_above_ground_floors = 1; num_under_ground_floors = 0; floor_to_floor_height = 3.8 ; plenum_height = 1; perimeter_zone_depth = 4.57; initial_height = 10.0
    BTAP::Geometry::Wizards::create_shape_rectangle(@model,length, width, num_above_ground_floors,num_under_ground_floors, floor_to_floor_height, plenum_height,perimeter_zone_depth, initial_height )
#    standard = Standard.build('NECB2015')

    header_output = ""
    output = ""
    #Iterate through all spacetypes/buildingtypes. 
    Templates.each do |template|
      #Get spacetypes from googledoc.
      standard = Standard.build(template)

      search_criteria = {
        "template" => template,
      }
      # lookup space type properties
      standards_table = standard.standards_data['space_types']
      standard.model_find_objects(standards_table, search_criteria).each do |space_type_properties|
        header_output = ""
        # Create a space type
        st = OpenStudio::Model::SpaceType.new(@model)
        st.setStandardsBuildingType(space_type_properties['building_type'])
        st.setStandardsSpaceType(space_type_properties['space_type'])
        st.setName("#{template}-#{space_type_properties['building_type']}-#{space_type_properties['space_type']}")
        standard.space_type_apply_rendering_color(st)
        standard.model_add_loads(@model,'LED',1.0)
  
        #Set all spaces to spacetype
        @model.getSpaces.each do |space|
          space.setSpaceType(st)
        end
          

        #Get handle for space. 
        space = @model.getSpaces[0]
        space_area = space.floorArea #m2
          
  
        #Lights #TODO: This should be discussed as occSensLPDfactor has been considered inside lighing function
        total_lpd = []
        lpd_sched = []
        occSensLPDfactor = 1.0
        if template == "NECB2011"
          # NECB2011 space types that require a reduction in the LPD to account for
          # the requirement of an occupancy sensor (8.4.4.6(3) and 4.2.2.2(2))
          reduceLPDSpaces = ["Classroom/lecture/training", "Conf./meet./multi-purpose", "Lounge/recreation",
            "Conf./meet./multi-purpose", "Washroom-sch-A",
            "Washroom-sch-B", "Washroom-sch-C", "Washroom-sch-D", "Washroom-sch-E", "Washroom-sch-F", "Washroom-sch-G",
            "Washroom-sch-H", "Washroom-sch-I", "Dress./fitt. - performance arts", "Locker room", "Retail - dressing/fitting"]
          space_type_name = st.standardsSpaceType.get
          if reduceLPDSpaces.include?(space_type_name)
            occSensLPDfactor = 0.9
          elsif ( (space_type_name=='Storage area' && space_area < 100) || 
               (space_type_name=='Storage area - refrigerated' && space_area < 100) || 
               (space_type_name=='Office - enclosed' && space_area < 25) )
            # Do nothing! In this case, we use the duplicate space type name appended with " - occsens"!
          end
        end
        st.lights.each {|light| total_lpd << light.powerPerFloorArea.get * occSensLPDfactor ; lpd_sched << light.schedule.get.name}
        assert(total_lpd.size <= 1 , "#{total_lpd.size} light definitions given. Expecting <= 1.")
        

        header_output << "SpaceType,"
        output << "#{st.name},"
        #standardsSpaceType
        header_output << "StandardsSpaceType,"
        output << "#{st.standardsSpaceType.get},"
        #standardsBuildingType
        header_output << "standardsBuildingType,"
        output << "#{st.standardsBuildingType.get},"
          
        #lights
        if total_lpd[0].nil?
          total_lpd[0] = 0.0
          lpd_sched[0] = "NA"
        end
        header_output << "Lighting Power Density (W/m2),"
        output << "#{total_lpd[0].round(4)},"
        header_output << "Lighting Schedule,"
        output << "#{lpd_sched[0]},"
        

        #End line
        header_output << "\n"
        output << "\n"
            
        #remove space_type (This speeds things up a bit.
        st.remove

      end #loop spacetypes
      puts template

    end #loop Template
    # puts output

    #Write test report file.
    test_result_file = File.join( @test_results_folder,'space_type_led_lights_test_results.csv')
    File.open(test_result_file, 'w') {|f| f.write(header_output + output) }

    #Test that the values are correct by doing a file compare.
    expected_result_file = File.join(@expected_results_folder,'space_type_led_lights_expected_results.csv')
    b_result = FileUtils.compare_file(expected_result_file , test_result_file )
    assert( b_result,
      "Spacetype test results do not match expected results! Compare/diff the output with the stored values here #{expected_result_file} and #{test_result_file}"
    )
  end 
  
end

