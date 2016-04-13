//
//  ViewController.swift
//  WatchOSMapDemo
//
//  Created by Jay on 4/13/16.
//  Copyright © 2016 Jay. All rights reserved.
//

import UIKit
import WatchConnectivity
import CoreLocation

class ViewController: UIViewController, WCSessionDelegate, CLLocationManagerDelegate {

    
    /// Default WatchConnectivity session for communicating with the watch.
    let session = WCSession.defaultSession()
    
    /// Location manager used to start and stop updating location.
    let manager = CLLocationManager()
    
    /**
     Timer to send the cumulative count to the watch.
     To avoid polluting IDS traffic, its better to send batch updates to the watch
     instead of sending the updates as they arrive.
     */
    var sessionMessageTimer = NSTimer()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        session.delegate = self
        session.activateSession()
        
        manager.delegate = self
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func session(session: WCSession, didReceiveMessage message: [String : AnyObject], replyHandler: ([String : AnyObject]) -> Void) {
        guard let messageCommandString = message[MessageKey.Command.rawValue] as? String else { return }
        
        guard let messageCommand = MessageCommand(rawValue: messageCommandString) else {
            print("Unknown command \(messageCommandString).")
            return
        }
    }


}

