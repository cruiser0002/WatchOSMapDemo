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
    
    @IBOutlet weak var startButton: UIButton!
    
    @IBOutlet weak var groupnameField: UITextField!
    
    @IBOutlet weak var facebookLogin: FBSDKLoginButton!
    
    var myUser = User.sharedUser()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.groupnameField.enabled = false
        self.groupnameField.delegate = self
        
        self.startButton.enabled = false
        self.facebookLogin.delegate = self
        
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
        
        User.baseRef.authWithOAuthProvider("facebook", token: tokenString,
            withCompletionBlock: { error, authData in
                guard error == nil else {
                    print("Login failed. \(error)")
                    return
                    
                }
                print("Logged in! \(authData.uid)")
                
                dispatch_async(dispatch_get_main_queue()) {
                    self.groupnameField.enabled = true
                }
                
                self.myUser.uid = String(authData.uid)
                
                guard (self.myUser.userRef != nil) else {
                    return
                }
                
                self.myUser.userRef!.observeSingleEventOfType(.Value, withBlock: { snapshot in
                    if snapshot.value is NSNull {
                        return
                    }
                    guard let groupName = snapshot.value as? String else {
                        return
                    }
                    
                    guard groupName != "" else {
                        return
                    }
                    
                    self.myUser.groupname = groupName
                    dispatch_async(dispatch_get_main_queue()) {
                        self.groupnameField.text = groupName
                        if(self.groupnameField.text?.characters.count >= ProgramConstants.minGroupCharacter) {
                            self.startButton.enabled = true
                        }
                    }
                    
                })
        })
    }
    
    func removePreviousGroups(completion: () -> Void) {
        
        guard let userInGroup = self.myUser.userInGroup else {
            completion()
            return
        }
        
        userInGroup.removeValue()
        
        completion()
    }
    
    @IBAction func startPressed(sender: AnyObject) {
        removePreviousGroups { () -> Void in

            let groupname = self.groupnameField.text!
            
            guard let userRef = self.myUser.userRef else {
                return
            }
            
            userRef.setValue(groupname)
            self.myUser.groupname = groupname
            
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
        
        removePreviousGroups { () -> Void in
            return
        }
    }
    
    func loginButtonWillLogin(loginButton: FBSDKLoginButton!) -> Bool {
        print("loginButtonWillLogin")
        return true
    }

    @IBAction func displayStatus(sender: AnyObject) {
        manageLogin()
    }
}