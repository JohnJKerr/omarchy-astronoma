import QtQuick
import qs.Commons

// The ASCII rocket, in the spirit of Omarchy's own logo.txt / icon.txt.
//
// Drawn in the monospace family the rest of the shell uses and tinted from
// the active theme, so it reads as part of Omarchy rather than as a brand
// dropped into it.
//
// Two things keep the art from skewing. Every row is padded to the same
// width and the text is left-aligned — centring would centre each row on
// its own width and bend the hull. And the line height is pulled in,
// because a monospace cell is far taller than it is wide, which stretches
// untouched ASCII art vertically.
Text {
  id: root

  property color foreground: Color.foreground
  property real cellSize: Style.font.body

  color: foreground
  font.family: Style.font.family
  font.pixelSize: cellSize
  lineHeight: 0.95
  lineHeightMode: Text.ProportionalHeight
  textFormat: Text.PlainText
  horizontalAlignment: Text.AlignLeft
  verticalAlignment: Text.AlignVCenter

  text: "   /\\   \n"
      + "  /  \\  \n"
      + "  |==|  \n"
      + "  |  |  \n"
      + " /|  |\\ \n"
      + "/_|__|_\\\n"
      + "   ..   "
}
