
# Custom changes for the LargeOffice prototype.
# These are changes that are inconsistent with other prototype
# building types.
module College
  def model_custom_hvac_tweaks(building_type, climate_zone, prototype_input, model)
    #   Infiltration		"Peak: 0.2016 cfm/sf of above grade exterior wall surface area, adjusted by wind (when fans turn off)
    # Off Peak: 25% of peak infiltration rate (when fans turn on)
    # Additional infiltration through building entrance"		

  end

  def model_custom_internal_load_tweaks(building_type, climate_zone, prototype_input, model)
    #Plugload:Average power density (W/ft2)		See under Zone Summary (MISSING)
    #Schedule		See under Schedules
    #Zone Control Type: minimum supply air at 30% of the zone design peak supply air
  end

  def model_custom_elevator_tweaks(building_type, climate_zone, prototype_input, model)
    #"    Peak Motor Power
        #(W/elevator)"		16,055
    #     Heat Gain to Building		Interior
    # "    Peak Fan/lights Power
    #     (W/elevator)"		161.9

  end


  def model_custom_swh_tweaks(model, building_type, climate_zone, prototype_input)

    return true
  end

  def model_custom_geometry_tweaks(building_type, climate_zone, prototype_input, model)

    return true
  end
end
