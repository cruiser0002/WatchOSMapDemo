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
    
    func myselfAndBuddies (nearest : Int?) -> [[String : AnyObject]] {
        var list = [[String : AnyObject]]()
        guard self.location != nil else {
            return list
        }
        list.append(self.location!)
        guard nearest != nil && nearest > 0 && nearest >= buddies.count else {
            return list+buddies
        }
//        let strings = numbers.map {
//            (number) -> String in
//            var number = number
//            var output = ""
//            while number > 0 {
//                output = digitNames[number % 10]! + output
//                number /= 10
//            }
//            return output
//        }
       
        return list+buddies[0...nearest!-1]
        
    }
    
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
    

    var userInGroup : Firebase? {
        guard groupname != nil && groupname != "" else {
            return nil
        }
        guard uid != nil && uid != "" else {
            return nil
        }
        guard groupRef != nil else {
            return nil
        }
        return groupRef!.childByAppendingPath(uid)
    }
    
    var userRef : Firebase? {
        guard uid != nil && uid != "" else {
            return nil
        }
        return User.usersRef.childByAppendingPath(uid)
    }
    
    func updateLocation () {
        let locationRef = self.groupRef?.childByAppendingPath(uid).childByAppendingPath("location")
        
        locationRef?.updateChildValues(self.location)
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