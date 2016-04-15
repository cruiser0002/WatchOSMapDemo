//
//  User.swift
//  WatchOSMapDemo
//
//  Created by Jay on 4/15/16.
//  Copyright © 2016 Jay. All rights reserved.
//

import Foundation
import CoreData


class User {
    // MARK: Shared Instance
    var uid : String?
    var groupname : String?
    var longitude : Double?
    var latitude : Double?
    var isLoggedIn : Bool = false
    
    var team = [User]()
    
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