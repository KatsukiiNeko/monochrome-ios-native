// Logging.swift: the app's os.Logger instances, all under one subsystem.
import os

/// Matches the bundle identifier so device logs can be filtered by one value.
let logSubsystem = "com.katsukiineko.monochrome"

let playerLog = Logger(subsystem: logSubsystem, category: "player")
let sessionLog = Logger(subsystem: logSubsystem, category: "audio-session")
