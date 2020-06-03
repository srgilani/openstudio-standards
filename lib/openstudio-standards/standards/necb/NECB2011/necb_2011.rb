# This class holds methods that apply NECB2011 rules.
# @ref [References::NECB2011]
class NECB2011 < Standard
  @template = self.new.class.name # rubocop:disable Style/ClassVars
  register_standard(@template)
  attr_reader :template
  attr_accessor :standards_data
  attr_accessor :space_type_map
  attr_accessor :space_multiplier_map

  def get_standards_table(table_name:)
    if @standards_data["tables"][table_name].nil?
      message = "Could not find table #{table_name} in database."
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.Standards.NECB', message)
    end
    @standards_data["tables"][table_name]
  end

  def get_standard_constant_value(constant_name:)
    puts "do nothing"
  end


  # Combine the data from the JSON files into a single hash
  # Load JSON files differently depending on whether loading from
  # the OpenStudio CLI embedded filesystem or from typical gem installation
  def load_standards_database_new()
    @standards_data = {}
    @standards_data["tables"] = {}

    if __dir__[0] == ':' # Running from OpenStudio CLI
      embedded_files_relative('../common', /.*\.json/).each do |file|
        data = JSON.parse(EmbeddedScripting.getFileAsString(file))
        if not data["tables"].nil? and data["tables"].first["data_type"] == "table"
          @standards_data["tables"] << data["tables"].first
        else
          @standards_data[data.keys.first] = data[data.keys.first]
        end
      end
    else
      path = "#{File.dirname(__FILE__)}/../common/"
      raise ('Could not find common folder') unless Dir.exist?(path)
      files = Dir.glob("#{path}/*.json").select {|e| File.file? e}
      files.each do |file|
        data = JSON.parse(File.read(file))
        if not data["tables"].nil?
          @standards_data["tables"] = [*@standards_data["tables"], *data["tables"]].to_h
        else
          @standards_data[data.keys.first] = data[data.keys.first]
        end
      end
    end


    if __dir__[0] == ':' # Running from OpenStudio CLI
      embedded_files_relative('data/', /.*\.json/).each do |file|
        data = JSON.parse(EmbeddedScripting.getFileAsString(file))
        if not data["tables"].nil? and data["tables"].first["data_type"] == "table"
          @standards_data["tables"] << data["tables"].first
        else
          @standards_data[data.keys.first] = data[data.keys.first]
        end
      end
    else
      files = Dir.glob("#{File.dirname(__FILE__)}/data/*.json").select {|e| File.file? e}
      files.each do |file|
        data = JSON.parse(File.read(file))
        if not data["tables"].nil?
          @standards_data["tables"] = [*@standards_data["tables"], *data["tables"]].to_h
        else
          @standards_data[data.keys.first] = data[data.keys.first]
        end
      end
    end
    # Write database to file.
    # File.open(File.join(File.dirname(__FILE__), '..', 'NECB2011.json'), 'w') {|f| f.write(JSON.pretty_generate(@standards_data))}

    return @standards_data
  end

  # Create a schedule from the openstudio standards dataset and
  # add it to the model.
  #
  # @param schedule_name [String} name of the schedule
  # @return [ScheduleRuleset] the resulting schedule ruleset
  # @todo make return an OptionalScheduleRuleset
  def model_add_schedule(model, schedule_name)

    super(model, schedule_name)
  end

  def get_standards_constant(name)
    object = @standards_data['constants'][name]

    if object.nil? or object['value'].nil?
      raise("could not find #{name} in standards constants database. ")
    end

    return object['value']
  end

  def get_standards_formula(name)
    object = @standards_data['formulas'][name]
    raise("could not find #{name} in standards formual database. ") if object.nil? or object['value'].nil?
    return object['value']
  end


  def initialize
    super()
    @template = self.class.name
    @standards_data = self.load_standards_database_new()
    self.corrupt_standards_database()
    #puts "loaded these tables..."
    #puts @standards_data.keys.size
    #raise("tables not all loaded in parent #{}") if @standards_data.keys.size < 24
  end

  def get_all_spacetype_names
    return @standards_data['space_types'].map {|space_types| [space_types['building_type'], space_types['space_type']]}
  end

  # Enter in [latitude, longitude] for each loc and this method will return the distance.
  def distance(loc1, loc2)
    rad_per_deg = Math::PI / 180 # PI / 180
    rkm = 6371 # Earth radius in kilometers
    rm = rkm * 1000 # Radius in meters

    dlat_rad = (loc2[0] - loc1[0]) * rad_per_deg # Delta, converted to rad
    dlon_rad = (loc2[1] - loc1[1]) * rad_per_deg

    lat1_rad, lon1_rad = loc1.map {|i| i * rad_per_deg}
    lat2_rad, lon2_rad = loc2.map {|i| i * rad_per_deg}

    a = Math.sin(dlat_rad / 2) ** 2 + Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlon_rad / 2) ** 2
    c = 2 * Math::atan2(Math::sqrt(a), Math::sqrt(1 - a))
    rm * c # Delta in meters
  end


  def get_necb_hdd18(model)
    max_distance_tolerance = 500000
    min_distance = 100000000000000.0
    necb_closest = nil
    epw = BTAP::Environment::WeatherFile.new(model.weatherFile.get.path.get)
    #this extracts the table from the json database.
    necb_2015_table_c1 = @standards_data['tables']['necb_2015_table_c1']['table']
    necb_2015_table_c1.each do |necb|
      next if necb['lat_long'].nil? #Need this until Tyson cleans up table.
      dist = distance([epw.latitude.to_f, epw.longitude.to_f], necb['lat_long'])
      if min_distance > dist
        min_distance = dist
        necb_closest = necb
      end
    end
    if (min_distance / 1000.0) > max_distance_tolerance and not epw.hdd18.nil?
      puts "Could not find close NECB HDD from Table C1 < #{max_distance_tolerance}km. Closest city is #{min_distance / 1000.0}km away. Using epw hdd18 instead."
      return epw.hdd18.to_f
    else
      puts "INFO:NECB HDD18 of #{necb_closest['degree_days_below_18_c'].to_f}  at nearest city #{necb_closest['city']},#{necb_closest['province']}, at a distance of #{'%.2f' % (min_distance / 1000.0)}km from epw location. Ref:necb_2015_table_c1"
      return necb_closest['degree_days_below_18_c'].to_f
    end
  end


  # This method is a wrapper to create the 16 archetypes easily.
  def model_create_prototype_model(template:,
                                   building_type:,
                                   epw_file:,
                                   debug: false,
                                   sizing_run_dir: Dir.pwd,
                                   primary_heating_fuel: 'DefaultFuel')

    model = load_building_type_from_library(building_type: building_type)
    return model_apply_standard(model: model,
                                epw_file: epw_file,
                                sizing_run_dir: sizing_run_dir,
                                primary_heating_fuel: primary_heating_fuel)
  end

  def load_building_type_from_library(building_type:)
    osm_model_path = File.absolute_path(File.join(__FILE__, '..', '..', '..', "necb/NECB2011/data/geometry/#{building_type}.osm"))
    model = BTAP::FileIO::load_osm(osm_model_path)
    model.getBuilding.setName(building_type)
    return model
  end


  # Created this method so that additional methods can be addded for bulding the prototype model in later
  # code versions without modifying the build_protoype_model method or copying it wholesale for a few changes.
  def model_apply_standard(model:,
                           epw_file:,
                           sizing_run_dir: Dir.pwd,
                           primary_heating_fuel: 'DefaultFuel',
                           dcv_type: "No DCV")
    apply_weather_data(model: model, epw_file: epw_file)
    apply_loads(model: model)
    apply_envelope(model: model)
    apply_fdwr_srr_daylighting(model: model)
    apply_auto_zoning(model: model, sizing_run_dir: sizing_run_dir)
    apply_systems(model: model, primary_heating_fuel: primary_heating_fuel, sizing_run_dir: sizing_run_dir, dcv_type: dcv_type)
    apply_standard_efficiencies(model: model, sizing_run_dir: sizing_run_dir)
    model = apply_loop_pump_power(model: model, sizing_run_dir: sizing_run_dir)
    model_add_daylighting_controls(model)
    return model
  end

  def apply_loads(model:)
    raise('validation of model failed.') unless validate_initial_model(model)
    raise('validation of spacetypes failed.') unless validate_and_upate_space_types(model)
    #this sets/stores the template version loads that the model uses.
    model.getBuilding.setStandardsTemplate(self.class.name)
    set_occ_sensor_spacetypes(model, @space_type_map)
    model_add_loads(model)
  end

  def apply_weather_data(model:, epw_file:)
    climate_zone = 'NECB HDD Method'
    # Fix EMS references. Temporary workaround for OS issue #2598
    model_temp_fix_ems_references(model)
    model.getThermostatSetpointDualSetpoints(&:remove)
    model.getYearDescription.setDayofWeekforStartDay('Sunday')
    model_add_design_days_and_weather_file(model, climate_zone, epw_file) # Standards
    model_add_ground_temperatures(model, nil, climate_zone)
  end

  def apply_envelope(model:,
                     properties: {
                         'outdoors_wall_conductance' => nil,
                         'outdoors_floor_conductance' => nil,
                         'outdoors_roofceiling_conductance' => nil,
                         'ground_wall_conductance' => nil,
                         'ground_floor_conductance' => nil,
                         'ground_roofceiling_conductance' => nil,
                         'outdoors_door_conductance' => nil,
                         'outdoors_fixedwindow_conductance' => nil
                     })
    raise('validation of model failed.') unless validate_initial_model(model)
    model_apply_infiltration_standard(model)
    model.getInsideSurfaceConvectionAlgorithm.setAlgorithm('TARP')
    model.getOutsideSurfaceConvectionAlgorithm.setAlgorithm('TARP')
    model_add_constructions(model)
    apply_standard_construction_properties(model: model, properties: properties)
    model_create_thermal_zones(model, @space_multiplier_map)
  end

  # Thermal zones need to be set to determine conditioned spaces when applying fdwr and srr limits.
  #     # fdwr_set/srr_set settings:
  #     # 0-1:  Remove all windows/skylights and add windows/skylights to match this fdwr/srr
  #     # -1:  Remove all windows/skylights and add windows/skylights to match max fdwr/srr from NECB
  #     # -2:  Do not apply any fdwr/srr changes, leave windows/skylights alone (also works for fdwr/srr > 1)
  #     # -3:  Use old method which reduces existing window/skylight size (if necessary) to meet maximum NECB fdwr/srr
  #     # limit
  #     # <-3.1:  Remove all the windows/skylights
  #     # > 1:  Do nothing
  def apply_fdwr_srr_daylighting(model:, fdwr_set: -1.0, srr_set: -1.0)
    apply_standard_window_to_wall_ratio(model: model, fdwr_set: fdwr_set)
    apply_standard_skylight_to_roof_ratio(model: model, srr_set: srr_set)
    # model_add_daylighting_controls(model) # to be removed after refactor.
  end

  def apply_standard_efficiencies(model:, sizing_run_dir:)
    raise('validation of model failed.') unless validate_initial_model(model)
    climate_zone = 'NECB HDD Method'
    raise("sizing run 1 failed! check #{sizing_run_dir}") if model_run_sizing_run(model, "#{sizing_run_dir}/plant_loops") == false
    # This is needed for NECB2011 as a workaround for sizing the reheat boxes
    model.getAirTerminalSingleDuctVAVReheats.each {|iobj| air_terminal_single_duct_vav_reheat_set_heating_cap(iobj)}
    # Apply the prototype HVAC assumptions
    model_apply_prototype_hvac_assumptions(model, nil, climate_zone)
    # Apply the HVAC efficiency standard
    model_apply_hvac_efficiency_standard(model, climate_zone)
  end

  def apply_loop_pump_power(model:, sizing_run_dir:)
    # Remove duplicate materials and constructions
    # Note For NECB2015 This is the 2nd time this method is bieng run.
    # First time it ran in the super() within model_apply_standard() method
    # model = return BTAP::FileIO::remove_duplicate_materials_and_constructions(model)
    return model
  end


  #this method will determine the vintage of NECB spacetypes the model contains. It will return nil if it can't
  # determine it.
  def determine_spacetype_vintage(model)
    #this code is the list of available vintages
    space_type_vintage_list = ['NECB2011', 'NECB2015', 'NECB2017', 'BTAPPRE1980', 'BTAP1980TO2010']
    #this reorders the list to do the current class first.
    space_type_vintage_list.insert(0, space_type_vintage_list.delete(self.class.name))
    #Set the space_type
    space_type_vintage = nil
    # get list of space types used in model and a mapped string.
    model_space_type_names = model.getSpaceTypes.map do |spacetype|
      [spacetype.standardsBuildingType.get.to_s + '-' + spacetype.standardsSpaceType.get.to_s]
    end
    #Now iterate though each vintage
    space_type_vintage_list.each do |template|
      #Create the standard object and get a list of all the spacetypes available for that vintage.
      standard_space_type_list = Standard.build(template).get_all_spacetype_names.map {|spacetype| [spacetype[0].to_s + '-' + spacetype[1].to_s]}
      # set array to contain unknown spacetypes.
      unknown_spacetypes = []
      # iterate though all space types that the model is using
      model_space_type_names.each do |space_type_name|
        # push unknown spacetypes into the array.
        unknown_spacetypes << space_type_name unless standard_space_type_list.include?(space_type_name)
      end
      if unknown_spacetypes.empty?
        #No unknowns, so return the template and don't bother looking for others.
        return template
      end
    end
    return space_type_vintage
  end

  # This method will validate that the space types in the model are indeed the correct NECB spacetypes names.
  def validate_and_upate_space_types(model)
    space_type_vintage = determine_spacetype_vintage(model)
    if space_type_vintage.nil?
      message = "These some of the spacetypes in the model are not part of any necb standard.\n  Please ensure all spacetype in model are correct."
      puts "Error: #{message}"
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.Standards.NECB', message)
      return false
    elsif space_type_vintage == self.class.name
      # the spacetype in the model match the version we are trying to create.
      # no translation neccesary.
      return true
    else
      #Need to translate to current vintage.
      no_errors = true
      st_model_vintage_string = "#{space_type_vintage}_space_type"
      bt_model_vintage_string = "#{space_type_vintage}_building_type"
      st_target_vintage_string = "#{self.class.name}_space_type"
      bt_target_vintage_string = "#{self.class.name}_building_type"
      space_type_upgrade_map = @standards_data['space_type_upgrade_map']
      model.getSpaceTypes.sort.each do |st|
        space_type_map = space_type_upgrade_map.detect {|row| (row[st_model_vintage_string] == st.standardsSpaceType.get.to_s) && (row[bt_model_vintage_string] == st.standardsBuildingType.get.to_s)}
        st.setStandardsBuildingType(space_type_map[bt_target_vintage_string].to_s.strip)
        raise('could not set buildingtype') unless st.setStandardsBuildingType(space_type_map[bt_target_vintage_string].to_s.strip)
        raise('could not set this') unless st.setStandardsSpaceType(space_type_map[st_target_vintage_string].to_s.strip)
        #Set name of spacetype to new name.
        st.setName("#{st.standardsBuildingType.get.to_s} #{st.standardsSpaceType.get.to_s}")
      end
      return no_errors
    end
  end


  # Determine whether or not water fixtures are attached to spaces
  def model_attach_water_fixtures_to_spaces?(model)
    return true
  end

  # Set the infiltration rate for this space to include
  # the impact of air leakage requirements in the standard.
  #
  # @return [Double] true if successful, false if not
  # @todo handle doors and vestibules
  def space_apply_infiltration_rate(space)
    # Remove infiltration rates set at the space type.
    infiltration_data = @standards_data['infiltration']
    unless space.spaceType.empty?
      space.spaceType.get.spaceInfiltrationDesignFlowRates.each(&:remove)
    end
    # Remove infiltration rates set at the space object.
    space.spaceInfiltrationDesignFlowRates.each(&:remove)

    exterior_wall_and_roof_and_subsurface_area = space_exterior_wall_and_roof_and_subsurface_area(space) # To do
    # Don't create an object if there is no exterior wall area
    if exterior_wall_and_roof_and_subsurface_area <= 0.0
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Standards.Model', "For #{template}, no exterior wall area was found, no infiltration will be added.")
      return true
    end
    # Calculate the total infiltration, assuming
    # that it only occurs through exterior walls and roofs (not floors as
    # explicit stated in the NECB2011 so overhang/cantilevered floors will
    # have no effective infiltration)
    tot_infil_m3_per_s = self.get_standards_constant('infiltration_rate_m3_per_s_per_m2') * exterior_wall_and_roof_and_subsurface_area
    # Now spread the total infiltration rate over all
    # exterior surface area (for the E+ input field) this will include the exterior floor if present.
    all_ext_infil_m3_per_s_per_m2 = tot_infil_m3_per_s / space.exteriorArea

    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Standards.Space', "For #{space.name}, adj infil = #{all_ext_infil_m3_per_s_per_m2.round(8)} m^3/s*m^2.")

    # Get any infiltration schedule already assigned to this space or its space type
    # If not, the always on schedule will be applied.
    infil_sch = nil
    unless space.spaceInfiltrationDesignFlowRates.empty?
      old_infil = space.spaceInfiltrationDesignFlowRates[0]
      if old_infil.schedule.is_initialized
        infil_sch = old_infil.schedule.get
      end
    end

    if infil_sch.nil? && space.spaceType.is_initialized
      space_type = space.spaceType.get
      unless space_type.spaceInfiltrationDesignFlowRates.empty?
        old_infil = space_type.spaceInfiltrationDesignFlowRates[0]
        if old_infil.schedule.is_initialized
          infil_sch = old_infil.schedule.get
        end
      end
    end

    if infil_sch.nil?
      infil_sch = space.model.alwaysOnDiscreteSchedule
    end

    # Create an infiltration rate object for this space
    infiltration = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(space.model)
    infiltration.setName("#{space.name} Infiltration")
    infiltration.setFlowperExteriorSurfaceArea(all_ext_infil_m3_per_s_per_m2)
    infiltration.setSchedule(infil_sch)
    infiltration.setConstantTermCoefficient(self.get_standards_constant('infiltration_constant_term_coefficient'))
    infiltration.setTemperatureTermCoefficient(self.get_standards_constant('infiltration_constant_term_coefficient'))
    infiltration.setVelocityTermCoefficient(self.get_standards_constant('infiltration_velocity_term_coefficient'))
    infiltration.setVelocitySquaredTermCoefficient(self.get_standards_constant('infiltration_velocity_squared_term_coefficient'))
    infiltration.setSpace(space)

    return true
  end

  # @return [Bool] returns true if successful, false if not
  def set_occ_sensor_spacetypes(model, space_type_map)
    building_type = 'Space Function'
    space_type_map.each do |space_type_name, space_names|
      space_names.sort.each do |space_name|
        space = model.getSpaceByName(space_name)
        next if space.empty?
        space = space.get

        # Check if space type for this space matches NECB2011 specific space type
        # for occupancy sensor that is area dependent. Note: space.floorArea in m2.

        #Evaluate the formula in the database.
        standard_space_type_name = space_type_name
        floor_area = space.floorArea
        if eval(@standards_data['formulas']['occupancy_sensors_space_types_formula']['value'])
          # If there is only one space assigned to this space type, then reassign this stub
          # to the @@template duplicate with appendage " - occsens", otherwise create a new stub
          # for this space. Required to use reduced LPD by NECB2011 0.9 factor.
          space_type_name_occsens = space_type_name + ' - occsens'
          stub_space_type_occsens = model.getSpaceTypeByName("#{building_type} #{space_type_name_occsens}")

          if stub_space_type_occsens.empty?
            # create a new space type just once for space_type_name appended with " - occsens"
            stub_space_type_occsens = OpenStudio::Model::SpaceType.new(model)
            stub_space_type_occsens.setStandardsBuildingType(building_type)
            stub_space_type_occsens.setStandardsSpaceType(space_type_name_occsens)
            stub_space_type_occsens.setName("#{building_type} #{space_type_name_occsens}")
            space_type_apply_rendering_color(stub_space_type_occsens)
            space.setSpaceType(stub_space_type_occsens)
          else
            # reassign occsens space type stub already created...
            stub_space_type_occsens = stub_space_type_occsens.get
            space.setSpaceType(stub_space_type_occsens)
          end
        end
      end
    end
    return true
  end

  # 2019-05-23 ckirney  This is an ugly, disgusting, hack (hence the name) that I dreamed out so that we could quickly
  # and easily finish the merge from the nrcan branch (using OS 2.6.0) to master (using OS 2.8.0).  This must be revised
  # and a more elegant solution found.
  #
  # This method takes everything in the @standards_data['tables'] hash and adds it to the main @standards_data hash.
  # This was done because other contributors insist on using the 'model_find_object' method which is passed a hash and
  # some search criteria.  The 'model_find_objects' then looks through the hash to information matching the search
  # criteria.  NECB standards assumes that the 'standards_lookup_table_first' method is used.  This does basically the
  # some thing as 'model_find_objects' only it assumes that you are looking in the standards hash and you tell it which
  # table in the standards hash to look for.
  def corrupt_standards_database()
    @standards_data['tables'].each do |table|
      @standards_data[table[0]] = table[1]['table']
    end
  end

  #This model gets the climate zone column index from tables 3.2.2.x
  #@author phylroy.lopez@nrcan.gc.ca
  #@param hdd [Float]
  #@return [Fixnum] climate zone 4-8
  def get_climate_zone_index(hdd)
    #check for climate zone index from NECB 3.2.2.X
    case hdd
    when 0..2999 then
      return 0 #climate zone 4
    when 3000..3999 then
      return 1 #climate zone 5
    when 4000..4999 then
      return 2 #climate zone 6
    when 5000..5999 then
      return 3 #climate zone 7a
    when 6000..6999 then
      return 4 #climate zone 7b
    when 7000..1000000 then
      return 5 #climate zone 8
    end
  end

  #This model gets the climate zone name and returns the climate zone string.
  #@author phylroy.lopez@nrcan.gc.ca
  #@param hdd [Float]
  #@return [Fixnum] climate zone 4-8
  def get_climate_zone_name(hdd)
    case self.get_climate_zone_index(hdd)
    when 0 then
      return "4"
    when 1 then
      return "5" #climate zone 5
    when 2 then
      return "6" #climate zone 6
    when 3 then
      return "7a" #climate zone 7a
    when 4 then
      return "7b" #climate zone 7b
    when 5 then
      return "8" #climate zone 8
    end
  end


  def model_add_daylighting_controls(model)

    ##### Ask user's inputs for daylighting controls illuminance setpoint and number of stepped control steps.
    ##### Note that the minimum number of stepped control steps is two steps as per NECB2011.
    def daylighting_controls_settings(illuminance_setpoint: 500.0,
                                      number_of_stepped_control_steps: 2)
      return illuminance_setpoint, number_of_stepped_control_steps
    end

    ##### Find spaces with exterior fenestration including fixed window, operable window, and skylight.
    daylight_spaces = []
    model.getSpaces.sort.each do |space|
      space.surfaces.each do |surface|
        surface.subSurfaces.each do |subsurface|
          if subsurface.outsideBoundaryCondition == "Outdoors" &&
              (subsurface.subSurfaceType == "FixedWindow" ||
                  subsurface.subSurfaceType == "OperableWindow" ||
                  subsurface.subSurfaceType == "Skylight")
            daylight_spaces << space
          end #subsurface.outsideBoundaryCondition == "Outdoors" && (subsurface.subSurfaceType == "FixedWindow" || "OperableWindow")
        end #surface.subSurfaces.each do |subsurface|
      end #space.surfaces.each do |surface|
    end #model.getSpaces.sort.each do |space|

    ##### Remove duplicate spaces from the "daylight_spaces" array, as a daylighted space may have various fenestration types.
    daylight_spaces = daylight_spaces.uniq
    # puts daylight_spaces

    ##### Create hashes for "Primary Sidelighted Areas", "Sidelighting Effective Aperture", "Daylighted Area Under Skylights",
    ##### and "Skylight Effective Aperture" for the whole model.
    ##### Each of these hashes will be used later in this function (i.e. model_add_daylighting_controls)
    ##### to provide a dictionary of daylighted space names and the associated value (i.e. daylighted area or effective aperture).
    primary_sidelighted_area_hash = {}
    sidelighting_effective_aperture_hash = {}
    daylighted_area_under_skylights_hash = {}
    skylight_effective_aperture_hash = {}

    ##### Calculate "Primary Sidelighted Areas" AND "Sidelighting Effective Aperture" as per NECB2011. #TODO: consider removing overlapped sidelighted area
    daylight_spaces.each do |daylight_space|
      # puts daylight_space.name.to_s
      primary_sidelighted_area = 0.0
      area_weighted_vt_handle = 0.0
      area_weighted_vt = 0.0
      window_area_sum = 0.0

      ##### Calculate floor area of the daylight_space and get floor vertices of the daylight_space (to be used for the calculation of daylight_space depth)
      floor_surface = nil
      floor_area = []
      floor_vertices = []
      daylight_space.surfaces.each do |surface|
        if surface.surfaceType == "Floor"
          floor_surface = surface
          floor_area << surface.netArea
          floor_vertices << surface.vertices
        end
      end

      ##### Loop through the surfaces of each daylight_space to calculate primary_sidelighted_area and
      ##### area-weighted visible transmittance and window_area_sum which are used to calculate sidelighting_effective_aperture
      daylight_space.surfaces.each do |surface|

        ##### Get the vertices of each exterior wall of the daylight_space on the floor
        ##### (these vertices will be used to calculate daylight_space depth in relation to the exterior wall, and
        ##### the distance of the window to vertical walls on each side of the window)
        if surface.outsideBoundaryCondition == "Outdoors" && surface.surfaceType == "Wall"
          wall_vertices_x_on_floor = []
          wall_vertices_y_on_floor = []
          surface_z_min = [surface.vertices[0].z, surface.vertices[1].z, surface.vertices[2].z, surface.vertices[3].z].min
          surface.vertices.each do |vertex|
            # puts vertex.z
            if vertex.z == surface_z_min && surface_z_min == floor_vertices[0][0].z
              wall_vertices_x_on_floor << vertex.x
              wall_vertices_y_on_floor << vertex.y
            end
          end
        end

        if surface.outsideBoundaryCondition == "Outdoors" && surface.surfaceType == "Wall" && surface_z_min == floor_vertices[0][0].z

          ##### Calculate the daylight_space depth in relation to the considered exterior wall.
          ##### To calculate daylight_space depth, first get the floor vertices which are on the opposite side of the considered exterior wall.
          floor_vertices_x_wall_opposite = []
          floor_vertices_y_wall_opposite = []
          floor_vertices[0].each do |floor_vertex|
            if (floor_vertex.x != wall_vertices_x_on_floor[0] && floor_vertex.y != wall_vertices_y_on_floor[0]) || (floor_vertex.x != wall_vertices_x_on_floor[1] && floor_vertex.y != wall_vertices_y_on_floor[1])
              floor_vertices_x_wall_opposite << floor_vertex.x
              floor_vertices_y_wall_opposite << floor_vertex.y
            end
          end

          ##### To calculate daylight_space depth, second calculate floor length on both sides: (1) exterior wall side, (2) on the opposite side of the exterior wall
          floor_width_wall_side = Math.sqrt((wall_vertices_x_on_floor[0] - wall_vertices_x_on_floor[1]) ** 2 + (wall_vertices_y_on_floor[0] - wall_vertices_y_on_floor[1]) ** 2)
          floor_width_wall_opposite = Math.sqrt((floor_vertices_x_wall_opposite[0] - floor_vertices_x_wall_opposite[1]) ** 2 + (floor_vertices_y_wall_opposite[0] - floor_vertices_y_wall_opposite[1]) ** 2)

          ##### Now, daylight_space depth can be calculated using the floor area and two lengths of the floor (note that these two lengths are in parallel to each other).
          daylight_space_depth = 2 * floor_area[0] / (floor_width_wall_side + floor_width_wall_opposite)

          ##### Loop through the windows (including fixed and operable ones) to get window specification (width, height, area, visible transmittance (VT)), and area-weighted VT
          surface.subSurfaces.each do |subsurface|
            # puts subsurface.name.to_s
            if subsurface.subSurfaceType == "FixedWindow" || subsurface.subSurfaceType == "OperableWindow"
              window_vt = subsurface.visibleTransmittance
              window_vt = window_vt.get
              window_area = subsurface.netArea
              window_area_sum += window_area
              area_weighted_vt_handle += window_area * window_vt
              window_vertices = subsurface.vertices
              if window_vertices[0].z.round(2) == window_vertices[1].z.round(2)
                window_width = Math.sqrt((window_vertices[0].x - window_vertices[1].x) ** 2.0 + (window_vertices[0].y - window_vertices[1].y) ** 2.0)
              else
                window_width = Math.sqrt((window_vertices[1].x - window_vertices[2].x) ** 2.0 + (window_vertices[1].y - window_vertices[2].y) ** 2.0)
              end
              window_head_height = [window_vertices[0].z, window_vertices[1].z, window_vertices[2].z, window_vertices[3].z].max.round(2)
              primary_sidelighted_area_depth = [window_head_height, daylight_space_depth].min #as per NECB2011: 4.2.2.9.

              ##### Calculate the  distance of the window to vertical walls on each side of the window (this is used to determine the sidelighted area's width).
              window_vertices_on_floor = []
              window_vertices.each do |vertex|
                window_vertices_on_floor << floor_surface.plane.project(vertex)
              end
              window_wall_distance_side1 = [Math.sqrt((wall_vertices_x_on_floor[0] - window_vertices_on_floor[0].x) ** 2.0 + (wall_vertices_y_on_floor[0] - window_vertices_on_floor[0].y) ** 2.0),
                                            Math.sqrt((wall_vertices_x_on_floor[0] - window_vertices_on_floor[2].x) ** 2.0 + (wall_vertices_y_on_floor[0] - window_vertices_on_floor[2].y) ** 2.0),
                                            0.6].min # 0.6 m as per NECB2011: 4.2.2.9.
              window_wall_distance_side2 = [Math.sqrt((wall_vertices_x_on_floor[1] - window_vertices_on_floor[0].x) ** 2.0 + (wall_vertices_y_on_floor[1] - window_vertices_on_floor[0].y) ** 2.0),
                                            Math.sqrt((wall_vertices_x_on_floor[1] - window_vertices_on_floor[2].x) ** 2.0 + (wall_vertices_y_on_floor[1] - window_vertices_on_floor[2].y) ** 2.0),
                                            0.6].min # 0.6 m as per NECB2011: 4.2.2.9.
              primary_sidelighted_area_width = window_wall_distance_side1 + window_width + window_wall_distance_side2
              primary_sidelighted_area = primary_sidelighted_area + primary_sidelighted_area_depth * primary_sidelighted_area_width
            end #if subsurface.subSurfaceType == "FixedWindow" || subsurface.subSurfaceType == "OperableWindow"
          end #surface.subSurfaces.each do |subsurface|
        end #if surface.outsideBoundaryCondition == "Outdoors" && surface.surfaceType == "Wall" && surface_z_min == floor_vertices[0][0].z
      end #daylight_space.surfaces.each do |surface|

      primary_sidelighted_area_hash[daylight_space.name.to_s] = primary_sidelighted_area

      ##### Calculate area-weighted VT of glazing (this is used to calculate sidelighting effective aperture; see NECB2011: 4.2.2.10.).
      area_weighted_vt = area_weighted_vt_handle / window_area_sum
      sidelighting_effective_aperture_hash[daylight_space.name.to_s] = window_area_sum * area_weighted_vt / primary_sidelighted_area

    end #daylight_spaces.each do |daylight_space|


    ##### Calculate "Daylighted Area Under Skylights" AND "Skylight Effective Aperture"
    daylight_spaces.each do |daylight_space|
      # puts daylight_space.name.to_s
      skylight_area = 0.0
      skylight_area_weighted_vt_handle = 0.0
      skylight_area_weighted_vt = 0.0
      skylight_area_sum = 0.0

      ##### Loop through the surfaces of each daylight_space to calculate daylighted_area_under_skylights and skylight_effective_aperture for each daylight_space
      daylight_space.surfaces.each do |surface|
        ##### Get roof vertices
        if surface.outsideBoundaryCondition == "Outdoors" && surface.surfaceType == "RoofCeiling"
          roof_vertices = surface.vertices
        end

        ##### Loop through each subsurafce to calculate daylighted_area_under_skylights and skylight_effective_aperture for each daylight_space
        surface.subSurfaces.each do |subsurface|
          if subsurface.subSurfaceType == "Skylight"
            skylight_vt = subsurface.visibleTransmittance
            skylight_vt = skylight_vt.get
            skylight_area = subsurface.netArea
            skylight_area_sum += skylight_area
            skylight_area_weighted_vt_handle += skylight_area * skylight_vt

            ##### Get skylight vertices
            skylight_vertices = subsurface.vertices

            ##### Calculate skylight width and height
            skylight_width = Math.sqrt((skylight_vertices[0].x - skylight_vertices[1].x) ** 2.0 + (skylight_vertices[0].y - skylight_vertices[1].y) ** 2.0)
            skylight_length = Math.sqrt((skylight_vertices[0].x - skylight_vertices[3].x) ** 2.0 + (skylight_vertices[0].y - skylight_vertices[3].y) ** 2.0)

            ##### Get ceiling height assuming the skylight is flush with the ceiling
            ceiling_height = skylight_vertices[0].z

            ##### Calculate roof lengths
            ##### (Note: used OpenStudio BCL measure called "assign_ashrae_9012010_daylighting_controls" with some changes/correcctions)
            roof_length_0 = Math.sqrt((roof_vertices[0].x - roof_vertices[1].x) ** 2.0 + (roof_vertices[0].y - roof_vertices[1].y) ** 2.0)
            roof_length_1 = Math.sqrt((roof_vertices[1].x - roof_vertices[2].x) ** 2.0 + (roof_vertices[1].y - roof_vertices[2].y) ** 2.0)
            roof_length_2 = Math.sqrt((roof_vertices[2].x - roof_vertices[3].x) ** 2.0 + (roof_vertices[2].y - roof_vertices[3].y) ** 2.0)
            roof_length_3 = Math.sqrt((roof_vertices[3].x - roof_vertices[0].x) ** 2.0 + (roof_vertices[3].y - roof_vertices[0].y) ** 2.0)

            ##### Find the skylight point that is the closest one to roof_vertex_0
            ##### (Note: used OpenStudio BCL measure called "assign_ashrae_9012010_daylighting_controls" with some changes/correcctions)
            roof_vertex_0_skylight_vertex_0 = Math.sqrt((roof_vertices[0].x - skylight_vertices[0].x) ** 2.0 + (roof_vertices[0].y - skylight_vertices[0].y) ** 2.0)
            roof_vertex_0_skylight_vertex_1 = Math.sqrt((roof_vertices[0].x - skylight_vertices[1].x) ** 2.0 + (roof_vertices[0].y - skylight_vertices[1].y) ** 2.0)
            roof_vertex_0_skylight_vertex_2 = Math.sqrt((roof_vertices[0].x - skylight_vertices[2].x) ** 2.0 + (roof_vertices[0].y - skylight_vertices[2].y) ** 2.0)
            roof_vertex_0_skylight_vertex_3 = Math.sqrt((roof_vertices[0].x - skylight_vertices[3].x) ** 2.0 + (roof_vertices[0].y - skylight_vertices[3].y) ** 2.0)
            roof_vertex_0_closest_distance = [roof_vertex_0_skylight_vertex_0, roof_vertex_0_skylight_vertex_1, roof_vertex_0_skylight_vertex_2, roof_vertex_0_skylight_vertex_3].min
            if roof_vertex_0_closest_distance == roof_vertex_0_skylight_vertex_0
              roof_vertex_0_closest_point = skylight_vertices[0]
            elsif roof_vertex_0_closest_distance == roof_vertex_0_skylight_vertex_1
              roof_vertex_0_closest_point = skylight_vertices[1]
            elsif roof_vertex_0_closest_distance == roof_vertex_0_skylight_vertex_2
              roof_vertex_0_closest_point = skylight_vertices[2]
            elsif roof_vertex_0_closest_distance == roof_vertex_0_skylight_vertex_3
              roof_vertex_0_closest_point = skylight_vertices[3]
            end

            ##### Find the skylight point that is the closest one to roof_vertex_2
            ##### (Note: used OpenStudio BCL measure called "assign_ashrae_9012010_daylighting_controls" with some changes/correcctions)
            roof_vertex_2_skylight_vertex_0 = Math.sqrt((roof_vertices[2].x - skylight_vertices[0].x) ** 2.0 + (roof_vertices[2].y - skylight_vertices[0].y) ** 2.0)
            roof_vertex_2_skylight_vertex_1 = Math.sqrt((roof_vertices[2].x - skylight_vertices[1].x) ** 2.0 + (roof_vertices[2].y - skylight_vertices[1].y) ** 2.0)
            roof_vertex_2_skylight_vertex_2 = Math.sqrt((roof_vertices[2].x - skylight_vertices[2].x) ** 2.0 + (roof_vertices[2].y - skylight_vertices[2].y) ** 2.0)
            roof_vertex_2_skylight_vertex_3 = Math.sqrt((roof_vertices[2].x - skylight_vertices[3].x) ** 2.0 + (roof_vertices[2].y - skylight_vertices[3].y) ** 2.0)
            roof_vertex_2_closest_distance = [roof_vertex_2_skylight_vertex_0, roof_vertex_2_skylight_vertex_1, roof_vertex_2_skylight_vertex_2, roof_vertex_2_skylight_vertex_3].min
            if roof_vertex_2_closest_distance == roof_vertex_2_skylight_vertex_0
              roof_vertex_2_closest_point = skylight_vertices[0]
            elsif roof_vertex_2_closest_distance == roof_vertex_2_skylight_vertex_1
              roof_vertex_2_closest_point = skylight_vertices[1]
            elsif roof_vertex_2_closest_distance == roof_vertex_2_skylight_vertex_2
              roof_vertex_2_closest_point = skylight_vertices[2]
            elsif roof_vertex_2_closest_distance == roof_vertex_2_skylight_vertex_3
              roof_vertex_2_closest_point = skylight_vertices[3]
            end

            ##### Calculate the vertical distance from the closest skylight points (projection onto the roof) to the wall (projection onto the roof) for roof_vertex_0 and roof_vertex_2
            ##### (Note: used OpenStudio BCL measure called "assign_ashrae_9012010_daylighting_controls" with some changes/correcctions)
            ##### For the calculation of each vertical distance: (1) first the area of the triangle is calculated knowing the cooridantes of its three corners;
            ##### (2) the vertical distance (i.e. triangle height) is calculated knowing the triangle area and the associated roof length.
            rv_0_triangle_0_area = 0.5 * (((roof_vertex_0_closest_point.x - roof_vertices[1].x) * (roof_vertex_0_closest_point.y - roof_vertices[0].y)) -
                ((roof_vertex_0_closest_point.x - roof_vertices[0].x) * (roof_vertex_0_closest_point.y - roof_vertices[1].y))).abs
            rv_0_distance_0 = (2.0 * rv_0_triangle_0_area) / roof_length_0
            rv_0_triangle_3_area = 0.5 * (((roof_vertex_0_closest_point.x - roof_vertices[3].x) * (roof_vertex_0_closest_point.y - roof_vertices[0].y)) -
                ((roof_vertex_0_closest_point.x - roof_vertices[0].x) * (roof_vertex_0_closest_point.y - roof_vertices[3].y))).abs
            rv_0_distance_3 = (2.0 * rv_0_triangle_3_area) / roof_length_3

            rv_2_triangle_1_area = 0.5 * (((roof_vertex_2_closest_point.x - roof_vertices[1].x) * (roof_vertex_2_closest_point.y - roof_vertices[2].y)) -
                ((roof_vertex_2_closest_point.x - roof_vertices[2].x) * (roof_vertex_2_closest_point.y - roof_vertices[1].y))).abs
            rv_2_distance_1 = (2.0 * rv_2_triangle_1_area) / roof_length_1
            rv_2_triangle_2_area = 0.5 * (((roof_vertex_2_closest_point.x - roof_vertices[3].x) * (roof_vertex_2_closest_point.y - roof_vertices[2].y)) -
                ((roof_vertex_2_closest_point.x - roof_vertices[2].x) * (roof_vertex_2_closest_point.y - roof_vertices[3].y))).abs
            rv_2_distance_2 = (2.0 * rv_2_triangle_2_area) / roof_length_2

            ##### Set the vertical distances from the closest skylight points (projection onto the roof) to the wall (projection onto the roof) for roof_vertex_0 and roof_vertex_2
            distance_1 = rv_0_distance_0
            distance_2 = rv_0_distance_3
            distance_3 = rv_2_distance_1
            distance_4 = rv_2_distance_2

            ##### Calculate the width and length of the daylighted area under the skylight as per NECB2011: 4.2.2.5.
            ##### Note: In the below loops, if any exterior walls has window(s), the width and length of the daylighted area under the skylight are re-calculated as per NECB2011: 4.2.2.5.
            daylighted_under_skylight_width = skylight_width + [0.7 * ceiling_height, distance_1].min + [0.7 * ceiling_height, distance_4].min
            daylighted_under_skylight_length = skylight_length + [0.7 * ceiling_height, distance_2].min + [0.7 * ceiling_height, distance_3].min

            ##### As noted above, the width and length of the daylighted area under the skylight are re-calculated (as per NECB2011: 4.2.2.5.), if any exterior walls has window(s).
            ##### To this end, the window_head_height should be calculated, as below:
            daylight_space.surfaces.each do |surface|
              if surface.outsideBoundaryCondition == "Outdoors" && surface.surfaceType == "Wall"
                wall_vertices_on_floor_x = []
                wall_vertices_on_floor_y = []
                wall_vertices = surface.vertices
                if wall_vertices[0].z == wall_vertices[1].z
                  wall_vertices_on_floor_x << wall_vertices[0].x
                  wall_vertices_on_floor_x << wall_vertices[1].x
                  wall_vertices_on_floor_y << wall_vertices[0].y
                  wall_vertices_on_floor_y << wall_vertices[1].y
                elsif wall_vertices[0].z == wall_vertices[3].z
                  wall_vertices_on_floor_x << wall_vertices[0].x
                  wall_vertices_on_floor_x << wall_vertices[3].x
                  wall_vertices_on_floor_y << wall_vertices[0].y
                  wall_vertices_on_floor_y << wall_vertices[3].y
                end
                window_vertices = subsurface.vertices
                window_head_height = [window_vertices[0].z, window_vertices[1].z, window_vertices[2].z, window_vertices[3].z].max.round(2)

                ##### Calculate the exterior wall length (on the floor)
                exterior_wall_length = Math.sqrt((wall_vertices_on_floor_x[0] - wall_vertices_on_floor_x[1]) ** 2.0 + (wall_vertices_on_floor_y[0] - wall_vertices_on_floor_y[1]) ** 2.0)

                ##### Calculate the vertical distance of skylight_vertices[0] projection onto the roof/floor to the exterior wall
                skylight_vertex_0_triangle_area = 0.5 * (((wall_vertices_on_floor_x[0] - wall_vertices_on_floor_x[1]) * (wall_vertices_on_floor_y[0] - skylight_vertices[0].y)) -
                    ((wall_vertices_on_floor_x[0] - skylight_vertices[0].x) * (wall_vertices_on_floor_y[0] - wall_vertices_on_floor_y[1]))).abs
                skylight_vertex_0_distance = (2.0 * skylight_vertex_0_triangle_area) / exterior_wall_length

                ##### Calculate the vertical distance of skylight_vertices[1] projection onto the roof/floor to the exterior wall
                skylight_vertex_1_triangle_area = 0.5 * (((wall_vertices_on_floor_x[0] - wall_vertices_on_floor_x[1]) * (wall_vertices_on_floor_y[0] - skylight_vertices[1].y)) -
                    ((wall_vertices_on_floor_x[0] - skylight_vertices[1].x) * (wall_vertices_on_floor_y[0] - wall_vertices_on_floor_y[1]))).abs
                skylight_vertex_1_distance = (2.0 * skylight_vertex_1_triangle_area) / exterior_wall_length

                ##### Calculate the vertical distance of skylight_vertices[3] projection onto the roof/floor to the exterior wall
                skylight_vertex_3_triangle_area = 0.5 * (((wall_vertices_on_floor_x[0] - wall_vertices_on_floor_x[1]) * (wall_vertices_on_floor_y[0] - skylight_vertices[3].y)) -
                    ((wall_vertices_on_floor_x[0] - skylight_vertices[3].x) * (wall_vertices_on_floor_y[0] - wall_vertices_on_floor_y[1]))).abs
                skylight_vertex_3_distance = (2.0 * skylight_vertex_3_triangle_area) / exterior_wall_length

                ##### Loop through the subsurfaces that has exterior windows to re-calculate the width and length of the daylighted area under the skylight
                surface.subSurfaces.each do |subsurface|
                  if subsurface.subSurfaceType == "FixedWindow" || subsurface.subSurfaceType == "OperableWindow"

                    if skylight_vertex_0_distance == skylight_vertex_1_distance #skylight_01 is in parellel to the exterior wall
                      if skylight_vertex_0_distance.round(2) == distance_2.round(2)
                        daylighted_under_skylight_length = skylight_length + [0.7 * ceiling_height, distance_2, distance_2 - window_head_height].min + [0.7 * ceiling_height, distance_3].min
                      elsif skylight_vertex_0_distance.round(2) == distance_3.round(2)
                        daylighted_under_skylight_length = skylight_length + [0.7 * ceiling_height, distance_2].min + [0.7 * ceiling_height, distance_3, distance_3 - window_head_height].min
                      end
                    elsif skylight_vertex_0_distance == skylight_vertex_3_distance #skylight_03 is in parellel to the exterior wall
                      if skylight_vertex_0_distance.round(2) == distance_1.round(2)
                        daylighted_under_skylight_width = skylight_width + [0.7 * ceiling_height, distance_1, distance_1 - window_head_height].min + [0.7 * ceiling_height, distance_4].min
                      elsif skylight_vertex_0_distance.round(2) == distance_4.round(2)
                        daylighted_under_skylight_width = skylight_width + [0.7 * ceiling_height, distance_1].min + [0.7 * ceiling_height, distance_4, distance_4 - window_head_height].min
                      end
                    end #if skylight_vertex_0_distance == skylight_vertex_1_distance

                  end #if subsurface.subSurfaceType == "FixedWindow" || subsurface.subSurfaceType == "OperableWindow"
                end #surface.subSurfaces.each do |subsurface|
              end #if surface.outsideBoundaryCondition == "Outdoors" && surface.surfaceType == "Wall"
            end #daylight_space.surfaces.each do |surface|

            skylight_area_weighted_vt = skylight_area_weighted_vt_handle / skylight_area_sum
            daylighted_area_under_skylights_hash[daylight_space.name.to_s] = daylighted_under_skylight_length * daylighted_under_skylight_width

            ##### Calculate skylight_effective_aperture as per NECB2011: 4.2.2.7.
            ##### Note that it was assumed that the skylight is flush with the ceiling. Therefore, area-weighted average well factor (WF) was set to 0.9 in the below Equation.
            skylight_effective_aperture_hash[daylight_space.name.to_s] = 0.85 * skylight_area_sum * skylight_area_weighted_vt * 0.9 / (daylighted_under_skylight_length * daylighted_under_skylight_width)

          end #if subsurface.subSurfaceType == "Skylight"
        end #surface.subSurfaces.each do |subsurface|
      end #daylight_space.surfaces.each do |surface|

    end #daylight_spaces.each do |daylight_space|

    # puts primary_sidelighted_area_hash
    # puts sidelighting_effective_aperture_hash
    # puts daylighted_area_under_skylights_hash
    # puts skylight_effective_aperture_hash

    ##### Find office spaces >= 25m2 among daylight_spaces
    offices_larger_25m2 = []
    daylight_spaces.each do |daylight_space|
      office_area = nil
      daylight_space.surfaces.each do |surface|
        if surface.surfaceType == "Floor"
          office_area = surface.netArea
        end
      end
      if daylight_space.spaceType.get.standardsSpaceType.get.to_s == "Office - enclosed" && office_area >= 25.0
        offices_larger_25m2 << daylight_space.name.to_s
      end
    end

    ##### find daylight_spaces which do not need daylight sensor controls based on the primary_sidelighted_area as per NECB2011: 4.2.2.8.
    ##### Note: Office spaces >= 25m2 are excluded (i.e. they should have daylighting controls even if their primary_sidelighted_area <= 100m2), as per NECB2011: 4.2.2.2.
    daylight_spaces_exception = []
    primary_sidelighted_area_hash.each do |key_daylight_space_name, value_primary_sidelighted_area|
      if value_primary_sidelighted_area <= 100.0 && [key_daylight_space_name].any? {|word| offices_larger_25m2.include?(word)} == false
        daylight_spaces_exception << key_daylight_space_name
      end
    end

    ##### find daylight_spaces which do not need daylight sensor controls based on the sidelighting_effective_aperture as per NECB2011: 4.2.2.8.
    ##### Note: Office spaces >= 25m2 are excluded (i.e. they should have daylighting controls even if their sidelighting_effective_aperture <= 10%), as per NECB2011: 4.2.2.2.
    sidelighting_effective_aperture_hash.each do |key_daylight_space_name, value_sidelighting_effective_aperture|
      if value_sidelighting_effective_aperture <= 0.1 && [key_daylight_space_name].any? {|word| offices_larger_25m2.include?(word)} == false
        daylight_spaces_exception << key_daylight_space_name
      end
    end

    ##### find daylight_spaces which do not need daylight sensor controls based on the daylighted_area_under_skylights as per NECB2011: 4.2.2.4.
    ##### Note: Office spaces >= 25m2 are excluded (i.e. they should have daylighting controls even if their daylighted_area_under_skylights <= 400m2), as per NECB2011: 4.2.2.2.
    daylighted_area_under_skylights_hash.each do |key_daylight_space_name, value_daylighted_area_under_skylights|
      if value_daylighted_area_under_skylights <= 400.0 && [key_daylight_space_name].any? {|word| offices_larger_25m2.include?(word)} == false
        daylight_spaces_exception << key_daylight_space_name
      end
    end

    ##### find daylight_spaces which do not need daylight sensor controls based on the skylight_effective_aperture criterion as per NECB2011: 4.2.2.4.
    ##### Note: Office spaces >= 25m2 are excluded (i.e. they should have daylighting controls even if their skylight_effective_aperture <= 0.6%), as per NECB2011: 4.2.2.2.
    skylight_effective_aperture_hash.each do |key_daylight_space_name, value_skylight_effective_aperture|
      if value_skylight_effective_aperture <= 0.006 && [key_daylight_space_name].any? {|word| offices_larger_25m2.include?(word)} == false
        daylight_spaces_exception << key_daylight_space_name
      end
    end
    # puts daylight_spaces_exception

    ##### Loop through the daylight_spaces and exclude the daylight_spaces that do not meet the criteria (see above) as per NECB2011: 4.2.2.4. and 4.2.2.8.
    daylight_spaces_exception.each do |daylight_space_exception|
      daylight_spaces.each do |daylight_space|
        if daylight_space.name.to_s == daylight_space_exception
          daylight_spaces.delete(daylight_space)
        end
      end
    end
    # puts daylight_spaces

    ##### Create one daylighting sensor and put it at the center of each daylight_space if the space area < 250m2;
    ##### otherwise, create two daylight sensors, divide the space into two parts and put each of the daylight sensors at the center of each part of the space.
    daylight_spaces.each do |daylight_space|

      ##### Calculate the area of the daylight_space
      daylight_space_area = nil
      daylight_space.surfaces.each do |surface|
        if surface.surfaceType == "Floor"
          daylight_space_area = surface.netArea
        end
      end

      ##### Get the thermal zone of daylight_space (this is used later to assign daylighting sensor)
      zone = daylight_space.thermalZone
      if zone.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Space', "Space #{daylight_space.name}, cannot determine daylighted areas.")
        return false
      else
        zone = daylight_space.thermalZone.get
      end

      ##### Get the floor of the daylight_space
      floors = []
      daylight_space.surfaces.each do |surface|
        if surface.surfaceType == "Floor"
          floors << surface
        end
      end

      ##### Get user's input for daylighting controls illuminance setpoint and number of stepped control steps
      illuminance_setpoint, number_of_stepped_control_steps = daylighting_controls_settings(illuminance_setpoint: 500.0, number_of_stepped_control_steps: 2)

      ##### Create daylighting sensor control(s)
      if daylight_space_area <= 250.0
        boundingBox = OpenStudio::BoundingBox.new
        floors.each do |floor|
          boundingBox.addPoints(floor.vertices)
        end
        xmin = boundingBox.minX.get
        ymin = boundingBox.minY.get
        zmin = boundingBox.minZ.get
        xmax = boundingBox.maxX.get
        ymax = boundingBox.maxY.get
        sensor = OpenStudio::Model::DaylightingControl.new(daylight_space.model)
        sensor.setName("#{daylight_space.name.to_s} daylighting control")
        sensor.setSpace(daylight_space)
        sensor.setIlluminanceSetpoint(illuminance_setpoint)
        sensor.setLightingControlType('Stepped')
        sensor.setNumberofSteppedControlSteps(number_of_stepped_control_steps)
        x_pos = (xmin + xmax) / 2.0
        y_pos = (ymin + ymax) / 2.0
        z_pos = zmin + 0.8 #put it 0.8 meter above the floor
        sensor_vertex = OpenStudio::Point3d.new(x_pos, y_pos, z_pos)
        sensor.setPosition(sensor_vertex)
        zone.setPrimaryDaylightingControl(sensor)
        zone.setFractionofZoneControlledbyPrimaryDaylightingControl(1.0)
      else
        floor_vertices = []
        floors.each do |floor|
          floor_vertices = floor.vertices
        end

        ##### Create daylighting sensor control #1 and put it at the center of each daylight_space.
        boundingBox = OpenStudio::BoundingBox.new
        vertex_0 = OpenStudio::Point3d.new(floor_vertices[0].x, floor_vertices[0].y, floor_vertices[0].z)
        vertex_1 = OpenStudio::Point3d.new(floor_vertices[1].x, floor_vertices[1].y, floor_vertices[1].z)
        # Find the mean point of the side connecting vertices 1 and 2.
        vertex_2 = OpenStudio::Point3d.new(floor_vertices[1].x - (floor_vertices[1].x - floor_vertices[2].x) / 2.0, floor_vertices[1].y + (floor_vertices[2].y - floor_vertices[1].y) / 2.0, floor_vertices[0].z)
        # Find the mean point of the side connecting vertices 0 and 3.
        vertex_3 = OpenStudio::Point3d.new(floor_vertices[3].x + (floor_vertices[0].x - floor_vertices[3].x) / 2.0, floor_vertices[0].y + (floor_vertices[3].y - floor_vertices[0].y) / 2.0, floor_vertices[0].z)
        boundingBox.addPoints([vertex_0, vertex_1, vertex_2, vertex_3])
        xmin = boundingBox.minX.get
        ymin = boundingBox.minY.get
        zmin = boundingBox.minZ.get
        xmax = boundingBox.maxX.get
        ymax = boundingBox.maxY.get
        sensor_1 = OpenStudio::Model::DaylightingControl.new(daylight_space.model)
        sensor_1.setName("#{daylight_space.name.to_s} daylighting control 1")
        sensor_1.setSpace(daylight_space)
        sensor_1.setIlluminanceSetpoint(illuminance_setpoint)
        sensor_1.setLightingControlType('Stepped')
        sensor_1.setNumberofSteppedControlSteps(number_of_stepped_control_steps)
        x_pos = (xmin + xmax) / 2.0
        y_pos = (ymin + ymax) / 2.0
        z_pos = zmin + 0.8 #put the sensor 0.8 meter above the floor
        sensor_vertex = OpenStudio::Point3d.new(x_pos, y_pos, z_pos)
        sensor_1.setPosition(sensor_vertex)
        zone.setPrimaryDaylightingControl(sensor_1)
        zone.setFractionofZoneControlledbyPrimaryDaylightingControl(0.5)

        ##### Create daylighting sensor control #2. Divide the space into two parts. Put each of the daylight sensors at the center of each part of the space.
        boundingBox = OpenStudio::BoundingBox.new
        vertex_0 = OpenStudio::Point3d.new(floor_vertices[2].x, floor_vertices[2].y, floor_vertices[2].z)
        vertex_1 = OpenStudio::Point3d.new(floor_vertices[3].x, floor_vertices[3].y, floor_vertices[3].z)
        vertex_2 = OpenStudio::Point3d.new(floor_vertices[3].x + (floor_vertices[0].x - floor_vertices[3].x) / 2, floor_vertices[0].y + (floor_vertices[3].y - floor_vertices[0].y) / 2, floor_vertices[0].z)
        vertex_3 = OpenStudio::Point3d.new(floor_vertices[1].x - (floor_vertices[1].x - floor_vertices[2].x) / 2, floor_vertices[1].y + (floor_vertices[2].y - floor_vertices[1].y) / 2, floor_vertices[0].z)
        boundingBox.addPoints([vertex_0, vertex_1, vertex_2, vertex_3])
        xmin = boundingBox.minX.get
        ymin = boundingBox.minY.get
        zmin = boundingBox.minZ.get
        xmax = boundingBox.maxX.get
        ymax = boundingBox.maxY.get
        sensor_2 = OpenStudio::Model::DaylightingControl.new(daylight_space.model)
        sensor_2.setName("#{daylight_space.name.to_s} daylighting control 2")
        sensor_2.setSpace(daylight_space)
        sensor_2.setIlluminanceSetpoint(illuminance_setpoint)
        sensor_2.setLightingControlType('Stepped')
        sensor_2.setNumberofSteppedControlSteps(number_of_stepped_control_steps)
        x_pos = (xmin + xmax) / 2.0
        y_pos = (ymin + ymax) / 2.0
        z_pos = zmin + 0.8 #put the sensor 0.8 meter above the floor
        sensor_vertex = OpenStudio::Point3d.new(x_pos, y_pos, z_pos)
        sensor_2.setPosition(sensor_vertex)
        zone.setSecondaryDaylightingControl(sensor_2)
        zone.setFractionofZoneControlledbySecondaryDaylightingControl(0.5)
      end

    end #daylight_spaces.each do |daylight_space|
  end #model_add_daylighting_controls



  def model_enable_demand_controlled_ventilation(model, dcv_type = "No DCV") # Note: Values for dcv_type are: "Occupancy-based DCV", "CO2-based DCV", "No DCV"

    if dcv_type == "Occupancy-based DCV" || dcv_type == "CO2-based DCV"
      #TODO: IMPORTANT: (upon other BTAP tasks) Set a value for the "Outdoor Air Flow per Person" field of the "OS:DesignSpecification:OutdoorAir" object
      # Note: The "Outdoor Air Flow per Person" field is required for occupancy-based DCV.
      # Note: The "Outdoor Air Flow per Person" values should be based on ASHRAE 62.1: Article 6.2.2.1.
      # Note: The "Outdoor Air Flow per Person" should be entered for "ventilation_per_person" in "lib/openstudio-standards/standards/necb/NECB2011/data/space_types.json"

      ##### Define ScheduleTypeLimits for Any_Number_ppm
      ##### TODO: (upon other BTAP tasks) This function can be added to btap/schedules.rb > module StandardScheduleTypeLimits
      def self.get_any_number_ppm(model)
        name = "Any_Number_ppm"
        any_number_ppm_schedule_type_limits = model.getScheduleTypeLimitsByName(name)
        if any_number_ppm_schedule_type_limits.empty?
          any_number_ppm_schedule_type_limits = OpenStudio::Model::ScheduleTypeLimits.new(model)
          any_number_ppm_schedule_type_limits.setName(name)
          any_number_ppm_schedule_type_limits.setNumericType("CONTINUOUS")
          any_number_ppm_schedule_type_limits.setUnitType("Dimensionless")
          any_number_ppm_schedule_type_limits.setLowerLimitValue(400.0)
          any_number_ppm_schedule_type_limits.setUpperLimitValue(1000.0)
          return any_number_ppm_schedule_type_limits
        else
          return any_number_ppm_schedule_type_limits.get
        end
      end

      ##### Define indoor CO2 availability schedule (required for CO2-based DCV)
      ##### Note: the defined schedule here is redundant as the schedule says it is always on AND
      ##### the "ZoneControl:ContaminantController" object says that "If this field is left blank, the schedule has a value of 1 for all time periods".
      indoor_co2_availability_schedule = OpenStudio::Model::ScheduleCompact.new(model)
      indoor_co2_availability_schedule.setName("indoor_co2_availability_schedule")
      indoor_co2_availability_schedule.setScheduleTypeLimits(BTAP::Resources::Schedules::StandardScheduleTypeLimits::get_fraction(model))
      indoor_co2_availability_schedule.setToConstantValue(1)

      ##### Define indoor CO2 setpoint schedule (required for CO2-based DCV)
      indoor_co2_setpoint_schedule = OpenStudio::Model::ScheduleCompact.new(model)
      indoor_co2_setpoint_schedule.setName("indoor_co2_setpoint_schedule")
      indoor_co2_setpoint_schedule.setScheduleTypeLimits(get_any_number_ppm(model))
      indoor_co2_setpoint_schedule.setToConstantValue(1000.0) #1000 ppm

      ##### Define outdoor CO2 schedule (required for CO2-based DCV)
      outdoor_co2_schedule = OpenStudio::Model::ScheduleCompact.new(model)
      outdoor_co2_schedule.setName("outdoor_co2_schedule")
      outdoor_co2_schedule.setScheduleTypeLimits(get_any_number_ppm(model))
      outdoor_co2_schedule.setToConstantValue(400.0) #400 ppm

      ##### Define ZoneAirContaminantBalance (required for CO2-based DCV)
      zone_air_contaminant_balance = model.getZoneAirContaminantBalance()
      zone_air_contaminant_balance.setCarbonDioxideConcentration(true)
      zone_air_contaminant_balance.setOutdoorCarbonDioxideSchedule(outdoor_co2_schedule)

      ##### Set CO2 controller in each space (required for CO2-based DCV)
      model.getSpaces.sort.each do |space|
        puts space.name.to_s
        zone = space.thermalZone
        if !zone.empty?
          zone = space.thermalZone.get
        end
        zone_control_co2 = OpenStudio::Model::ZoneControlContaminantController.new(zone.model)
        zone_control_co2.setName("#{space.name.to_s} Zone Control Contaminant Controller")
        zone_control_co2.setCarbonDioxideControlAvailabilitySchedule(indoor_co2_availability_schedule)
        zone_control_co2.setCarbonDioxideSetpointSchedule(indoor_co2_setpoint_schedule)
        zone.setZoneControlContaminantController(zone_control_co2)
      end

    end #if dcv_type == "Occupancy-based DCV" || dcv_type == "CO2-based DCV"

    ##### Loop through AirLoopHVACs
    model.getAirLoopHVACs.each do |air_loop|
      ##### Loop through AirLoopHVAC's supply nodes to:
      ##### (1) Find its AirLoopHVAC:OutdoorAirSystem using the supply node;
      ##### (2) Find Controller:OutdoorAir using AirLoopHVAC:OutdoorAirSystem;
      ##### (3) Get "Controller Mechanical Ventilation" from Controller:OutdoorAir.
      air_loop.supplyComponents.each do |supply_component|
        ##### Find AirLoopHVAC:OutdoorAirSystem of AirLoopHVAC using the supply node.
        hvac_component = supply_component.to_AirLoopHVACOutdoorAirSystem

        if !hvac_component.empty?
          ##### Find Controller:OutdoorAir using AirLoopHVAC:OutdoorAirSystem.
          hvac_component = hvac_component.get
          controller_oa = hvac_component.getControllerOutdoorAir

          ##### Get "Controller Mechanical Ventilation" from Controller:OutdoorAir.
          controller_mv = controller_oa.controllerMechanicalVentilation

          ##### Set "Demand Controlled Ventilation" to "Yes" or "No" in Controller:MechanicalVentilation depending on dcv_type.
          if dcv_type == "Occupancy-based DCV" || dcv_type == "CO2-based DCV"
            if controller_mv.demandControlledVentilation != true
              controller_mv.setDemandControlledVentilation(true)
            end
          elsif dcv_type == "No DCV"
            if controller_mv.demandControlledVentilation != false
              controller_mv.setDemandControlledVentilation(false)
            end
          end

          ##### Set the "System Outdoor Air Method" field based on dcv_type in the Controller:MechanicalVentilation object
          if dcv_type == "Occupancy-based DCV"
            controller_mv.setSystemOutdoorAirMethod("ZoneSum")
          elsif dcv_type == "CO2-based DCV"
            controller_mv.setSystemOutdoorAirMethod("IndoorAirQualityProcedure")
          end
        end #if !hvac_component.empty?

      end #air_loop.supplyComponents.each do |supply_component|
    end #model.getAirLoopHVACs.each do |air_loop|
  end #def model_enable_demand_controlled_ventilation


  def set_lighting_per_area_led_lighting(space_type, definition, lighting_per_area_led_lighting)
    occ_sens_lpd_frac = 1.0
    # NECB2011 space types that require a reduction in the LPD to account for
    # the requirement of an occupancy sensor (8.4.4.6(3) and 4.2.2.2(2))
    reduce_lpd_spaces = ['Classroom/lecture/training', 'Conf./meet./multi-purpose', 'Lounge/recreation',
                         'Conf./meet./multi-purpose', 'Washroom-sch-A', 'Washroom-sch-B', 'Washroom-sch-C', 'Washroom-sch-D',
                         'Washroom-sch-E', 'Washroom-sch-F', 'Washroom-sch-G', 'Washroom-sch-H', 'Washroom-sch-I',
                         'Dress./fitt. - performance arts', 'Locker room', 'Locker room-sch-A', 'Locker room-sch-B',
                         'Locker room-sch-C', 'Locker room-sch-D', 'Locker room-sch-E', 'Locker room-sch-F', 'Locker room-sch-G',
                         'Locker room-sch-H', 'Locker room-sch-I', 'Retail - dressing/fitting']
    if reduce_lpd_spaces.include?(space_type.standardsSpaceType.get)
      # Note that "Storage area", "Storage area - refrigerated", "Hospital - medical supply" and "Office - enclosed"
      # LPD should only be reduced if their space areas are less than specific area values.
      # This is checked in a space loop after this function in the calling routine.
      occ_sens_lpd_frac = 0.9
    end
    definition.setWattsperSpaceFloorArea(OpenStudio.convert(lighting_per_area_led_lighting.to_f * occ_sens_lpd_frac, 'W/ft^2', 'W/m^2').get)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set LPD to #{lighting_per_area_led_lighting} W/ft^2.")
  end



end