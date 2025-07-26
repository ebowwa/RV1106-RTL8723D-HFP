# RTL8723D Bluetooth Firmware

These firmware files were extracted from the RV1106 device at `/lib/firmware/rtlbt/`.

## Files

1. **rtl8723d_fw** (51,980 bytes)
   - Main firmware binary for RTL8723D Bluetooth controller
   - Header shows "Realtech" signature
   - Contains the actual Bluetooth stack firmware

2. **rtl8723d_config** (47 bytes)
   - Configuration parameters for the RTL8723D
   - Contains device-specific settings like:
     - UART baud rate configuration
     - GPIO pin mappings
     - Power settings
     - RF parameters

## Usage

These files are required for initializing the RTL8723D Bluetooth controller. They should be placed in:
- Linux: `/lib/firmware/rtlbt/` or `/lib/firmware/`
- Android: `/vendor/firmware/` or `/system/etc/firmware/`

## Loading Process

1. The Bluetooth driver (btrtl) looks for these files during initialization
2. First loads the firmware (rtl8723d_fw)
3. Then applies the configuration (rtl8723d_config)
4. The configuration can be customized for specific hardware implementations

## Compatibility

These firmware files are compatible with:
- RTL8723D Bluetooth controller
- RTL8723DS (SDIO variant)
- RTL8723DU (USB variant)

## Tools

To use with hciattach:
```bash
hciattach -s 115200 /dev/ttyS5 rtk_h5
```

Or with btattach:
```bash
btattach -B /dev/ttyS5 -P h5 -S 1500000
```

## Notes

- The firmware expects H5 (3-wire UART) protocol by default
- Baud rate can be 115200 or 1500000 depending on configuration
- Some implementations may require GPIO control for power/reset