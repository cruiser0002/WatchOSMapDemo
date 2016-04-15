//
//  MainNavigationController.swift
//  WatchOSMapDemo
//
//  Created by Jay on 4/15/16.
//  Copyright © 2016 Jay. All rights reserved.
//

import UIKit
import MapKit
import WatchConnectivity
import CoreLocation


class MainNavigationController : UINavigationController, WCSessionDelegate, CLLocationManagerDelegate {
    
    /// Default WatchConnectivity session for communicating with the watch.
    let session = WCSession.defaultSession()
    
    /// Location manager used to start and stop updating location.
    let manager = CLLocationManager()
    
    var isUpdatingLocation = false
    var receivedLocationCount = 0
    
    var myLocation = [String : AnyObject]()
    
    
    
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
        
        //        startUpdatingLocationAllowingBackground()
        manager.requestWhenInUseAuthorization()
        manager.requestAlwaysAuthorization()
        
        var baseRef = Firebase(url: "https://torrid-heat-3834.firebaseio.com")
        var handle = baseRef.observeEventType(.Value, withBlock: { snapshot in
            print("Snapshot value: \(snapshot.value)")
        })
        
    }
    
    func startUpdatingLocationAllowingBackground() {
        
        guard !isUpdatingLocation else {
            return
        }
        
        self.isUpdatingLocation = true
        
        manager.allowsBackgroundLocationUpdates = true
        
        manager.startUpdatingLocation()
        
        sessionMessageTimer = NSTimer.scheduledTimerWithTimeInterval(5, target: self, selector: "sendLocationCount", userInfo: nil, repeats: true)
        
    }
    
    /**
     Informs the manager to stop updating location, invalidates the timer, and
     updates the view.
     
     If the command comes from the phone, this method sends a state update to
     the watch to inform the watch that location updates have stopped.
     */
    func stopUpdatingLocation() {
        
        guard isUpdatingLocation else {
            return
        }
        
        self.isUpdatingLocation = false
        
        manager.stopUpdatingLocation()
        
        manager.allowsBackgroundLocationUpdates = false
        
        sessionMessageTimer.invalidate()
    }
    
    
    
    /**
     On the receipt of a message, check for expected commands.
     
     On a `startUpdatingLocation` command, inform the manager to start updating
     location, and start a repeating 5 second timer that sends the cumulative
     location count to the watch.
     
     On a `stopUpdatingLocation` command, inform the manager to stop updating
     location, and stop the repeating timer.
     */
    func session(session: WCSession, didReceiveMessage message: [String: AnyObject], replyHandler: [String: AnyObject] -> Void) {
        guard let messageCommandString = message[MessageKey.Command.rawValue] as? String else { return }
        
        guard let messageCommand = MessageCommand(rawValue: messageCommandString) else {
            print("Unknown command \(messageCommandString).")
            return
        }
        
        dispatch_async(dispatch_get_main_queue()) {
            //            self.label.text = messageCommandString
            
            switch messageCommand {
            case .StartUpdatingLocation:
                self.startUpdatingLocationAllowingBackground()
                
                replyHandler([
                    MessageKey.Acknowledge.rawValue: messageCommand.rawValue
                    ])
                
            case .StopUpdatingLocation:
                
                self.stopUpdatingLocation()
                
                replyHandler([
                    MessageKey.Acknowledge.rawValue: messageCommand.rawValue
                    ])
                
            case .SendLocationStatus:
                replyHandler([
                    MessageKey.Acknowledge.rawValue: self.isUpdatingLocation
                    ])
            }
        }
    }
    
    /**
     Send the current cumulative location to the watch and reset the batch
     count to zero.
     */
    func sendLocationCount() {
        
        var buddies = [[String : AnyObject]]()
        
        buddies.append(self.myLocation)
        
        for index in 1...4 {
            var newLoc = self.myLocation as! [String : Double]
            newLoc[DataKey.Latitude.rawValue]! += Double(index) / 2000.0
            
            buddies.append(newLoc)
        }
        
        
        //        fireRef.setValue(buddies)
        
        do {
            try session.updateApplicationContext([
                MessageKey.StateUpdate.rawValue: isUpdatingLocation,
                MessageKey.Location.rawValue: buddies
                ])
            
        }
        catch let error as NSError {
            print("Error when updating application context \(error).")
        }
    }
    
    /**
     Increases that location count by the number of locations received by the
     manager. Updates the batch count with the added locations.
     */
    func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        self.receivedLocationCount += locations.count
        
        let currentLocation = locations.last!
        
        let lat = currentLocation.coordinate.latitude as Double
        let long = currentLocation.coordinate.longitude as Double
        
        self.myLocation = [DataKey.Latitude.rawValue: lat, DataKey.Longitude.rawValue : long]
        
    }
    
    /// Log any errors to the console.
    func locationManager(manager: CLLocationManager, didFailWithError error: NSError) {
        print("Error occured: \(error.localizedDescription).")
    }
    


}