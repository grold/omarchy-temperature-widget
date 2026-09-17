import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TempModel.js" as TempModel

BarWidget {
  id: root
  moduleName: "grold.temperature"

  // User configuration options
  property string activeFormat: setting("format", "compact")
  property string activeUnit: setting("unit", "C")
  readonly property int refreshInterval: Math.max(1000, parseInt(setting("interval", 3000), 10) || 3000)

  // Sensor state
  property var sensorModel: TempModel.emptyModel()
  property string lastUpdatedTime: ""
  property bool opened: false

  // Status and presentation
  readonly property int primaryTemp: sensorModel ? (sensorModel.primaryTemp || 0) : 0
  readonly property string status: TempModel.statusLevel(primaryTemp)
  readonly property string iconGlyph: TempModel.thermometerIcon(primaryTemp)
  readonly property string displayText: TempModel.formatBarLabel(sensorModel, activeFormat, activeUnit)

  // Color mapping based on temperature level
  readonly property color tempColor: {
    if (!root.bar) return Color.foreground
    if (status === "critical") return root.bar.urgent || Color.urgent
    if (status === "hot") return "#f59e0b" // warning amber
    if (status === "warm") return Color.accent
    return root.bar.barForeground || Color.foreground
  }

  function refresh() {
    if (!queryProc.running) {
      queryProc.running = true
    }
  }

  function open() {
    opened = true
    refresh()
  }

  function close() {
    opened = false
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  function cycleFormat() {
    var next = TempModel.nextFormat(activeFormat)
    activeFormat = next
    persistSetting("format", next)
  }

  function toggleUnit() {
    var next = activeUnit === "C" ? "F" : "C"
    activeUnit = next
    persistSetting("unit", next)
  }

  function persistSetting(key, val) {
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("omarchy bar set " + root.moduleName + " " + key + " " + val)
    }
  }

  function openBtop() {
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("omarchy-launch-floating-terminal-with-presentation btop")
      close()
    }
  }

  // Shell IPC target
  IpcHandler {
    target: "grold.temperature"

    function refresh(): void { root.refresh() }
    function cycleFormat(): void { root.cycleFormat() }
    function toggleUnit(): void { root.toggleUnit() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
  }

  // Background sensor reader
  Process {
    id: queryProc
    command: [
      "bash",
      Qt.resolvedUrl("get-temps.sh").toString().replace(/^file:\/\//, "")
    ]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!text || text.trim().length === 0) return
        var model = TempModel.parseSensors(text)
        if (model && model.hasData) {
          root.sensorModel = model
          var now = new Date()
          var hrs = String(now.getHours()).padStart(2, "0")
          var mins = String(now.getMinutes()).padStart(2, "0")
          var secs = String(now.getSeconds()).padStart(2, "0")
          root.lastUpdatedTime = hrs + ":" + mins + ":" + secs
        }
      }
    }
  }

  // Polling timer
  Timer {
    id: pollTimer
    interval: root.refreshInterval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Bar Button representation
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.iconGlyph + " " + root.displayText
    foreground: root.tempColor
    fontSize: Style.font.caption
    horizontalMargin: 8
    verticalPadding: 6
    tooltipText: TempModel.formatTooltip(root.sensorModel, root.activeUnit)

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.cycleFormat()
      } else if (b === Qt.MiddleButton) {
        root.refresh()
      } else {
        root.toggle()
      }
    }
  }

  // Popup panel
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: true
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function") {
          root.bar.switchPanelFrom(root, direction)
        }
      }

      Flickable {
        id: panelScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: panelColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: panelColumn
          width: panelScroll.width
          spacing: Style.space(12)

          // 1. Header Row
          Item {
            width: parent.width
            height: Style.space(26)

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf2c9"
                color: root.tempColor
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: "TEMPERATURES"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              // btop launcher button
              BorderSurface {
                width: Style.space(56)
                height: Style.space(22)
                radius: Style.cornerRadius
                color: btopMouse.containsMouse ? Style.hoverFillFor(Color.accent, Color.accent) : "transparent"
                borderSpec: Border.controlSpec(btopMouse.containsMouse ? "hover-cursor" : "normal", Color.foreground, Color.accent)

                Row {
                  anchors.centerIn: parent
                  spacing: Style.space(4)
                  Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf0e4"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: Color.foreground
                  }
                  Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: "btop"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: Color.foreground
                  }
                }

                MouseArea {
                  id: btopMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openBtop()
                }

                PanelToolTip {
                  visible: btopMouse.containsMouse
                  text: "Launch btop hardware monitor in terminal"
                  fontFamily: Style.font.family
                }
              }

              // Refresh button
              PanelActionButton {
                iconText: "\uf021"
                tooltipText: "Refresh sensor readings"
                onClicked: root.refresh()
              }

              // Close button
              PanelActionButton {
                iconText: "\uf00d"
                tooltipText: "Close panel (Esc)"
                onClicked: root.close()
              }
            }
          }

          PanelSeparator { width: parent.width }

          // 2. Hero banner: Large temperature + status badge + unit toggle
          BorderSurface {
            width: parent.width
            height: Style.space(72)
            radius: Style.cornerRadius
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
            borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)

            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(16)

              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: root.iconGlyph
                color: root.tempColor
                font.family: Style.font.family
                font.pixelSize: Style.space(36)
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Row {
                  spacing: Style.space(4)

                  Text {
                    textFormat: Text.PlainText
                    anchors.baseline: unitText.baseline
                    text: TempModel.toUnit(root.primaryTemp, root.activeUnit) !== null
                      ? String(TempModel.toUnit(root.primaryTemp, root.activeUnit))
                      : "—"
                    color: root.tempColor
                    font.family: Style.font.family
                    font.pixelSize: Style.font.displayLarge
                    font.bold: true
                  }

                  Text {
                    id: unitText
                    textFormat: Text.PlainText
                    text: TempModel.unitSuffix(root.activeUnit)
                    color: Qt.darker(Color.foreground, 1.3)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.heading
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.sensorModel ? (root.sensorModel.cpu.label + " Package") : "Hardware Sensor"
                  color: Qt.darker(Color.foreground, 1.4)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Row {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              // Status pill
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: statusText.implicitWidth + Style.space(16)
                height: Style.space(24)
                radius: height / 2
                color: {
                  if (root.status === "critical") return Qt.rgba(1, 0.2, 0.2, 0.2)
                  if (root.status === "hot") return Qt.rgba(0.96, 0.62, 0.04, 0.2)
                  if (root.status === "warm") return Qt.rgba(0.2, 0.6, 1, 0.2)
                  return Qt.rgba(0.2, 0.8, 0.4, 0.2)
                }

                Text {
                  id: statusText
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: TempModel.statusLabel(root.primaryTemp)
                  color: root.tempColor
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              // Unit Switcher Button
              BorderSurface {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(48)
                height: Style.space(24)
                radius: Style.cornerRadius
                color: unitMouse.containsMouse ? Style.hoverFillFor(Color.accent, Color.accent) : "transparent"
                borderSpec: Border.controlSpec(unitMouse.containsMouse ? "hover-cursor" : "normal", Color.foreground, Color.accent)

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: root.activeUnit === "C" ? "°C" : "°F"
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                MouseArea {
                  id: unitMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleUnit()
                }

                PanelToolTip {
                  visible: unitMouse.containsMouse
                  text: "Click to toggle °C / °F"
                  fontFamily: Style.font.family
                }
              }
            }
          }

          // 3. CPU Section
          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "PROCESSOR (CPU)"
            }

            // Overall CPU package bar
            BorderSurface {
              width: parent.width
              height: Style.space(40)
              radius: Style.cornerRadius
              color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.03)
              borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)

              Column {
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(6)

                Row {
                  width: parent.width
                  Item {
                    width: parent.width - tempValText.implicitWidth
                    height: tempValText.implicitHeight
                    Text {
                      textFormat: Text.PlainText
                      text: "Package (Overall)"
                      color: Color.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }
                  }
                  Text {
                    id: tempValText
                    textFormat: Text.PlainText
                    text: TempModel.formatValue(root.sensorModel.cpu.temp, root.activeUnit)
                    color: root.tempColor
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }
                }

                // Progress Bar
                Rectangle {
                  width: parent.width
                  height: Style.space(4)
                  radius: height / 2
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)

                  Rectangle {
                    width: parent.width * Math.min(1.0, Math.max(0.0, (root.sensorModel.cpu.temp || 0) / (root.sensorModel.cpu.crit || 100)))
                    height: parent.height
                    radius: height / 2
                    color: root.tempColor
                  }
                }
              }
            }

            // CPU Cores Grid
            Grid {
              width: parent.width
              columns: Math.max(1, Math.min(4, root.sensorModel.cpu.cores.length))
              spacing: Style.space(6)

              Repeater {
                model: root.sensorModel.cpu.cores

                BorderSurface {
                  width: (panelColumn.width - (parent.columns - 1) * Style.space(6)) / parent.columns
                  height: Style.space(44)
                  radius: Style.cornerRadius
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.03)
                  borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)

                  Column {
                    anchors.centerIn: parent
                    spacing: Style.space(2)

                    Text {
                      textFormat: Text.PlainText
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: modelData.name
                      color: Qt.darker(Color.foreground, 1.4)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      textFormat: Text.PlainText
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: TempModel.formatValue(modelData.temp, root.activeUnit)
                      color: {
                        var st = TempModel.statusLevel(modelData.temp)
                        if (st === "critical") return root.bar ? root.bar.urgent : Color.urgent
                        if (st === "hot") return "#f59e0b"
                        if (st === "warm") return Color.accent
                        return Color.foreground
                      }
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }
                  }
                }
              }
            }
          }

          // 4. Storage Section (NVMe / SSD)
          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.sensorModel && root.sensorModel.storage && root.sensorModel.storage.length > 0

            PanelSectionHeader {
              text: "STORAGE (NVME / DRIVES)"
            }

            Repeater {
              model: root.sensorModel ? root.sensorModel.storage : []

              BorderSurface {
                width: panelColumn.width
                height: Style.space(38)
                radius: Style.cornerRadius
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.03)
                borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)

                Item {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)

                  Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(8)

                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: "\uf0a0"
                      color: Color.accent
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.chip + " " + modelData.name
                      color: Color.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                    }
                  }

                  Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: TempModel.formatValue(modelData.temp, root.activeUnit)
                    color: {
                      var st = TempModel.statusLevel(modelData.temp)
                      if (st === "critical") return root.bar ? root.bar.urgent : Color.urgent
                      if (st === "hot") return "#f59e0b"
                      return Color.foreground
                    }
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }
                }
              }
            }
          }

          // 5. GPU Section (if available)
          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.sensorModel && root.sensorModel.gpu !== null

            PanelSectionHeader {
              text: "GRAPHICS (GPU)"
            }

            BorderSurface {
              width: panelColumn.width
              height: Style.space(42)
              radius: Style.cornerRadius
              color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.03)
              borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)

              Item {
                anchors.fill: parent
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)

                Row {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf108"
                    color: Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.sensorModel && root.sensorModel.gpu ? root.sensorModel.gpu.label : "GPU"
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                Text {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: root.sensorModel && root.sensorModel.gpu ? TempModel.formatValue(root.sensorModel.gpu.temp, root.activeUnit) : "—"
                  color: {
                    var t = root.sensorModel && root.sensorModel.gpu ? root.sensorModel.gpu.temp : 0
                    var st = TempModel.statusLevel(t)
                    if (st === "critical") return root.bar ? root.bar.urgent : Color.urgent
                    if (st === "hot") return "#f59e0b"
                    return Color.foreground
                  }
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }
            }
          }

          // 6. Motherboard / System Section
          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.sensorModel && root.sensorModel.system && root.sensorModel.system.length > 0

            PanelSectionHeader {
              text: "MOTHERBOARD & SYSTEM"
            }

            Grid {
              width: parent.width
              columns: Math.max(1, Math.min(3, root.sensorModel ? root.sensorModel.system.length : 1))
              spacing: Style.space(6)

              Repeater {
                model: root.sensorModel ? root.sensorModel.system : []

                BorderSurface {
                  width: (panelColumn.width - (parent.columns - 1) * Style.space(6)) / parent.columns
                  height: Style.space(42)
                  radius: Style.cornerRadius
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.03)
                  borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)

                  Column {
                    anchors.centerIn: parent
                    spacing: Style.space(2)

                    Text {
                      textFormat: Text.PlainText
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: modelData.chip + " " + modelData.name
                      color: Qt.darker(Color.foreground, 1.4)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      textFormat: Text.PlainText
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: TempModel.formatValue(modelData.temp, root.activeUnit)
                      color: Color.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                    }
                  }
                }
              }
            }
          }

          PanelSeparator { width: parent.width }

          // 7. Footer: Display mode switch & Last updated
          Item {
            width: parent.width
            height: Style.space(26)

            // Display Mode Switcher
            BorderSurface {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: modeText.implicitWidth + Style.space(16)
              height: Style.space(22)
              radius: Style.cornerRadius
              color: modeMouse.containsMouse ? Style.hoverFillFor(Color.accent, Color.accent) : "transparent"
              borderSpec: Border.controlSpec(modeMouse.containsMouse ? "hover-cursor" : "normal", Color.foreground, Color.accent)

              Text {
                id: modeText
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "Bar: " + TempModel.formatDisplayName(root.activeFormat)
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: modeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cycleFormat()
              }

              PanelToolTip {
                visible: modeMouse.containsMouse
                text: "Click to cycle bar display format"
                fontFamily: Style.font.family
              }
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.lastUpdatedTime !== "" ? ("Updated " + root.lastUpdatedTime) : "Reading sensors..."
              color: Qt.darker(Color.foreground, 1.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
