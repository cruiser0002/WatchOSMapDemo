//
//  ViewController.swift
//  WatchOSMapDemo
//
//  Created by Jay on 4/13/16.
//  Copyright © 2016 Jay. All rights reserved.
//

import UIKit
import MapKit
import WatchConnectivity
import CoreLocation

class ViewController: UIViewController, WCSessionDelegate, CLLocationManagerDelegate {

//    @IBOutlet weak var label: UILabel!
    @IBOutlet weak var map: MKMapView!
    @IBOutlet weak var textView: UITextView!
    
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
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    /**
     Starts updating location and allows the app to receive background location
     updates.
     
     This method also sets the view into a state that lets the user know that
     the manager has started updating location, as well as starts the batch timer
     for sending location counts to the watch.
     
     Use `commandedFromPhone` to determine whether or not to call `requestWhenInUseAuthorization()`.
     If this method was called due to a command from the watch, the watch should
     be responsible for requesting authorization, and therefore this method
     should not request authorization. This ensures that the authorization prompt
     will come from the device that the user is currently interacting with.
     */
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
        do {
            try session.updateApplicationContext([
                MessageKey.StateUpdate.rawValue: isUpdatingLocation,
                MessageKey.Location.rawValue: self.myLocation
                ])
            
        }
        catch let error as NSError {
            print("Error when updating application context \(error).")
        }
        
//        let annotation = MKPointAnnotation()
//        annotation.coordinate = 
        
        
        
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

