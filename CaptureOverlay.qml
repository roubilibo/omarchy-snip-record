import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property bool opened: false
  property string pendingAction: ""
  property string selectedMode: "screenshot"

  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color border: Color.menu.border
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property color scrim: Color.menu.scrim
  readonly property int radius: Style.cornerRadius

  function open(payloadJson) {
    root.selectedMode = "screenshot"
    freezeProcess.running = true
    openDelay.restart()
  }

  function dismiss(keepFreeze) {
    openDelay.stop()
    root.opened = false
    if (!keepFreeze)
      root.releaseFreeze()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "roubilibo.omarchy-snip-record")
  }

  function releaseFreeze() {
    handoffPoll.stop()
    handoffTimeout.stop()
    freezeProcess.running = false
  }

  function runAfterDismiss(action) {
    root.pendingAction = action
    // Keep the first freeze alive while the native capture or selection layer
    // starts. Screenshot and recording handoffs release it through their own
    // lifecycle checks below.
    root.dismiss(true)
    captureDelay.restart()
  }

  function runScreenshot() {
    root.runAfterDismiss("screenshot")
  }

  function runScreenrecordMenu() {
    root.runAfterDismiss("screenrecord")
  }

  // Use the same compositor-backed freeze as omarchy-capture-region. The
  // overlay is opened on the next event-loop turn so its layer is mapped above
  // hyprpicker's frozen-screen layer and remains interactive.
  Process {
    id: freezeProcess
    command: ["hyprpicker", "-r", "-z"]
  }

  Timer {
    id: openDelay
    interval: 120
    repeat: false
    onTriggered: {
      root.opened = true
      Qt.callLater(function() { focusCatcher.forceActiveFocus() })
    }
  }

  Timer {
    id: captureDelay
    interval: 140
    repeat: false
    onTriggered: {
      if (root.pendingAction === "screenshot") {
        screenshotProcess.running = true
      } else if (root.pendingAction === "screenrecord") {
        Quickshell.execDetached(["omarchy-menu", "summon", "trigger.capture.screenrecord"])
        handoffPoll.start()
        handoffTimeout.restart()
      }
      root.pendingAction = ""
    }
  }

  // Omasnap uses its own native overlay, so release our freeze when its
  // screenshot process exits. Screen recording still uses slurp as its picker.
  Process {
    id: screenshotProcess
    command: ["omarchy-capture-screenshot"]
    onExited: root.releaseFreeze()
  }

  Timer {
    id: handoffPoll
    interval: 40
    repeat: true
    onTriggered: if (!slurpProbe.running) slurpProbe.running = true
  }

  Timer {
    id: handoffTimeout
    interval: 10000
    repeat: false
    onTriggered: root.releaseFreeze()
  }

  Process {
    id: slurpProbe
    command: ["pgrep", "-x", "slurp"]
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.releaseFreeze()
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "roubilibo-capture-overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
      opacity: 0.45

      MouseArea {
        anchors.fill: parent
        onPressed: root.runScreenshot()
      }
    }

    Rectangle {
      id: toolbar
      width: screenshotButton.width + recordButton.width
      height: Style.space(52)
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: Style.space(52)
      radius: root.radius
      color: root.background
      border.color: root.border
      border.width: 1

      Rectangle {
        id: screenshotButton
        width: Style.space(150)
        height: parent.height
        radius: root.radius
        color: root.selectedMode === "screenshot" ? root.selectedBackground : "transparent"

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.space(18)
          text: "\uf030"
          color: root.selectedMode === "screenshot" ? root.selectedText : root.foreground
          font.family: "omarchy"
          font.pixelSize: Style.font.body
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.space(44)
          text: "Screenshot"
          color: root.selectedMode === "screenshot" ? root.selectedText : root.foreground
          // Keep the label out of the icon font.  Some user font aliases can
          // resolve monospace to the Omarchy glyph font, which turns letters
          // into unrelated symbols.
          font.family: "sans-serif"
          font.pixelSize: Style.font.body
        }

        MouseArea {
          anchors.fill: parent
          onClicked: root.runScreenshot()
        }
      }

      Rectangle {
        id: recordButton
        x: screenshotButton.width
        width: Style.space(170)
        height: parent.height
        radius: root.radius
        color: root.selectedMode === "screenrecord" ? root.selectedBackground : "transparent"

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.space(18)
          text: "\uf03d"
          color: root.selectedMode === "screenrecord" ? root.selectedText : root.foreground
          font.family: "omarchy"
          font.pixelSize: Style.font.body
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.space(44)
          text: "Screen recording"
          color: root.selectedMode === "screenrecord" ? root.selectedText : root.foreground
          font.family: "sans-serif"
          font.pixelSize: Style.font.body
        }

        MouseArea {
          anchors.fill: parent
          onClicked: root.runScreenrecordMenu()
        }
      }
    }

    Item {
      id: focusCatcher
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.dismiss()
          event.accepted = true
        } else if (event.key === Qt.Key_Tab) {
          root.selectedMode = root.selectedMode === "screenshot" ? "screenrecord" : "screenshot"
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (root.selectedMode === "screenshot") root.runScreenshot()
          else root.runScreenrecordMenu()
          event.accepted = true
        }
      }
    }
  }
}
