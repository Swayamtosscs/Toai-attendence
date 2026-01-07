# Android Par App Run Karne Ke Steps

## Option 1: Emulator Use Karein (Abhi Available Hai)

### Step 1: Emulator Launch Karein
```bash
flutter emulators --launch Medium_Phone_API_36.0
```

### Step 2: Emulator Start Hone Ka Wait Karein (30-60 seconds)

### Step 3: App Run Karein
```bash
flutter run
```
Ya phir device select karein:
```bash
flutter run -d <device-id>
```

## Option 2: Physical Android Device

### Step 1: USB Debugging Enable Karein
1. Phone Settings → About Phone
2. Build Number ko 7 baar tap karein (Developer Options unlock)
3. Settings → Developer Options
4. USB Debugging ON karein

### Step 2: Phone Ko Computer Se Connect Karein
- USB cable se connect karein
- Phone par "Allow USB Debugging" permission grant karein

### Step 3: Device Check Karein
```bash
adb devices
```
Agar device dikhe to ready hai!

### Step 4: App Run Karein
```bash
flutter run
```

## Quick Commands

```bash
# Available devices dekhne ke liye
flutter devices

# Emulator list dekhne ke liye
flutter emulators

# Emulator launch karne ke liye
flutter emulators --launch Medium_Phone_API_36.0

# App run karne ke liye (automatic device select)
flutter run

# Specific device par run karne ke liye
flutter run -d <device-id>
```

## Troubleshooting

### Agar device detect nahi ho raha:
1. USB cable check karein
2. USB Debugging verify karein
3. `adb kill-server` then `adb start-server` run karein
4. Phone restart karein

### Agar emulator slow hai:
- Emulator settings mein RAM increase karein
- Hardware acceleration enable karein



