# Omarchy Temperature Widget (`grold.temperature`)

A native Quickshell bar widget and hardware temperature monitor for the Omarchy desktop shell.

![Omarchy Plugin](https://img.shields.io/badge/omarchy-plugin-blue)
![Kind](https://img.shields.io/badge/kind-bar--widget-green)

---

## Features

- **Comprehensive Hardware Monitoring**:
  - **Processor (CPU)**: Overall CPU Package / Tctl / Tdie temperature and individual core temperatures (Core 0, Core 1, ...).
  - **Storage**: NVMe SSDs and drives (Composite, Sensor 1/2).
  - **Graphics (GPU)**: Dedicated GPU temperatures (AMD, NVIDIA via `nvidia-smi`, Intel Arc/Xe).
  - **Motherboard & System**: Platform Controller Hub (PCH), ACPI thermal zones, and SuperIO sensors.
- **Dynamic Status & Colors**:
  - Thermometer icon updates dynamically according to heat level (`` < 50°C, `` 50–64°C, `` 65–74°C, `` 75–84°C, `` ≥ 85°C).
  - Color changes from normal foreground to warm accent, warning amber (≥ 75°C), and critical urgent red (≥ 85°C).
- **Interactive Bar Button**:
  - **Left Click**: Toggles the detailed popup panel.
  - **Right Click**: Cycles through bar display modes directly from the bar.
  - **Middle Click**: Forces an immediate sensor refresh.
  - **Hover**: Shows a formatted multi-line breakdown of all detected sensors.
- **Detailed Popup Panel**:
  - Hero banner with current temperature, status pill, and instant `°C` / `°F` unit toggle.
  - CPU section with visual progress bar and grid of per-core readings.
  - Storage section listing NVMe / SSD drive temperatures.
  - Graphics section for discrete / integrated GPUs.
  - Motherboard & System section for PCH and ACPI zones.
  - Quick **btop** launcher button to open the terminal system monitor in a floating window.
- **Multiple Bar Display Modes**:
  - `compact`: `59°C`
  - `cpu`: `CPU 59°C`
  - `multi`: `CPU 59° SSD 58°`
  - `max`: `Max 59°C`

---

## File Structure

```
grold.temperature/
├── manifest.json       # Omarchy plugin manifest
├── Temperature.qml     # BarWidget component & popup panel
├── TempModel.js        # Parser and data presentation logic
├── get-temps.sh        # Fast multi-backend sensor collection helper
└── README.md           # Documentation
```

---

## Bar Placement & Positioning

### Position in the Top Bar

Omarchy allows the bar to be placed at the top, bottom, left, or right edge of the screen:

```bash
# Place the bar at the top edge of the screen:
omarchy bar position top

# Or return to the bottom:
omarchy bar position bottom
```

### Widget Placement on the Bar

The widget is placed in `~/.config/omarchy/shell.json`. You can move it using the `omarchy bar` command:

```bash
# Place in the right section (status icons):
omarchy bar put grold.temperature --section right

# Move before or after specific widgets:
omarchy bar move grold.temperature --after omarchy.tray
omarchy bar move grold.temperature --before omarchy.clock
```

---

## Configuration

In `~/.config/omarchy/shell.json`, configure options under the layout entry:

```json
{
  "id": "grold.temperature",
  "format": "compact",
  "unit": "C",
  "interval": 3000
}
```

Or configure dynamically via CLI:

```bash
# Change format: compact, cpu, multi, max
omarchy bar set grold.temperature format cpu

# Change unit: C or F
omarchy bar set grold.temperature unit F

# Change update interval (in ms):
omarchy bar set grold.temperature interval 2000
```

---

## Shell IPC Controls

The widget exposes an IPC handler for scripting or hotkey binding:

```bash
# Toggle the popup panel:
quickshell ipc -p /usr/share/omarchy/shell call grold.temperature toggle

# Force immediate temperature refresh:
quickshell ipc -p /usr/share/omarchy/shell call grold.temperature refresh

# Cycle display format:
quickshell ipc -p /usr/share/omarchy/shell call grold.temperature cycleFormat

# Toggle Celsius / Fahrenheit:
quickshell ipc -p /usr/share/omarchy/shell call grold.temperature toggleUnit
```
