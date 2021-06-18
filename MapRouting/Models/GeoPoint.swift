//
//  Point.swift
//  YandexMapsApp
//
//  Created by Александр Васильевич on 07.06.2021.
//  Copyright © 2021 Александр Васильевич. All rights reserved.
//

import Foundation
import RealmSwift

class GeoPoint: Object {
    @objc dynamic var geoPointLatitude : Double = 0.0
    @objc dynamic var geoPointLongitude : Double = 0.0
    @objc dynamic var address = ""
    @objc dynamic var location = ""
    
    
    convenience init(geoPointLatitude: Double, geoPointLongitude: Double, address: String, location: String) {
        self.init()
        self.geoPointLatitude = geoPointLatitude
        self.geoPointLongitude = geoPointLongitude
        self.address = address
        self.location = location
    }
}

class GeoPointToSend: Object {
    @objc dynamic var address = ""
    @objc dynamic var location = ""
    
    convenience init(address: String, location: String) {
        self.init()
        self.address = address
        self.location = location
    }
}
