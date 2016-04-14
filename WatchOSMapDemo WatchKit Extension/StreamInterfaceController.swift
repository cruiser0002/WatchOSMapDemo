//
//  StreamInterfaceController.swift
//  WatchOSMapDemo
//
//  Created by Jay on 4/13/16.
//  Copyright © 2016 Jay. All rights reserved.
//

import WatchKit
import Foundation
import CoreLocation
import WatchConnectivity

class StreamInterfaceController: WKInterfaceController, WCSessionDelegate, CLLocationManagerDelegate {
    

    @IBOutlet var map: WKInterfaceMap!
    @IBOutlet var slider: WKInterfaceSlider!

    let session = WCSession.defaultSession()
    var manager: CLLocationManager?
    var mapLocation: CLLocationCoordinate2D?
    var span : MKCoordinateSpan?
    
    
    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)
        
        session.delegate = self
        session.activateSession()
        self.span = MKCoordinateSpanMake(0.1, 0.1)
        
    }
    
    override func willActivate() {
//        sendLocationUpdateStatusCommand()
        
        super.willActivate()
        
        startPressed()
    }
    
    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible

        stopPressed()
        
        super.didDeactivate()
        //        print("native: did deactivate")
        
        
        
    }
    func startPressed() {
        guard session.reachable else {
            print("watchos error: ios device unreachable")
            return
        }
        let authorizationStatus = CLLocationManager.authorizationStatus()
        
        
        switch authorizationStatus {
        case .NotDetermined:
            manager = CLLocationManager()
            manager!.delegate = self
            manager!.requestWhenInUseAuthorization()
            
        case .AuthorizedWhenInUse, .AuthorizedAlways:
            sendStartUpdatingLocationCommand()
            
        default:
            break

        }
        
    }
    
    func stopPressed() {
        guard session.reachable else {
            print("watchos error: ios device unreachable")
            return
        }
        sendStopUpdatingLocationCommand()
    }
    
    
    /// MARK - Sending Commands to Phone
    
    /**
    Sends the message to request a status update from the phone determining
    if the phone is updating location.
    */
    func sendLocationUpdateStatusCommand() {
        let message = [
            MessageKey.Command.rawValue: MessageCommand.SendLocationStatus.rawValue
        ]
        
        session.sendMessage(message, replyHandler: { replyDict in
            guard let ack = replyDict[MessageKey.Acknowledge.rawValue] as? Bool else { return }
            
            print("ios status is \(ack)")
            
            }, errorHandler: { error in
                print("watchos error: unable to get ios status")
        })
    }
    
    /// Sends the message to start updating location, and handles the reply.
    func sendStartUpdatingLocationCommand() {
        
        let message = [
            MessageKey.Command.rawValue: MessageCommand.StartUpdatingLocation.rawValue
        ]
        
        session.sendMessage(message, replyHandler: { replyDict in
            guard let ack = replyDict[MessageKey.Acknowledge.rawValue] as? String
                where ack == MessageCommand.StartUpdatingLocation.rawValue else { return }
            
            print("ios status is start update \(ack)")
            
            }, errorHandler: { error in
                print("watchos error: start update")
        })
    }
    
    /// Sends the message to stop updating location, and handles the reply.
    func sendStopUpdatingLocationCommand() {
        
        let message = [
            MessageKey.Command.rawValue: MessageCommand.StopUpdatingLocation.rawValue
        ]
        
        session.sendMessage(message, replyHandler: { replyDict in
            guard let ack = replyDict[MessageKey.Acknowledge.rawValue] as? String
                where ack == MessageCommand.StopUpdatingLocation.rawValue else { return }
            
            print("ios status is start update \(ack)")
            
            }, errorHandler: { error in
                print("watchos error: stop update")
        })
    }
    
    /// MARK - WCSessionDelegate Methods
    
    /**
    On receipt of a locationCount message, set the text to the value of the
    locationCount key. This is the only key expected to be sent.
    
    On receipt of a startUpdate message, update the controller's state to
    reflect the location updating state.
    */
    func session(session: WCSession, didReceiveApplicationContext applicationContext: [String: AnyObject]) {
        dispatch_async(dispatch_get_main_queue()) {
//            let test = ["location": "-122.26651906", "latitude": "37.4439116"]
            
            guard let location = applicationContext[MessageKey.Location.rawValue] as? [String: AnyObject] else {
                print(applicationContext)
                return
            }
//            print(location[MessageKey.Longitude.rawValue])
            
            guard let lat = location[MessageKey.Latitude.rawValue] as? CLLocationDegrees,
            let long = location[MessageKey.Longitude.rawValue] as? CLLocationDegrees else
            {
                return
            }
            
            self.mapLocation = CLLocationCoordinate2DMake(lat, long)
            
            let region = MKCoordinateRegionMake(self.mapLocation!, self.span!)
            
            self.map.setRegion(region)
            self.map.removeAllAnnotations()
            self.map.addAnnotation(self.mapLocation!, withPinColor: .Red)
        }
    }
    
    
    @IBAction func changeMapRegion(value: Float) {
        
        let degrees:CLLocationDegrees = CLLocationDegrees(value / 200)
        
        self.span = MKCoordinateSpanMake(degrees, degrees)
        
        if (mapLocation == nil || span == nil) {
            return
        }
        let region = MKCoordinateRegionMake(mapLocation!, span!)
        
        map.setRegion(region)
        
    }
    
    
    /// MARK - CLLocationManagerDelegate Methods
    
    /**
    Resets the location manager to nil since it is no longer needed after the
    authorization status is updated. Also sends the command to start updating
    location if the authorization status has changed to .AuthorizedWhenInUse.
    */
    func locationManager(manager: CLLocationManager, didChangeAuthorizationStatus status: CLAuthorizationStatus) {
        /*
        Only set the manager to nil if the status has been determined. This
        prevents us from releasing the manager when the "didChangeAuthorizationStatus"
        callback is received on manager creation while the status is still not
        determined.
        */
        if status != .NotDetermined {
            self.manager = nil
        }
        
        if status == .AuthorizedWhenInUse {
            sendStartUpdatingLocationCommand()
        }
        
    }
}
