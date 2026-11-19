import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  // Every monitor has workspaces 1-10 of its own, which Hyprland numbers in a
  // block of ten per monitor: 1-10, 11-20, and so on (see
  // default/hypr/monitor-workspaces.lua). Each bar shows its own monitor's block,
  // numbered 1-10, and the one that monitor shows, whichever monitor has focus.
  readonly property int slots: 10

  readonly property var monitor: {
    var window = root.QsWindow.window
    var screen = window ? window.screen : null
    return screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor
  }
  readonly property string monitorName: root.monitor ? root.monitor.name : ""

  // Connector -> block, from the file Hyprland keeps them in.
  property var blocks: ({})

  function readBlocks(text) {
    var next = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var fields = lines[i].split("\t")
      if (fields.length >= 3 && fields[1] !== "") next[fields[1]] = parseInt(fields[0], 10)
    }
    root.blocks = next
  }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitor-workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readBlocks(text())
    onLoadFailed: root.readBlocks("")
  }

  function blockOf(id) {
    return Math.floor((id - 1) / root.slots)
  }

  function slotOf(id) {
    return (id - 1) % root.slots + 1
  }

  function activeWorkspaceId() {
    return root.monitor && root.monitor.activeWorkspace ? root.monitor.activeWorkspace.id : -1
  }

  // Until Hyprland has written the file, the workspace a monitor shows is in
  // its own block.
  readonly property int block: {
    var block = root.blocks[root.monitorName]
    if (block !== undefined) return block
    var active = root.activeWorkspaceId()
    return active > 0 ? root.blockOf(active) : 0
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function toplevelAppId(toplevel) {
    if (!toplevel) return ""
    var wayland = toplevel.wayland
    if (wayland && wayland.appId) return String(wayland.appId)
    if (toplevel.appId) return String(toplevel.appId)
    var ipc = toplevel.lastIpcObject
    if (ipc) {
      if (ipc.initialClass) return String(ipc.initialClass)
      if (ipc.class) return String(ipc.class)
      if (ipc.initialTitle) return String(ipc.initialTitle)
    }
    return ""
  }

  function iconForAppId(appId) {
    var id = String(appId || "")
    if (!id) return ""
    var candidates = [id, id.toLowerCase()]
    try {
      if (typeof DesktopEntries !== "undefined" && DesktopEntries.heuristicLookup) {
        var entry = DesktopEntries.heuristicLookup(id)
        if (entry && entry.icon) candidates.unshift(String(entry.icon))
      }
    } catch (e) {}
    for (var i = 0; i < candidates.length; i++) {
      var icon = Quickshell.iconPath(candidates[i], true)
      if (icon) return icon
    }
    return ""
  }

  function workspaceToplevels(workspaceId) {
    var out = []
    var lists = []

    var ws = root.workspaceById(workspaceId)
    if (ws && ws.toplevels && ws.toplevels.values) lists.push(ws.toplevels.values)

    var all = Hyprland.toplevels ? Hyprland.toplevels.values : null
    if (all && all.length) {
      for (var i = 0; i < all.length; i++) {
        var tl = all[i]
        var tws = tl.workspace || (tl.wayland && tl.wayland.workspace)
        if (tws && tws.id === workspaceId) out.push(tl)
      }
      if (out.length > 0) return out
    }

    return lists.length > 0 ? lists[0] : []
  }

  function appIconsForWorkspaceId(workspaceId) {
    var values = root.workspaceToplevels(workspaceId)
    var seen = {}
    for (var i = 0; i < values.length; i++) {
      var id = root.toplevelAppId(values[i])
      if (!id) continue
      var key = id.toLowerCase()
      if (seen[key]) continue
      seen[key] = true
      var icon = root.iconForAppId(id)
      if (icon) return [icon]
    }
    return []
  }

  // The first five of the monitor's own, and any of the rest that exist. After
  // them come workspaces that are only visiting: those of a monitor that is
  // unplugged, which had no room to join this one's.
  function workspaceIds() {
    var base = root.block * root.slots
    var ids = [base + 1, base + 2, base + 3, base + 4, base + 5]
    var guests = []
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id <= 0) continue
      if (root.blockOf(id) === root.block) {
        if (ids.indexOf(id) === -1) ids.push(id)
      } else if (values[i].monitor && values[i].monitor.name === root.monitorName) {
        guests.push(id)
      }
    }

    ids.sort(function(left, right) { return left - right })
    guests.sort(function(left, right) { return left - right })
    return ids.concat(guests)
  }

  function dispatch(expression) {
    if (root.bar) root.bar.run("hyprctl dispatch " + Util.shellQuote(expression))
  }

  function focusWorkspace(id) {
    if (root.blockOf(id) === root.block) {
      root.dispatch("o.workspaces.focus(" + root.slotOf(id) + ", \"" + root.monitorName + "\")")
    } else {
      root.dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
    }
  }

  // A wheel notch moves one entry along the row, and a touchpad adds up its
  // smaller deltas until they make a notch's worth.
  property real wheelAccumulator: 0

  function scrollWorkspaces(delta) {
    var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
    root.wheelAccumulator = wheel.remainder
    if (wheel.steps === 0) return

    // Holds at either end rather than wrapping, so a touchpad swipe that runs
    // long stops on the last workspace.
    var ids = root.workspaceIds()
    var index = ids.indexOf(root.activeWorkspaceId())
    if (index === -1) return
    var target = ids[Util.clamp(index - wheel.steps, 0, ids.length - 1)]
    if (target !== ids[index]) root.focusWorkspace(target)
  }

  // The workspace each monitor shows carries its layout: a square tiles, a
  // circle scrolls, and a triangle floats. Clicking it cycles to the next one,
  // as Super + L does.
  property string activeMode: "dwindle"
  property bool modeStale: false

  function modeGlyph(mode) {
    if (mode === "scrolling") return "󰝥"
    if (mode === "floating") return "󰔶"
    return "󱓻"
  }

  // A layout only changes through the layout commands, which ask for a refresh,
  // or a config reload, so each workspace's mode is read once and cached rather
  // than running the script on every workspace switch.
  property var modeCache: ({})
  property int modeGeneration: 0
  property int modeProcWorkspace: -1
  property int modeProcGeneration: 0

  function showActiveMode() {
    var mode = root.modeCache[root.activeWorkspaceId()]
    if (mode !== undefined) root.activeMode = mode
    else readMode()
  }

  function readMode() {
    if (modeProc.running) {
      root.modeStale = true
      return
    }
    var id = root.activeWorkspaceId()
    if (id === -1) return
    root.modeProcWorkspace = id
    root.modeProcGeneration = root.modeGeneration
    modeProc.command = ["omarchy-hyprland-workspace-layout-current", String(id)]
    modeProc.running = true
  }

  function refresh() {
    root.modeCache = ({})
    root.modeGeneration++
    readMode()
  }

  // The layout commands act on the focused workspace, so a click on another
  // monitor's bar focuses that monitor first.
  function cycleLayout() {
    if (!root.bar) return
    var command = "omarchy-hyprland-workspace-layout-toggle"
    if (root.monitor && !root.monitor.focused) {
      command = "hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ monitor = \"" + root.monitorName + "\" })") + " >/dev/null && " + command
    }
    root.bar.run(command)
  }

  Component.onCompleted: refresh()
  onMonitorChanged: root.showActiveMode()

  Connections {
    target: root.monitor
    function onActiveWorkspaceChanged() { root.showActiveMode() }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "configreloaded") root.refresh()
      // Quickshell credits every workspace switch to the focused monitor, as
      // the event doesn't say which one switched, and misses the workspace a
      // monitor falls back to when its own is moved away. Moving workspaces
      // between monitors switches the others, so ask Hyprland for the truth.
      // A workspace that changes number is only learned by asking too. Every
      // bar shares what Hyprland answers, so one asks after a plain switch.
      var switched = name === "workspacev2" && root.monitor !== null && root.monitor.focused
      if (switched || name === "moveworkspacev2" || name === "changeworkspaceid") {
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
      }
    }
  }

  Process {
    id: modeProc
    stdout: StdioCollector {
      onStreamFinished: {
        var mode = text.trim()
        // A read that started before a refresh may predate the change.
        if (!mode || root.modeProcGeneration !== root.modeGeneration) return
        root.modeCache[root.modeProcWorkspace] = mode
        if (root.modeProcWorkspace === root.activeWorkspaceId()) root.activeMode = mode
      }
    }
    onExited: {
      if (!root.modeStale) return
      root.modeStale = false
      // Deferred: the process still reports running while it signals exit.
      Qt.callLater(root.showActiveMode)
    }
  }

  // Super + L and the default layout change the mode without a focus change,
  // so they ask every bar to read it again.
  ShellIpc {
    target: "omarchy.workspaces"

    function refresh(): void { root.broadcast("refresh") }
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      Item {
        id: slotItem
        required property int modelData
        required property int index

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels && workspace.toplevels.values.length > 0
        readonly property bool shown: root.monitor !== null && root.monitor.activeWorkspace !== null && root.monitor.activeWorkspace.id === modelData
        readonly property int slot: root.slotOf(modelData)
        readonly property bool firstGuest: root.blockOf(modelData) !== root.block && index > 0 && root.blockOf(root.workspaceIds()[index - 1]) === root.block
        readonly property var appIcons: root.appIconsForWorkspaceId(modelData)
        readonly property string slotLabel: slot === root.slots ? "0" : String(slot)
        readonly property color slotColor: shown
          ? Commons.Color.accent
          : (root.bar ? root.bar.barForeground : "#cccccc")

        // A gap sets visiting workspaces apart from the monitor's own.
        Layout.leftMargin: firstGuest && !root.vertical ? Style.space(6) : 0
        Layout.topMargin: firstGuest && root.vertical ? Style.space(6) : 0

        readonly property real hPad: Style.spaceReal(7)
        readonly property real bgWidth: content.implicitWidth + hPad * 2
        readonly property real bgHeight: Math.max(18, root.barSize - Style.spaceReal(6))

        implicitWidth: bgWidth
        implicitHeight: root.barSize
        opacity: occupied || shown ? 1 : 0.45
        scale: mouseArea.pressed ? 0.96 : 1

        Behavior on opacity {
          NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic }
        }
        Behavior on scale {
          NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
        }

        Rectangle {
          id: bg
          anchors.centerIn: parent
          width: slotItem.bgWidth
          height: slotItem.bgHeight
          radius: 3
          color: slotItem.shown
            ? Qt.rgba(slotItem.slotColor.r, slotItem.slotColor.g, slotItem.slotColor.b, 0.14)
            : "transparent"
          border.width: 1
          border.color: slotItem.shown
            ? Qt.rgba(slotItem.slotColor.r, slotItem.slotColor.g, slotItem.slotColor.b, 0.75)
            : Qt.rgba(slotItem.slotColor.r, slotItem.slotColor.g, slotItem.slotColor.b, slotItem.occupied ? 0.35 : 0.2)

          Behavior on border.color {
            ColorAnimation { duration: Style.duration(140) }
          }
          Behavior on color {
            ColorAnimation { duration: Style.duration(140) }
          }
        }

        RowLayout {
          id: content
          anchors.centerIn: parent
          spacing: (appIcon.visible || fallbackDot.visible) ? 3 : 0

          Text {
            id: label
            Layout.alignment: Qt.AlignVCenter
            textFormat: Text.PlainText
            text: slotItem.slotLabel
            color: slotItem.slotColor
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            renderType: Text.NativeRendering
          }

          Image {
            id: appIcon
            Layout.alignment: Qt.AlignVCenter
            visible: slotItem.appIcons.length > 0 && !root.vertical
            Layout.preferredWidth: 11
            Layout.preferredHeight: 11
            source: visible ? slotItem.appIcons[0] : ""
            sourceSize: Qt.size(22, 22)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            mipmap: true
            opacity: slotItem.shown ? 1.0 : 0.85
          }

          Text {
            id: fallbackDot
            Layout.alignment: Qt.AlignVCenter
            visible: !appIcon.visible && slotItem.occupied && !root.vertical
            textFormat: Text.PlainText
            text: "•"
            color: slotItem.slotColor
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: 10
            opacity: 0.8
          }
        }

        MouseArea {
          id: mouseArea
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
          cursorShape: Qt.PointingHandCursor
          onEntered: {
            if (root.bar && slotItem.shown)
              root.bar.showTooltip(slotItem, "Layout: " + root.activeMode + " (click to cycle)")
          }
          onExited: {
            if (root.bar) root.bar.hideTooltip(slotItem)
          }
          onClicked: function(mouse) {
            if (root.bar) root.bar.hideTooltip(slotItem)
            if (slotItem.shown) root.cycleLayout()
            else root.focusWorkspace(slotItem.modelData)
          }
          onWheel: function(wheel) { root.scrollWorkspaces(wheel.angleDelta.y) }
        }
      }
    }
  }
}
