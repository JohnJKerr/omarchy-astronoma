import QtQuick

QtObject {
  default property list<KeyBinding> bindings

  function handle(event) {
    for (var i = 0; i < bindings.length; ++i) {
      if (bindings[i].handle(event)) return
    }
  }
}
