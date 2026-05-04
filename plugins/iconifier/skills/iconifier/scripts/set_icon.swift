#!/usr/bin/env swift
//
// Apply custom icons to folders using NSWorkspace.setIcon.
//
// Usage:
//     swift set_icon.swift <selection.json>
//
// where selection.json is the file the HTML preview's "Export selection"
// button downloads:
//
//   {
//     "selection": [
//       { "folder_path": "/abs/path", "proposed_icon_path": "/abs/path/to.png",
//         "method": "emoji", "method_detail": "🎬" },
//       ...
//     ]
//   }
//
// Each folder gets its proposed PNG installed via:
//   NSWorkspace.shared.setIcon(image, forFile: folderPath, options: [])
//
// We print one line per folder: "ok <path>" or "err <path>: <reason>".
// Exit 0 if every folder applied, 1 if any failed.

import Foundation
import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: swift set_icon.swift <selection.json>\n".data(using: .utf8)!)
    exit(2)
}

let selectionURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let data = try? Data(contentsOf: selectionURL),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let entries = json["selection"] as? [[String: Any]]
else {
    FileHandle.standardError.write("set_icon: failed to read selection JSON\n".data(using: .utf8)!)
    exit(2)
}

var failures = 0
for entry in entries {
    guard let folder = entry["folder_path"] as? String,
          let iconPath = entry["proposed_icon_path"] as? String
    else {
        FileHandle.standardError.write("set_icon: malformed entry, skipping\n".data(using: .utf8)!)
        failures += 1
        continue
    }
    guard let image = NSImage(contentsOfFile: iconPath) else {
        print("err \(folder): could not load icon at \(iconPath)")
        failures += 1
        continue
    }
    let ok = NSWorkspace.shared.setIcon(image, forFile: folder, options: [])
    if ok {
        // Touch the folder so Finder picks up the change in the current view.
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: folder
        )
        print("ok \(folder)")
    } else {
        print("err \(folder): NSWorkspace.setIcon returned false")
        failures += 1
    }
}

exit(failures == 0 ? 0 : 1)
