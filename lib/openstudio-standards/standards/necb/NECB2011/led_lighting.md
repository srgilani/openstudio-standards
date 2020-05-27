# High Performance LED Lighting Measure
This measure adds a new lighting definition regarding LED lighting in each space of the model, 
and replace the existing lighting definition in the spaces with the LED lighting definitions.

# Description
The workflow of this measure is as follows:
1. Define a new LED lighting definition for each space.
2. Use the new LED lighting definition instead of the existing lighting definition in each space.

# Approach
This measure follows the functions already existed in the BTAP environment with respect to setting lights in spaces.<br>
However, a new function called **set_lighting_per_area_led_lighting** has been created to set lighting power density (LPD) for LED lighting.<br>
Moreover, the **apply_standard_lights** function (lighting.rb) has been modified to set the three fields of 
fraction radiant, fraction visible, and return air fraction for LED lighting.<br> 
Furthermore, a variable called **lights_led** has been added to the **apply_standard_lights** function to specify if LED lightings are used in the model or not.

# Testing Plan
* This measure has been called in the **apply_loads** function (necb_2011.rb) -> **model_add_loads** function (necb_2011.rb) 
-> **space_type_apply_internal_loads** function (beps_compliance_path.rb) -> **apply_standard_lights** function (lighting.rb).
* This measure was tested for NECB 2011 full service restaurant archetype.
Note that since setting the four fields of LPD, fraction radiant, fraction visible, and return air fraction are upon another BTAP task, 
for testing the measure, the associated values already exist in NECB2011/data/space_types.json regarding lighting were used.

# Waiting On
* There are four fields in the OS:Lights:Definition object that need to be added for the LED lighting in NECB2011/data/space_types.json, as follows:
  1. LPD (W/m<sup>2</sup>)
  2. Fraction Radiant
  3. Fraction Visible
  4. Return Air Fraction

* Once the above valuses are included in space_types.json, the **apply_standard_lights** function in lighting.rb (the first 20 lines) should be revised.