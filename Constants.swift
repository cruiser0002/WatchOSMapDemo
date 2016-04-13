//
//  Constants.swift
//  WatchOSMapDemo
//
//  Created by Jay on 4/13/16.
//  Copyright © 2016 Jay. All rights reserved.
//

import Foundation


/// Keys used by the dictionaries when communicating between the watch and the phone.
enum MessageKey: String {
    case Command        = "command"
    case StateUpdate    = "stateUpdate"
    case Acknowledge    = "ack"
    case LocationCount  = "locationCount"
}

/// Used by the dicationaries when communicating between the watch and the phone.
enum MessageCommand: String {
    case SendLocationStatus     = "sendLocationUpdateStatus"
    case StartUpdatingLocation  = "startUpdatingLocation"
    case StopUpdatingLocation   = "stopUpdatingLocation"
}
