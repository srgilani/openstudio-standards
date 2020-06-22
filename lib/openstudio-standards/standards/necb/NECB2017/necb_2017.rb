# This class holds methods that apply NECB2017 rules.
# @ref [References::NECB2017]
class NECB2017 < NECB2015
  @template = self.new.class.name # rubocop:disable Style/ClassVars
  register_standard(@template)

  def initialize
    super()
    @template = self.class.name
    @standards_data = self.load_standards_database_new()
    self.corrupt_standards_database()
  end

  def load_standards_database_new()
    #load NECB2011 data.
    super()

    if __dir__[0] == ':' # Running from OpenStudio CLI
      embedded_files_relative('data/', /.*\.json/).each do |file|
        data = JSON.parse(EmbeddedScripting.getFileAsString(file))
        if !data['tables'].nil?
          @standards_data['tables'] = [*@standards_data['tables'], *data['tables']].to_h
        elsif !data['constants'].nil?
          @standards_data['constants'] = [*@standards_data['constants'], *data['constants']].to_h
        elsif !data['constants'].nil?
          @standards_data['formulas'] = [*@standards_data['formulas'], *data['formulas']].to_h
        end
      end
    else
      files = Dir.glob("#{File.dirname(__FILE__)}/data/*.json").select {|e| File.file? e}
      files.each do |file|
        data = JSON.parse(File.read(file))
        if !data['tables'].nil?
          @standards_data['tables'] = [*@standards_data['tables'], *data['tables']].to_h
        elsif !data['constants'].nil?
          @standards_data['constants'] = [*@standards_data['constants'], *data['constants']].to_h
        elsif !data['formulas'].nil?
          @standards_data['formulas'] = [*@standards_data['formulas'], *data['formulas']].to_h
        end
      end
    end
    #Write test report file.
    # Write database to file.
    # File.open(File.join(File.dirname(__FILE__), '..', 'NECB2017.json'), 'w') {|f| f.write(JSON.pretty_generate(@standards_data))}

    return @standards_data
  end

  def set_lighting_per_area_led_lighting(space_type, definition, lighting_per_area_led_lighting, scale, space_height)
    puts "#{space_type.name.to_s} - 'space_height' - #{space_height.to_s}"
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

    # ##### Since Atrium's LPD for LED lighting depends on atrium's height, the height of the atrium (if applicable) should be found.
    standards_space_type = space_type.standardsSpaceType.is_initialized ? space_type.standardsSpaceType.get : nil #Sara
    if standards_space_type.include? 'Atrium' #TODO: Note that since none of the archetypes has Atrium, this was tested for 'Dining'. #Atrium
      puts "#{standards_space_type} - has atrium"  #space_type.name.to_s
      # puts space_height
      if space_height < 12.0
        lighting_per_area_led_lighting_atrium = (1.06 * space_height) * 0.092903 # W/ft2
      else #i.e. space_height >= 12.0
        lighting_per_area_led_lighting_atrium = (4.3 + 0.71 * space_height) * 0.092903 # W/ft2
      end
      puts "#{standards_space_type} - has lighting_per_area_led_lighting_atrium - #{lighting_per_area_led_lighting_atrium}"
      lighting_per_area_led_lighting = lighting_per_area_led_lighting_atrium * scale
    end

    definition.setWattsperSpaceFloorArea(OpenStudio.convert(lighting_per_area_led_lighting.to_f * occ_sens_lpd_frac, 'W/ft^2', 'W/m^2').get)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set LPD to #{lighting_per_area_led_lighting} W/ft^2.")
  end

end
