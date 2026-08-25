import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.brm-src.plugin-control-center"

  property string uiLanguage: Qt.locale().name.toLowerCase().startsWith("es") ? "es" : "en"
  readonly property bool isSpanish: uiLanguage === "es"
  property var pluginRegistry: null
  function words(es, en) { return root.isSpanish ? es : en }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    var registry = root.bar && root.bar.shell ? root.bar.shell.pluginRegistry : root.pluginRegistry
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("pluginRegistry" in target) target.pluginRegistry = registry
    if ("refresh" in target) Qt.callLater(target.refresh)
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item && panelLoader.item.closeForPopoutSwitch) panelLoader.item.closeForPopoutSwitch()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  visible: true

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰏖"
    slotSize: Style.bar.statusSlot
    opticalSize: 17
    tooltipText: root.words("Plugin Control Center", "Plugin Control Center")
    active: root.opened
    useActiveColor: true
    activeColor: Color.accent

    onPressed: function(b) { root.togglePanel() }
  }
}
