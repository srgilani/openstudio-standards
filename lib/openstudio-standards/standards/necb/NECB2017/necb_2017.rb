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

  def set_lighting_per_area_led_lighting(space_type, definition, lighting_per_area_led_lighting)
    ##### Since Atrium's LPD for LED lighting depends on atrium's height, the height of the atrium (if applicable) should be found.
    standards_space_type = space_type.standardsSpaceType.is_initialized ? space_type.standardsSpaceType.get : nil
    puts standards_space_type
    space_type_atrium = ['Atrium (height < 6m)-sch-A','Atrium (height < 6m)-sch-B','Atrium (height < 6m)-sch-C','Atrium (height < 6m)-sch-D',
                         'Atrium (height < 6m)-sch-E','Atrium (height < 6m)-sch-F','Atrium (height < 6m)-sch-G','Atrium (height < 6m)-sch-H',
                         'Atrium (height < 6m)-sch-I','Atrium (height < 6m)-sch-J','Atrium (height < 6m)-sch-K',
                         'Atrium (6 =< height <= 12m)-sch-A','Atrium (6 =< height <= 12m)-sch-B','Atrium (6 =< height <= 12m)-sch-B',
                         'Atrium (6 =< height <= 12m)-sch-D','Atrium (6 =< height <= 12m)-sch-E','Atrium (6 =< height <= 12m)-sch-F',
                         'Atrium (6 =< height <= 12m)-sch-G','Atrium (6 =< height <= 12m)-sch-H','Atrium (6 =< height <= 12m)-sch-I',
                         'Atrium (6 =< height <= 12m)-sch-J','Atrium (6 =< height <= 12m)-sch-K',
                         'Atrium (height > 12m)-sch-A','Atrium (height > 12m)-sch-B','Atrium (height > 12m)-sch-C',
                         'Atrium (height > 12m)-sch-D','Atrium (height > 12m)-sch-E','Atrium (height > 12m)-sch-F',
                         'Atrium (height > 12m)-sch-G','Atrium (height > 12m)-sch-H','Atrium (height > 12m)-sch-I',
                         'Atrium (height > 12m)-sch-J','Atrium (height > 12m)-sch-K']
    if [standards_space_type].any? {|word| space_type_atrium.include?(word)} == true
      puts "#{standards_space_type} - has atrium"  #space_type.name.to_s
      ##### Get the atrium height
      space_height = led_lighting_atrium(space_type: space_type)
      # puts space_type
      # puts space_height
      # raise('check if standards_space_type is atrium')
      if space_height <= 12.0   #TODO to be corrected as Mike inputs
        lighting_per_area_led_lighting_atrium = (1.06 * space_height) * 0.092903 # W/ft2
      else
        lighting_per_area_led_lighting_atrium = (4.3 + 0.71 * space_height) * 0.092903 # W/ft2
      end
      definition.setWattsperSpaceFloorArea(OpenStudio.convert(lighting_per_area_led_lighting_atrium.to_f, 'W/ft^2', 'W/m^2').get)
    else
      definition.setWattsperSpaceFloorArea(OpenStudio.convert(lighting_per_area_led_lighting.to_f, 'W/ft^2', 'W/m^2').get)
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set LPD to #{lighting_per_area_led_lighting} W/ft^2.")
  end

end
