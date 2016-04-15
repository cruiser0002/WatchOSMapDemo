//
//  LoginViewController.swift
//  WatchOSMapDemo
//
//  Created by Jay on 4/14/16.
//  Copyright © 2016 Jay. All rights reserved.
//

import Foundation
import UIKit
import FBSDKCoreKit
import FBSDKLoginKit


class LoginViewController : UIViewController, FBSDKLoginButtonDelegate {
    
    @IBOutlet weak var statusButton: UIButton!
    @IBOutlet weak var startButton: UIButton!
    @IBOutlet weak var usernameField: UITextField!
    @IBOutlet weak var groupnameField: UITextField!
    @IBOutlet weak var facebookLogin: FBSDKLoginButton!
    
    var usersRef = Firebase(url: "https://torrid-heat-3834.firebaseio.com/location/WatchOSMapDemo/users")
    var groupsRef = Firebase(url: "https://torrid-heat-3834.firebaseio.com/location/WatchOSMapDemo/groups")
    var baseRef = Firebase(url: "https://torrid-heat-3834.firebaseio.com")

    
    @IBAction func startPressed(sender: AnyObject) {
        let username = usernameField.text!
        let groupname = groupnameField.text!
        
        let userRef = usersRef.childByAppendingPath(username)
        let group = ["groupname": groupname]
        
        userRef.updateChildValues(group)
        
        let groupRef = groupsRef.childByAppendingPath(groupname)
        groupRef.updateChildValues(["username": username])
        
    }
    

    
    func loginButton(loginButton: FBSDKLoginButton!, didCompleteWithResult result: FBSDKLoginManagerLoginResult!, error: NSError!)
    {
        print("loginButton")
        
    }
    
    func loginButtonDidLogOut(loginButton: FBSDKLoginButton!)
    {
        print("loginButtonDidLogOut")
        let loginManager: FBSDKLoginManager = FBSDKLoginManager()
        loginManager.logOut()
        
    }
    
    func loginButtonWillLogin(loginButton: FBSDKLoginButton!) -> Bool {
        print("loginButtonWillLogin")
        return true
    }

    @IBAction func displayStatus(sender: AnyObject) {
        
        guard let accessToken = FBSDKAccessToken.currentAccessToken() else {
            return
        }
        
        let tokenString = accessToken.tokenString

        
        self.baseRef.authWithOAuthProvider("facebook", token: tokenString,
            withCompletionBlock: { error, authData in
                guard error == nil else {
                    print("Login failed. \(error)")
                    return
                    
                }
                print("Logged in! \(authData)")
                
        })
        
    }
}