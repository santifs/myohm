# ERC triage

Generated from the current KiCad JSON report. No new electrical checks suppressed.

| Sheet | Severity | Type | Evidence |
| --- | --- | --- | --- |
| / | warning | isolated_pin_label | Label connected to only one pin: Label 'P0.04/AIN0' |
| / | warning | isolated_pin_label | Label connected to only one pin: Label 'P0.10/TRACEDATA1' |
| / | warning | isolated_pin_label | Label connected to only one pin: Label 'GPIO2' |
| / | warning | isolated_pin_label | Label connected to only one pin: Label 'GPIO3' |
| / | warning | isolated_pin_label | Label connected to only one pin: Label 'GPIO4' |
| /AD5941/ | warning | multiple_net_names | Both AVDD_2 and DVDD are attached to the same items; AVDD_2 will be used in the netlist: Global Label 'AVDD_2'; Global Label 'DVDD' |
| /Micro/ | error | power_pin_not_driven | Input Power pin not driven by any Output Power pins: Symbol U1 Pin A19 [VDD, Power input, Line] |
| /Micro/ | error | power_pin_not_driven | Input Power pin not driven by any Output Power pins: Symbol U1 Pin 104 [VSS_PAD, Power input, Line] |
| /Micro/ | warning | multiple_net_names | Both RESET_AD and P0.02{slash}NFC1 are attached to the same items; RESET_AD will be used in the netlist: Global Label 'RESET_AD'; Label 'P0.02/NFC1' |
| /Micro/ | warning | multiple_net_names | Both AD_INT and P0.03{slash}NFC2 are attached to the same items; AD_INT will be used in the netlist: Global Label 'AD_INT'; Label 'P0.03/NFC2' |
| /Micro/ | warning | multiple_net_names | Both AD_SCLK and P0.09{slash}TRACEDATA2 are attached to the same items; AD_SCLK will be used in the netlist: Global Label 'AD_SCLK'; Label 'P0.09/TRACEDATA2' |
| /Micro/ | warning | multiple_net_names | Both AD_MOSI and P0.13{slash}QSPI0 are attached to the same items; AD_MOSI will be used in the netlist: Global Label 'AD_MOSI'; Label 'P0.13/QSPI0' |
| /Micro/ | warning | multiple_net_names | Both AD_CS and P0.16{slash}QSPI3 are attached to the same items; AD_CS will be used in the netlist: Global Label 'AD_CS'; Label 'P0.16/QSPI3' |
| /Micro/ | warning | multiple_net_names | Both AD_MISO and P0.19 are attached to the same items; AD_MISO will be used in the netlist: Global Label 'AD_MISO'; Label 'P0.19' |
| /Micro/ | warning | multiple_net_names | Both SCL_nPM and P0.24 are attached to the same items; SCL_nPM will be used in the netlist: Global Label 'SCL_nPM'; Label 'P0.24' |
| /Micro/ | warning | multiple_net_names | Both SDA_nPM and P0.26{slash}AIN5 are attached to the same items; SDA_nPM will be used in the netlist: Global Label 'SDA_nPM'; Label 'P0.26/AIN5' |
| /Micro/ | warning | multiple_net_names | Both INT_nPM and P0.28{slash}AIN7 are attached to the same items; INT_nPM will be used in the netlist: Global Label 'INT_nPM'; Label 'P0.28/AIN7' |
| /Micro/ | warning | multiple_net_names | Both PWR_BTN_nPM and P1.06 are attached to the same items; PWR_BTN_nPM will be used in the netlist: Global Label 'PWR_BTN_nPM'; Label 'P1.06' |
| /Power/ | error | power_pin_not_driven | Input Power pin not driven by any Output Power pins: Symbol #PWR058 Hidden pin  [VBAT, Power input, Line] |
| /Power/ | error | power_pin_not_driven | Input Power pin not driven by any Output Power pins: Symbol U2 Pin 21 [VBUS, Power input, Line] |
| /Power/ | error | pin_not_connected | Pin not connected: Symbol U2 Pin 25 [LED0, Output, Line] |
| /Power/ | error | pin_not_connected | Pin not connected: Symbol U2 Pin 26 [LED1, Output, Line] |
| /Power/ | error | pin_not_connected | Pin not connected: Symbol U2 Pin 27 [LED2, Output, Line] |
| /Power/ | error | pin_not_connected | Pin not connected: Symbol U2 Pin 3 [SW1, Power output, Line] |
| /Power/ | error | power_pin_not_driven | Input Power pin not driven by any Output Power pins: Symbol U2 Pin 6 [PVSS2, Power input, Line] |
| /Power/ | warning | multiple_net_names | Both SCL_nPM and SCL are attached to the same items; SCL_nPM will be used in the netlist: Global Label 'SCL_nPM'; Label 'SCL' |
| /Power/ | warning | multiple_net_names | Both SDA_nPM and SDA are attached to the same items; SDA_nPM will be used in the netlist: Global Label 'SDA_nPM'; Label 'SDA' |
| /Power/ | warning | multiple_net_names | Both INT_nPM and GPIO0 are attached to the same items; INT_nPM will be used in the netlist: Global Label 'INT_nPM'; Label 'GPIO0' |
| /Power/ | warning | multiple_net_names | Both PWR_BTN_nPM and GPIO1 are attached to the same items; PWR_BTN_nPM will be used in the netlist: Global Label 'PWR_BTN_nPM'; Label 'GPIO1' |
| /Power/ | warning | multiple_net_names | Both GND and VSET1 are attached to the same items; GND will be used in the netlist: Symbol #PWR054 Hidden pin 1 [GND, Power input, Line]; Label 'VSET1' |
| /Connectors and Mounting/ | error | power_pin_not_driven | Input Power pin not driven by any Output Power pins: Symbol #PWR085 Hidden pin  [VBUS', Power input, Line] |
