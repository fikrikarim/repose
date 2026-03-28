import AppKit

// Usage: swift pad_icon.swift <input.png> <output.png>
// Adds transparent padding to the right and bottom of an icon for README margin.

let src = NSImage(contentsOfFile: CommandLine.arguments[1])!
let srcSize = src.size
let paddingRight: CGFloat = 100
let paddingBottom: CGFloat = 100
let newSize = NSSize(width: srcSize.width + paddingRight, height: srcSize.height + paddingBottom)

let newImage = NSImage(size: newSize)
newImage.lockFocus()
NSColor.clear.set()
NSRect(origin: .zero, size: newSize).fill()
src.draw(in: NSRect(origin: NSPoint(x: 0, y: paddingBottom), size: srcSize))
newImage.unlockFocus()

let rep = NSBitmapImageRep(data: newImage.tiffRepresentation!)!
let pngData = rep.representation(using: .png, properties: [:])!
try! pngData.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
