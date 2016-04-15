//
//  User.swift
//  WatchOSMapDemo
//
//  Created by Jay on 4/15/16.
//  Copyright © 2016 Jay. All rights reserved.
//

import Foundation
import CoreData
import MapKit

class User {
    // MARK: Shared Instance
    var uid : String?
    var groupname : String?
    var location : [String : AnyObject]?
    var isLoggedIn : Bool = false
    var buddies = [[String : AnyObject]]()
    
    func updateBuddies () {
        guard groupRef != nil else {
            return
        }
        groupRef!.observeSingleEventOfType(.Value, withBlock: { (snapshot) -> Void in
            if snapshot.value is NSNull {
                return
            }
            var tempBuddies = [[String : AnyObject]]()
            for (buddyID, data) in snapshot.value as! [String : AnyObject] {
                guard buddyID != self.uid else {
                    print("found myself")
                    continue
                }
                guard let locationStruct = data as? [String: AnyObject] else{
                    continue
                }
                guard let location = locationStruct[DataKey.Location.rawValue] as? [String : AnyObject] else {
                    continue
                }
                guard let long = location[DataKey.Longitude.rawValue], let lat = location[DataKey.Latitude.rawValue] else {
                    continue
                }
                tempBuddies.append(location)
            }
            
            self.buddies = tempBuddies
            print(self.buddies)
        })
    }
    
    var groupRef : Firebase? {
        guard groupname != nil && groupname != "" else {
            return nil
        }
        return User.groupsRef.childByAppendingPath(groupname)
    }
    
    var userRef : Firebase? {
        guard uid != nil && uid != "" else {
            return nil
        }
        return User.usersRef.childByAppendingPath(uid)
    }
    
    func updateLocation (location: [String : AnyObject]) {
        let locationRef = self.groupRef?.childByAppendingPath(uid).childByAppendingPath("location")
        self.location = location
        locationRef?.updateChildValues(location)
    }
    
    static var usersRef = Firebase(url: "https://torrid-heat-3834.firebaseio.com/location/WatchOSMapDemo/users")
    static var groupsRef = Firebase(url: "https://torrid-heat-3834.firebaseio.com/location/WatchOSMapDemo/groups")
    static var baseRef = Firebase(url: "https://torrid-heat-3834.firebaseio.com")
    
    class func sharedUser() -> User {
        struct Singleton {
            static var sharedUser = User()
        }
        return Singleton.sharedUser
    }
}