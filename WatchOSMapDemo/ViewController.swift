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


class ViewController: UIViewController, WCSessionDelegate, CLLocationManagerDelegate, MKMapViewDelegate {

//    @IBOutlet weak var label: UILabel!
    @IBOutlet weak var map: MKMapView!
    var myUser = User.sharedUser()
    
    
    var updateTimer = NSTimer()
    
    /// Location manager used to start and stop updating location.
    var locationManager : CLLocationManager!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        locationManager = CLLocationManager()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest;
        locationManager.delegate = self;
        
        
        // user activated automatic authorization info mode
        let status = CLLocationManager.authorizationStatus()
        if status == .NotDetermined || status == .Denied || status == .AuthorizedWhenInUse {
            // present an alert indicating location authorization required
            // and offer to take the user to Settings for the app via
            // UIApplication -openUrl: and UIApplicationOpenSettingsURLString
            locationManager.requestAlwaysAuthorization()
            locationManager.requestWhenInUseAuthorization()
        }
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        
        
        map.delegate = self
        map.showsUserLocation = true
        map.mapType = .Standard
        map.userTrackingMode = .Follow

        updateTimer = NSTimer.scheduledTimerWithTimeInterval(5, target: self, selector: "updateLocation", userInfo: nil, repeats: true)
    }

    func updateLocation () {
        
        
        self.myUser.updateLocation()
        self.myUser.updateBuddies()
        
        let buddies = self.myUser.buddies
        
//        print(buddies)
        var annotations = [MKAnnotation]()
        
        for buddy in buddies {
            guard let long = buddy[DataKey.Longitude.rawValue] as? CLLocationDegrees,
            let lat = buddy[DataKey.Latitude.rawValue] as? CLLocationDegrees else
            {
                continue
            }
            let coordinate = CLLocationCoordinate2DMake(lat, long)
            let annotation = MKPointAnnotation()
            annotation.coordinate = coordinate
            annotations.append(annotation)
        }
        
        map.removeAnnotations(map.annotations)
        map.addAnnotations(annotations)
        
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
    
    func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        let currentLocation = locations.last!
        
        let lat = currentLocation.coordinate.latitude as Double
        let long = currentLocation.coordinate.longitude as Double
        
        self.myUser.location = [DataKey.Latitude.rawValue: lat, DataKey.Longitude.rawValue : long]

    }
    
    /// Log any errors to the console.
    func locationManager(manager: CLLocationManager, didFailWithError error: NSError) {
        print("Error occured: \(error.localizedDescription).")
    }

    
}

