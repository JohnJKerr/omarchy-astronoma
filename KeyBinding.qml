import QtQuick

QtObject {
  property int key: 0
  // Required modifiers, rather than an exact match: existing navigation also
  // accepts modified keys.
  property int modifiers: Qt.NoModifier
  property bool enabled: true

  signal triggered(var event)

  function handle(event) {
    if (!enabled || event.key !== key
        || (event.modifiers & modifiers) !== modifiers) return false
    triggered(event)
    event.accepted = true
    return true
  }
}
