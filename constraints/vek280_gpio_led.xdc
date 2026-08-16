# VEK280 user GPIO LEDs.  gpio_led[0] through gpio_led[3] drive DS6 through
# DS3, respectively, from the output-only AXI GPIO peripheral.
set_property PACKAGE_PIN AT12 [get_ports {gpio_led[0]}]
set_property PACKAGE_PIN AT11 [get_ports {gpio_led[1]}]
set_property PACKAGE_PIN AU13 [get_ports {gpio_led[2]}]
set_property PACKAGE_PIN AT13 [get_ports {gpio_led[3]}]
set_property IOSTANDARD LVCMOS15 [get_ports {gpio_led[*]}]
