//
//  NativeInterfaceController.swift
//  WatchOSMapDemo WatchKit Extension
//
//  Created by Jay on 4/13/16.
//  Copyright © 2016 Jay. All rights reserved.
//

import WatchKit
import Foundation
import CoreLocation

class NativeInterfaceController: WKInterfaceController {

    @IBOutlet var map: WKInterfaceMap!
    @IBOutlet var slider: WKInterfaceSlider!
    
    var timer = NSTimer()
    var timer2 = NSTimer()
    
    var locationManager: CLLocationManager = CLLocationManager()
    var mapLocation: CLLocationCoordinate2D?
    var span : MKCoordinateSpan?
    
    
    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)
        
//        print("native: awake with context")
        
        // Configure interface objects here.
        
//        locationManager.requestWhenInUseAuthorization()
        locationManager.requestAlwaysAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.delegate = self
        locationManager.requestLocation()
        
        
        timer = NSTimer(timeInterval: 1.0, target: self, selector: "updateLocation", userInfo: nil, repeats: true)
        NSRunLoop.currentRunLoop().addTimer(timer, forMode: NSRunLoopCommonModes)
        
                
        self.span = MKCoordinateSpanMake(0.1, 0.1)
//        self.region = MKCoordinateRegionMake(self.mapLocation!, span)
        
    }
    
    func updateLocation() {
        locationManager.requestLocation()
    }

    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
        super.willActivate()
//        print("native: will activate")
        
    }

    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
//        print("native: did deactivate")
        timer.invalidate()
        
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
    
}


extension NativeInterfaceController: CLLocationManagerDelegate {
    func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        let currentLocation = locations[0]
        let lat = currentLocation.coordinate.latitude
        let long = currentLocation.coordinate.longitude
        
        self.mapLocation = CLLocationCoordinate2DMake(lat, long)
        
        let region = MKCoordinateRegionMake(self.mapLocation!, span!)
        
        self.map.setRegion(region)
        
        self.map.removeAllAnnotations()
        self.map.addAnnotation(self.mapLocation!, withPinColor: .Red)
    }
    
    func locationManager(manager: CLLocationManager, didFailWithError error: NSError) {
        
        print(error.description)
    }
    
}