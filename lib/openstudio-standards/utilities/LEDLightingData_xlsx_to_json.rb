#converts the led_lighting_data_necb2011.xlsx spreadsheet into a ruby hash using the rubyXL gem

require 'csv'
require 'json'
require 'rubyXL'
require 'roo'

begin

  csv_file = "#{File.dirname(__FILE__)}/../btap/csvFile1.csv"
  input_file = "#{File.dirname(__FILE__)}/../btap/led_lighting_data_necb2011.xlsx" #led_lighting_data_necb2011  led_lighting_data_necb2015  led_lighting_data_necb2017

  CSV.open(csv_file, "wb") do |csv|
    workbook = Roo::Spreadsheet.open input_file
    worksheets = workbook.sheets
    # puts "Found #{worksheets.count} worksheets"
    worksheets.each do |worksheet|
      # puts worksheet
      workbook.sheet(worksheet).each_row_streaming do |row|
        # puts row
        # row_cells = row.map { |cell| cell.value }row_data = []
        row_data = []
        (0...row.size).each do |col_idx|
          begin
            cell = row[col_idx]
            val = cell.value
            row_data << val
          rescue NoMethodError
            row_data << ""
          end
        end
        # puts row_data
        csv << row_data
        # puts csv
      end
    end
  end

rescue;
end


data_json_hash = CSV.open(csv_file, :headers => true).map { |x| x.to_h }.to_json

File.write("#{File.dirname(__FILE__)}/../btap/csvToJsonUpdate.json",data_json_hash)

data_hash = JSON.parse(File.read("#{File.dirname(__FILE__)}/../btap/csvToJsonUpdate.json"))
# puts data_hash

data_hash.each do |info|
  info['lighting_per_area_w_per_m2'] = info['lighting_per_area_w_per_m2'].to_f
  info['lighting_per_area'] = info['lighting_per_area'].to_f
  info['lighting_fraction_to_return_air'] = info['lighting_fraction_to_return_air'].to_f
  info['lighting_fraction_radiant'] = info['lighting_fraction_radiant'].to_f
  info['lighting_fraction_visible'] = info['lighting_fraction_visible'].to_f
end

pretty_output = JSON.pretty_generate(data_hash)
puts pretty_output

File.delete("#{File.dirname(__FILE__)}/../btap/csvToJsonUpdate.json")

File.delete("#{File.dirname(__FILE__)}/../btap/csvFile1.csv")

File.write("#{File.dirname(__FILE__)}/../btap/led_lighting_data.json", pretty_output)
