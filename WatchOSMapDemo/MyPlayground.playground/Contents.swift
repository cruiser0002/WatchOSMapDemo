//: Playground - noun: a place where people can play

import UIKit
import MapKit

var str = "Hello, playground"


let lat : CLLocationDegrees = 3.3
let long : CLLocationDegrees = 3.3

let mapLocation = CLLocationCoordinate2DMake(lat, long)
print(mapLocation)
let sloc = String(mapLocation)

//let newLoc = sloc as CLLocationCoordinate2D
let a = ["v":3, "q":4]
a["v"]

var list = [3,4]
list.append(5)
list += [6,7,8]
print(list)

