//
//  Constants.swift
//  WatchOSMapDemo
//
//  Created by Jay on 4/13/16.
//  Copyright © 2016 Jay. All rights reserved.
//

import Foundation

class ProgramConstants {
    static let minGroupCharacter = 5
}

/// Keys used by the dictionaries when communicating between the watch and the phone.
enum DataKey : String {
    case Longitude      = "longitude"
    case Latitude       = "latitude"
    case GroupName      = "groupname"
    case UserName       = "username"
}

enum MessageKey: String {
    case Command        = "command"
    case StateUpdate    = "stateUpdate"
    case Acknowledge    = "ack"
    case Location       = "location"
}

/// Used by the dicationaries when communicating between the watch and the phone.
enum MessageCommand: String {
    case SendLocationStatus     = "sendLocationUpdateStatus"
    case StartUpdatingLocation  = "startUpdatingLocation"
    case StopUpdatingLocation   = "stopUpdatingLocation"
}
