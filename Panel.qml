import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.brm-src.plugin-control-center"
  ipcTarget: "io.github.brm-src.plugin-control-center"
  manageIpc: true

  property string uiLanguage: String(Quickshell.env("PLUGIN_CONTROL_CENTER_LANG") || "").toLowerCase() === "en"
    ? "en"
    : (Qt.locale().name.toLowerCase().startsWith("es") ? "es" : "en")
  readonly property bool isSpanish: uiLanguage === "es"
  function words(es, en) { return root.isSpanish ? es : en }

  // Injected by main.qml. The shell owns this registry instance.
  property var pluginRegistry: null
  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property var registry: root.pluginRegistry

  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string pluginsDir: homeDir + "/.config/omarchy/plugins"

  property var plugins: []
  property string filterText: ""
  property string viewFilter: "all" // all | enabled | disabled | third-party
  property string statusMessage: ""
  property bool busy: false
  property string expandedId: ""      // settings drawer open for this plugin id
  property string infoId: ""          // info drawer open for this plugin id
  property var draftSettings: ({})    // key -> string, edited before saving
  property string pendingRemoveId: ""

  // ponytail: caps prevent a malicious installed plugin from forcing
  // unbounded arrays/strings into the shared shell (Panel.qml runs in the bar).
  readonly property int _maxPlugins: 256
  readonly property int _maxField: 160
  readonly property int _maxDesc: 500
  readonly property int _maxSchema: 64
  function _trunc(v, n) { var s = String(v == null ? "" : v); return s.length > n ? s.slice(0, n) : s }

  readonly property var filteredPlugins: {
    var query = _trunc(filterText, 120).toLowerCase()
    var out = []
    for (var i = 0; i < plugins.length && out.length < _maxPlugins; i++) {
      var p = plugins[i]
      if (query !== "" && String(p.name).toLowerCase().indexOf(query) === -1 && p.id.toLowerCase().indexOf(query) === -1) continue
      if (viewFilter === "enabled" && !p.enabled) continue
      if (viewFilter === "disabled" && p.enabled) continue
      if (viewFilter === "third-party" && p.firstParty) continue
      out.push(p)
    }
    return out
  }

  function refresh() {
    var reg = registry
    if (!reg || !reg.installedPlugins) {
      statusMessage = root.words("Registro de plugins no disponible.", "Plugin registry unavailable.")
      return
    }
    var list = []
    statusMessage = statusMessage === "Registro de plugins no disponible."
      || statusMessage === "Plugin registry unavailable." ? "" : statusMessage
    var installed = reg.installedPlugins
    var seen = 0
    for (var id in installed) {
      if (seen++ >= _maxPlugins) break
      var m = installed[id]
      if (!m || !m.id || m.id === "omarchy.bar") continue
      var kinds = Array.isArray(m.kinds) ? m.kinds.slice(0, 16).map(function(k) { return _trunc(k, 64) }) : []
      list.push({
        id: _trunc(m.id, 128),
        name: _trunc(m.name || m.id, _maxField),
        version: _trunc(m.version || "", 32),
        description: _trunc(m.description || "", _maxDesc),
        author: _trunc(m.author || "", 80),
        firstParty: m.__isFirstParty === true,
        kinds: kinds.join(", ").slice(0, 200),
        enabled: reg.isEnabled(m.id),
        inBar: reg.inBar(m.id),
        sourceDir: _trunc(m.__sourceDir || "", 256)
      })
    }
    list.sort(function(a, b) {
      if (a.firstParty !== b.firstParty) return a.firstParty ? 1 : -1
      return a.name.localeCompare(b.name)
    })
    plugins = list
  }

  function openFromHotkey() {
    open()
    refresh()
  }

  function kindBadge(p) {
    var kinds = p.kinds.split(", ")
    if (kinds.indexOf("bar") !== -1) return root.words("BARRA", "BAR")
    if (p.inBar) return root.words("EN LA BARRA", "ON BAR")
    if (kinds.indexOf("bar-widget") !== -1) return root.words("WIDGET", "WIDGET")
    if (kinds.indexOf("panel") !== -1 || kinds.indexOf("overlay") !== -1 || kinds.indexOf("menu") !== -1)
      return root.words("INTERFAZ", "UI")
    if (kinds.indexOf("service") !== -1) return root.words("SERVICIO", "SERVICE")
    return p.kinds.toUpperCase()
  }

  function toggleEnabled(p) {
    var reg = registry
    if (!reg || busy) return
    busy = true
    statusMessage = p.enabled
      ? root.words("Desactivando " + p.name + "…", "Disabling " + p.name + "…")
      : root.words("Activando " + p.name + "…", "Enabling " + p.name + "…")
    var ok = reg.setEnabled(p.id, !p.enabled, {})
    busy = false
    if (!ok) statusMessage = reg.lastEnableError || root.words("No se pudo cambiar el estado.", "Could not change state.")
    else statusMessage = ""
    refresh()
  }

  // ---- inline widget settings -------------------------------------------

  function schemaOf(p) {
    var meta = registry && registry.installedPlugins[p.id]
      && registry.installedPlugins[p.id].barWidget
    return meta && Array.isArray(meta.schema) ? meta.schema : []
  }

  function defaultsOf(p) {
    var meta = registry && registry.installedPlugins[p.id]
      && registry.installedPlugins[p.id].barWidget
    return meta && meta.defaults ? meta.defaults : {}
  }

  function currentSettings(p) {
    // ponytail: cap copied keys/values before they reach settings objects
    var out = ({})
    var base = defaultsOf(p)
    var bc = 0
    for (var key in base) {
      if (bc++ >= 32) break
      var bv = base[key]
      out[_trunc(key, 64)] = typeof bv === "string" ? _trunc(bv, 256) : bv
    }
    var live = hostWidget && hostWidget.moduleName === p.id ? hostWidget.settings : null
    if (!live && registry && registry.shellConfigProvider) {
      var config = registry.shellConfigProvider()
      var sections = ["left", "center", "right"]
      for (var s = 0; s < sections.length && !live; s++) {
        var entries = config && config.bar && config.bar.layout && config.bar.layout[sections[s]]
        if (!Array.isArray(entries)) continue
        for (var i = 0; i < entries.length; i++) {
          if (entries[i] && String(entries[i].id) === p.id) {
            live = entries[i]
            break
          }
        }
      }
    }
    if (live) {
      var lc = 0
      for (var k2 in live) {
        if (lc++ >= 32) break
        if (k2 in out) continue
        var lv = live[k2]
        if (k2 === "id") out[k2] = _trunc(lv, 128)
        else if (typeof lv === "string") out[k2] = _trunc(lv, 512)
        else out[_trunc(k2, 64)] = lv
      }
    }
    return out
  }

  function _sanitize(v, depth) {
    if (v == null) return null
    if (depth <= 0) return typeof v === "string" ? _trunc(v, 64) : null
    if (typeof v === "string") return _trunc(v, 256)
    if (typeof v === "number" || typeof v === "boolean") return v
    if (Array.isArray(v)) {
      var out = []
      for (var i = 0; i < v.length && out.length < 16; i++) out.push(_sanitize(v[i], depth - 1))
      return out
    }
    if (typeof v === "object") {
      var o = {}; var c = 0
      for (var k in v) { if (c++ >= 16) break; o[_trunc(k, 64)] = _sanitize(v[k], depth - 1) }
      return o
    }
    return _trunc(String(v), 128)
  }

  function _stringifyCapped(v) {
    var sanitized = _sanitize(v, 3)
    var s = JSON.stringify(sanitized)
    return s && s.length > 512 ? s.slice(0, 512) : (s || "null")
  }

  function openSettings(p) {
    if (expandedId === p.id) { expandedId = ""; return }
    draftSettings = ({})
    infoId = ""
    var current = currentSettings(p)
    var fields = schemaFields(p)
    for (var i = 0; i < fields.length; i++)
      draftSettings[fields[i].key] = _stringifyCapped(current[fields[i].key])
    expandedId = p.id
  }

  function toggleInfo(p) {
    infoId = infoId === p.id ? "" : p.id
    if (infoId !== "") expandedId = ""
  }

  function schemaFields(p) {
    var flat = []
    var schema = schemaOf(p)
    if (!Array.isArray(schema)) return flat
    for (var i = 0; i < schema.length && flat.length < _maxSchema; i++) {
      var opt = schema[i]
      if (!opt || typeof opt !== "object") continue
      if (opt.type === "object" && Array.isArray(opt.options)) {
        for (var j = 0; j < opt.options.length && flat.length < _maxSchema; j++) {
          var sub = opt.options[j]
          if (!sub || typeof sub !== "object") continue
          flat.push({ key: _trunc(opt.key, 64) + "." + _trunc(sub.key, 64), label: _trunc(sub.label || sub.key, 80), type: _trunc(sub.type || "string", 16), min: sub.min, max: sub.max, step: sub.step })
        }
      } else {
        flat.push({ key: _trunc(opt.key, 64), label: _trunc(opt.label || opt.key, 80), type: _trunc(opt.type || "string", 16), min: opt.min, max: opt.max, step: opt.step })
      }
    }
    return flat
  }

  function parseDraft(value) {
    try { return JSON.parse(String(value)) } catch (e) { return undefined }
  }

  function saveSettings(p) {
    var reg = registry
    if (!reg || busy) return
    var fields = schemaFields(p)
    var applied = 0
    for (var i = 0; i < fields.length; i++) {
      var field = fields[i]
      if (!(field.key in draftSettings)) continue
      var value = parseDraft(draftSettings[field.key])
      if (value === undefined) continue
      var err = ""
      if (field.key.indexOf(".") !== -1) {
        var parts = field.key.split(".")
        var current = currentSettings(p)
        var nested = current[parts[0]]
        if (!nested || typeof nested !== "object") nested = {}
        nested[parts[1]] = value
        err = String(reg.setBarWidget(p.id, parts[0], nested, {}) || "")
      } else {
        err = String(reg.setBarWidget(p.id, field.key, value, {}) || "")
      }
      if (err === "") applied++
    }
    statusMessage = applied > 0 ? root.words("Ajustes guardados.", "Settings saved.") : root.words("Nada que guardar.", "Nothing to save.")
    expandedId = ""
    Qt.callLater(refresh)
  }

  // ---- uninstall ---------------------------------------------------------

  function requestRemove(p) {
    pendingRemoveId = p.id
    confirmDialog.message = root.words(
      "¿Desinstalar " + p.name + "? Se elimina su carpeta en ~/.config/omarchy/plugins.",
      "Uninstall " + p.name + "? Its folder under ~/.config/omarchy/plugins will be deleted.")
    confirmDialog.opened = true
  }

  function confirmRemove() {
    var p = pendingRemoveId
    pendingRemoveId = ""
    confirmDialog.opened = false
    if (!p) return
    removeProc.pluginId = p
    busy = true
    removeProc.running = true
    statusMessage = root.words("Desinstalando…", "Uninstalling…")
  }

  function kindColor(p) {
    return Color.accent
  }

  Component.onCompleted: {
    // The shell assigns pluginRegistry right after load; give it a tick.
    Qt.callLater(refresh)
  }
  onRegistryChanged: refresh()

  Connections {
    target: root.registry
    function onScanFinished() { root.refresh() }
  }

  Process {
    id: removeProc
    property string pluginId: ""
    command: ["omarchy", "plugin", "remove", pluginId, "--yes"]
    onExited: function(code) {
      root.busy = false
      root.statusMessage = code === 0
        ? root.words("Desinstalado.", "Uninstalled.")
        : root.words("No se pudo desinstalar.", "Could not uninstall.")
      root.refresh()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(Math.min(contentColumn.implicitHeight, Style.space(620)))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
    }

    Column {
      id: contentColumn
      width: parent.width
      spacing: Style.spacing.md

      // Header: small-caps title, subtitle, actions
      Row {
        width: parent.width
        spacing: Style.spacing.sm
        Column {
          width: parent.width - panelActions.width - Style.spacing.sm
          spacing: 1
          Text { text: "PLUGIN CONTROL CENTER"; color: Color.accent; font.family: Style.font.menuFamily; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1.5 }
          Text {
            width: parent.width
            text: root.plugins.length + " " + root.words("plugins instalados", "plugins installed")
            color: Util.alpha(Color.menu.text, 0.45)
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
        Row {
          id: panelActions
          spacing: Style.spacing.xs
          Button { iconText: "↻"; foreground: Color.menu.text; tooltipText: root.words("Actualizar", "Refresh"); onClicked: root.refresh() }
          Button { iconText: "×"; foreground: Color.menu.text; tooltipText: root.words("Cerrar", "Close"); onClicked: root.close() }
        }
      }

      Rectangle { width: parent.width; height: 1; color: Util.alpha(Color.accent, 0.45) }

      // Search + filters
      Row {
        width: parent.width
        spacing: Style.spacing.sm

        TextField {
          id: searchField
          width: parent.width - filterRow.width - Style.spacing.sm
          placeholderText: root.words("Buscar plugins…", "Search plugins…")
          foreground: Color.menu.text
          onTextChanged: root.filterText = _trunc(text, 120)
        }

        Row {
          id: filterRow
          spacing: Style.spacing.xs
          Repeater {
            model: [
              ["all", root.words("TODOS", "ALL")],
              ["enabled", root.words("ACTIVOS", "ON")],
              ["disabled", root.words("INACTIVOS", "OFF")],
              ["third-party", root.words("TERCEROS", "3RD")]
            ]
            delegate: Button {
              required property var modelData
              text: modelData[1]
              fontSize: Style.font.caption
              active: root.viewFilter === modelData[0]
              bordered: true
              foreground: Color.menu.text
              accent: Color.accent
              onClicked: root.viewFilter = modelData[0]
            }
          }
        }
      }

      Text {
        visible: root.statusMessage !== ""
        width: parent.width
        text: root.statusMessage
        color: Color.accent
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap
      }

      // Plugin list
      Flickable {
        id: listScroll
        width: parent.width
        height: Math.min(listColumn.implicitHeight, Style.space(340))
        contentWidth: width
        contentHeight: listColumn.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: listColumn
          width: listScroll.width
          spacing: Style.spacing.xs

          Text {
            visible: root.filteredPlugins.length === 0
            width: parent.width
            text: root.words("Nada coincide con el filtro.", "Nothing matches the filter.")
            color: Util.alpha(Color.menu.text, 0.55)
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }

          Repeater {
            model: root.filteredPlugins

            delegate: Rectangle {
              id: card
              required property var modelData
              readonly property bool expanded: root.expandedId === modelData.id
              readonly property bool canToggle: !root.busy
              readonly property bool canRemove: !modelData.firstParty && !root.busy

              width: listColumn.width
              height: cardBody.implicitHeight + Style.space(18)
              radius: Style.cornerRadius
              color: Util.alpha(Color.menu.text, 0.06)
              border.width: 1
              border.color: modelData.enabled ? Util.alpha(Color.accent, 0.5) : Util.alpha(Color.menu.text, 0.14)

              Column {
                id: cardBody
                anchors.fill: parent
                anchors.margins: Style.space(9)
                spacing: Style.space(7)

                Row {
                  width: parent.width
                  spacing: Style.space(8)

                  Column {
                    width: parent.width - actionsRow.width - Style.space(8)
                    spacing: 1

                    Row {
                      width: parent.width
                      spacing: Style.space(6)

                      Text {
                        text: card.modelData.name
                        color: Color.menu.text
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth + 2, parent.width / 2)
                      }

                      Text {
                        text: root.kindBadge(card.modelData)
                        color: Util.alpha(Color.accent, 0.85)
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        font.letterSpacing: 0.8
                      }

                      Text {
                        visible: card.modelData.version !== ""
                        text: "v" + card.modelData.version
                        color: Util.alpha(Color.menu.text, 0.40)
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Text {
                      width: parent.width
                      text: card.modelData.id + (card.modelData.firstParty ? root.words(" · integrado", " · built-in") : "")
                      color: Util.alpha(Color.menu.text, 0.42)
                      font.family: Style.font.menuFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideMiddle
                    }
                  }

                  Row {
                    id: actionsRow
                    spacing: Style.spacing.xs

                    component PccButton: Button {
                      height: 26
                      fontSize: Style.font.caption
                      fontFamily: Style.font.menuFamily
                      foreground: Color.menu.text
                      accent: Color.accent
                    }

                    PccButton {
                      iconText: "ⓘ"
                      width: 28
                      tooltipText: root.words("Ver qué hace este plugin", "See what this plugin does")
                      active: root.infoId === card.modelData.id
                      onClicked: root.toggleInfo(card.modelData)
                    }
                    PccButton {
                      visible: root.expandedId === card.modelData.id
                      text: root.words("Guardar", "Save")
                      background: Color.accent
                      foreground: Color.background
                      onClicked: root.saveSettings(card.modelData)
                    }
                    PccButton {
                      visible: root.schemaFields(card.modelData).length > 0
                      text: root.expandedId === card.modelData.id ? root.words("Cerrar", "Close") : root.words("Ajustes", "Settings")
                      bordered: true
                      onClicked: root.openSettings(card.modelData)
                    }
                    PccButton {
                      text: card.modelData.enabled ? root.words("Desactivar", "Disable") : root.words("Activar", "Enable")
                      bordered: true
                      enabled: card.canToggle
                      onClicked: root.toggleEnabled(card.modelData)
                    }
                    PccButton {
                      visible: card.canRemove
                      text: root.words("Desinstalar", "Uninstall")
                      bordered: true
                      enabled: card.canRemove
                      tooltipText: root.words("Elimina la carpeta del plugin.", "Deletes the plugin folder.")
                      onClicked: root.requestRemove(card.modelData)
                    }
                  }
                }

                Column {
                  visible: root.infoId === card.modelData.id
                  width: parent.width
                  spacing: Style.space(5)

                  Rectangle { width: parent.width; height: 1; color: Util.alpha(Color.menu.text, 0.12) }

                  Text {
                    width: parent.width
                    text: card.modelData.description !== ""
                      ? card.modelData.description
                      : root.words("Este plugin no declara una descripción.", "This plugin has no declared description.")
                    color: Util.alpha(Color.menu.text, 0.72)
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: Text.Wrap
                  }

                  Text {
                    width: parent.width
                    text: card.modelData.author !== "" ? "" + card.modelData.author : ""
                    visible: text !== ""
                    color: Util.alpha(Color.menu.text, 0.40)
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                // Settings editor (only when expanded and schema exists)
                Column {
                  visible: card.expanded
                  width: parent.width
                  spacing: Style.space(6)

                  Rectangle { width: parent.width; height: 1; color: Util.alpha(Color.menu.text, 0.12) }

                  Repeater {
                    model: card.expanded ? root.schemaFields(card.modelData) : []

                    delegate: Row {
                      required property var modelData
                      width: parent.width
                      spacing: Style.space(8)

                      Text {
                        width: parent.width * 0.45
                        text: modelData.label
                        color: Util.alpha(Color.menu.text, 0.70)
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      TextField {
                        id: editField
                        property var field: modelData
                        width: parent.width - parent.children[0].width - Style.space(8)
                        height: 26
                        verticalPadding: 2
                        horizontalPadding: 6
                        foreground: Color.menu.text
                        font.pixelSize: Style.font.caption
                        text: root.draftSettings[field.key] !== undefined ? root.draftSettings[field.key] : ""
                        onTextEdited: root.draftSettings[field.key] = _trunc(text, 512)
                        placeholderText: field.type === "boolean"
                          ? root.words("true o false", "true or false")
                          : (field.type === "integer" || field.type === "number")
                            ? root.words("número", "number")
                            : root.words("texto", "text")
                      }
                    }
                  }

                  Text {
                    width: parent.width
                    text: root.words("Los valores van en formato JSON: texto entre comillas, true/false sin comillas.",
                                     "Values use JSON format: quoted strings, unquoted true/false.")
                    color: Util.alpha(Color.menu.text, 0.38)
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.Wrap
                  }
                }
              }
            }
          }
        }
      }

      Item { width: 1; height: Style.space(2) }

      Text {
        width: parent.width
        text: "PLUGIN CONTROL CENTER 1.0"
        color: Util.alpha(Color.menu.text, 0.28)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.0
      }
    }

    ConfirmDialog {
      id: confirmDialog
      anchors.fill: parent
      z: 20
      background: Color.menu.background
      foreground: Color.menu.text
      selectedText: Color.accent
      cancelText: root.words("Cancelar", "Cancel")
      confirmText: root.words("Desinstalar", "Uninstall")
      onCanceled: { opened = false; root.pendingRemoveId = "" }
      onConfirmed: root.confirmRemove()
    }
  }
}
