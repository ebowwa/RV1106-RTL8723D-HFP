# Weekend Plan for Bluetooth HFP Solution

## Saturday - Raspberry Pi Testing

### Why Raspberry Pi?
- Native Linux environment (no cross-compilation)
- Package manager available (`apt`)
- Can directly install and test different Bluetooth stacks
- Similar ARM architecture to RV1106

### Test Plan

#### 1. Setup Raspberry Pi with RTL8723D (if available)
```bash
# Install required packages
sudo apt update
sudo apt install -y bluez bluez-tools ofono bluealsa pulseaudio-module-bluetooth

# Check if using RTL8723D or built-in Bluetooth
hciconfig -a
```

#### 2. Test Different HFP Solutions

**Test A: BlueALSA with HFP-AG Mode**
```bash
# Quick workaround we discovered
sudo systemctl stop pulseaudio
sudo bluealsa -p hfp-ag -p a2dp-sink &
sudo bluealsa-aplay 00:00:00:00:00:00 &
```

**Test B: oFono + BlueALSA**
```bash
# Proper HFP support
sudo systemctl start ofono
sudo ofonod -d &
sudo bluealsa -p a2dp-sink -p a2dp-source &  # A2DP only
```

**Test C: PulseAudio**
```bash
# Traditional approach
sudo systemctl start pulseaudio
pactl load-module module-bluetooth-discover
pactl load-module module-bluetooth-policy
```

**Test D: PipeWire (if available)**
```bash
# Modern approach
sudo apt install pipewire pipewire-pulse wireplumber
systemctl --user start pipewire wireplumber
```

#### 3. Measure and Compare
- HFP connection stability
- Audio quality (CVSD vs mSBC)
- CPU usage: `top -p $(pgrep -f "bluealsa|ofono|pulse|pipewire")`
- Latency: `pactl list sinks | grep Latency`

#### 4. Document Working Configuration
Create `raspberry-pi-results.md` with:
- Which solution works best
- Configuration files needed
- Performance metrics
- How to apply to RV1106

## Sunday - HATs Button Integration

### Goal
Fix the Bluetooth control button on the HAT (Hardware Attached on Top)

### Plan

#### 1. Identify Button GPIO
```python
# Test script to find button
import RPi.GPIO as GPIO
import time

GPIO.setmode(GPIO.BCM)
for pin in range(2, 28):  # Test common GPIO pins
    try:
        GPIO.setup(pin, GPIO.IN, pull_up_down=GPIO.PUD_UP)
        print(f"Monitoring GPIO {pin}...")
        initial = GPIO.input(pin)
        time.sleep(0.1)
        if GPIO.input(pin) != initial:
            print(f"Button might be on GPIO {pin}")
    except:
        pass
```

#### 2. Create Button Handler
```python
# bluetooth_button.py
import RPi.GPIO as GPIO
import subprocess
import time

BUTTON_GPIO = 23  # Replace with actual pin

def button_callback(channel):
    """Handle button press"""
    print("Button pressed!")
    
    # Check Bluetooth status
    result = subprocess.run(['hciconfig', 'hci0'], capture_output=True, text=True)
    
    if 'UP RUNNING' in result.stdout:
        # Bluetooth is on, turn it off
        subprocess.run(['sudo', 'hciconfig', 'hci0', 'down'])
        print("Bluetooth OFF")
    else:
        # Bluetooth is off, turn it on
        subprocess.run(['sudo', 'hciconfig', 'hci0', 'up'])
        subprocess.run(['sudo', 'hciconfig', 'hci0', 'piscan'])
        print("Bluetooth ON")

GPIO.setmode(GPIO.BCM)
GPIO.setup(BUTTON_GPIO, GPIO.IN, pull_up_down=GPIO.PUD_UP)
GPIO.add_event_detect(BUTTON_GPIO, GPIO.FALLING, 
                      callback=button_callback, 
                      bouncetime=300)

print(f"Monitoring button on GPIO {BUTTON_GPIO}")
try:
    while True:
        time.sleep(1)
except KeyboardInterrupt:
    GPIO.cleanup()
```

#### 3. Advanced Button Functions
- **Single press**: Toggle Bluetooth on/off
- **Double press**: Switch between A2DP and HFP
- **Long press**: Reset Bluetooth stack
- **Triple press**: Enter pairing mode

#### 4. Integrate with BlueFusion
```python
# Add to BlueFusion
class ButtonController:
    def __init__(self, gpio_pin):
        self.gpio_pin = gpio_pin
        self.last_press_time = 0
        self.press_count = 0
        
    def handle_press(self):
        current_time = time.time()
        if current_time - self.last_press_time < 0.5:
            self.press_count += 1
        else:
            self.press_count = 1
            
        self.last_press_time = current_time
        
        # After 0.5s, execute action based on press count
        threading.Timer(0.5, self.execute_action).start()
        
    def execute_action(self):
        if self.press_count == 1:
            self.toggle_bluetooth()
        elif self.press_count == 2:
            self.switch_profile()
        elif self.press_count >= 3:
            self.enter_pairing_mode()
```

#### 5. Create SystemD Service
```ini
# /etc/systemd/system/bluetooth-button.service
[Unit]
Description=Bluetooth HAT Button Handler
After=bluetooth.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /home/pi/bluetooth_button.py
Restart=always
User=pi

[Install]
WantedBy=multi-user.target
```

### Expected Outcomes

**Saturday**:
- Know which Bluetooth stack works best for HFP
- Have working configuration to apply to RV1106
- Performance benchmarks for each solution

**Sunday**:
- HAT button working for Bluetooth control
- Multiple functions mapped to button presses
- SystemD service for automatic startup
- Integration plan for RV1106

## Notes for RV1106 Application

After weekend testing, apply findings:

1. **If oFono works best on Pi**:
   - Use pre-built oFono ARM package
   - Or complete the Codespaces build

2. **If BlueALSA HFP-AG works on Pi**:
   - Simple config change on RV1106
   - No additional software needed

3. **Button integration**:
   - Find equivalent GPIO on RV1106
   - Adapt Python script for RV1106's GPIO library

## Repository Updates

Create branches for each day:
```bash
# Saturday
git checkout -b raspberry-pi-hfp-testing
# Document all findings

# Sunday  
git checkout -b hats-button-integration
# Add button control code
```

Then merge everything back to main with complete solution!