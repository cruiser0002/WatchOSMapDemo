//
//  LoginViewController.swift
//  WatchOSMapDemo
//
//  Created by Jay on 4/14/16.
//  Copyright © 2016 Jay. All rights reserved.
//

import Foundation
import UIKit
import MapKit
import WatchConnectivity
import CoreLocation
import FBSDKCoreKit
import FBSDKLoginKit


class LoginViewController : UIViewController, FBSDKLoginButtonDelegate, UITextFieldDelegate{
    
    @IBOutlet weak var statusButton: UIButton!
    @IBOutlet weak var startButton: UIButton!
    @IBOutlet weak var usernameField: UITextField!
    @IBOutlet weak var groupnameField: UITextField!
    @IBOutlet weak var facebookLogin: FBSDKLoginButton!
    
    var usersRef = Firebase(url: "https://torrid-heat-3834.firebaseio.com/location/WatchOSMapDemo/users")
    var groupsRef = Firebase(url: "https://torrid-heat-3834.firebaseio.com/location/WatchOSMapDemo/groups")
    var baseRef = Firebase(url: "https://torrid-heat-3834.firebaseio.com")

    var uid : String = ""
    
    var myUser = User.sharedUser()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.groupnameField.enabled = false
        self.groupnameField.delegate = self
        self.startButton.enabled = false
        
        manageLogin()
        
        if(self.groupnameField.text?.characters.count >= ProgramConstants.minGroupCharacter) {
            self.startButton.enabled = true
        }
    }
    
    
    func textField(textField: UITextField, shouldChangeCharactersInRange range: NSRange, replacementString string: String) -> Bool {
        
        let text = "\(self.groupnameField.text!)\(string)"
        print("\(text):\(string)")
        
        if(text.characters.count >= ProgramConstants.minGroupCharacter) {
            self.startButton.enabled = true
        }
        else {
            self.startButton.enabled = false
        }
        
        return true
    }
    
    func manageLogin() {
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
                print("Logged in! \(authData.uid)")
                
                dispatch_async(dispatch_get_main_queue()) {
                    self.groupnameField.enabled = true
                }
                
                
                self.uid = String(authData.uid)
                
                let userGroupRef = self.usersRef.childByAppendingPath(self.uid)
                
                userGroupRef.observeSingleEventOfType(.Value, withBlock: { snapshot in
                    if snapshot.value is NSNull {
                        return
                    }
                    guard let groupName = snapshot.value["groupname"] as? String else {
                        return
                    }
                    
                    guard groupName != "" else {
                        return
                    }
                    self.groupnameField.text = groupName
                })
        })
    }
    
    func removePreviousGroups(completion: () -> Void) {
        
        guard self.uid != "" else{
            return
        }
        
        let userGroupRef = self.usersRef.childByAppendingPath(self.uid)
        
        userGroupRef.observeSingleEventOfType(.Value, withBlock: { snapshot in
            if snapshot.value is NSNull {
                completion()
                return
            }
            guard let groupName = snapshot.value["groupname"] as? String else {
                completion()
                return
            }
            
            print(groupName)
            guard groupName != "" else {
                completion()
                return
            }
            
            let groupUserRef = self.groupsRef.childByAppendingPath(groupName)
            
            print(groupUserRef.description)
            groupUserRef.removeValue()
            
            userGroupRef.removeValue()
            
            completion()
        })
        
        
        
    }
    
    @IBAction func startPressed(sender: AnyObject) {
        removePreviousGroups { () -> Void in
            let username = self.uid
            let groupname = self.groupnameField.text!
            
            let userRef = self.usersRef.childByAppendingPath(username)
            let group = ["groupname": groupname]
            
            userRef.updateChildValues(group)
            
            let groupRef = self.groupsRef.childByAppendingPath(groupname)
            groupRef.updateChildValues(["username": username])
        }
        
        
        //TODO: should turn start button into stop button
    }
    

    
    func loginButton(loginButton: FBSDKLoginButton!, didCompleteWithResult result: FBSDKLoginManagerLoginResult!, error: NSError!)
    {
        print("loginButton")
        manageLogin()
    }
    
    func loginButtonDidLogOut(loginButton: FBSDKLoginButton!)
    {
        print("loginButtonDidLogOut")
        let loginManager: FBSDKLoginManager = FBSDKLoginManager()
        loginManager.logOut()
        self.groupnameField.enabled = false
        self.startButton.enabled = false
    }
    
    func loginButtonWillLogin(loginButton: FBSDKLoginButton!) -> Bool {
        print("loginButtonWillLogin")
        return true
    }

    @IBAction func displayStatus(sender: AnyObject) {
        manageLogin()
    }
}