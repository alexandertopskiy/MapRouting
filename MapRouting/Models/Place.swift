//
//  Place.swift
//  YandexMapsApp
//
//  Created by Александр Васильевич on 31.05.2021.
//  Copyright © 2021 Александр Васильевич. All rights reserved.
//

import Foundation
import RealmSwift

class Place: Object {

    @objc dynamic var userName = ""
    @objc dynamic var geoName = ""
    @objc dynamic var address: String?
    @objc dynamic var type: String?
    @objc dynamic var geoPoint: GeoPoint?
    
    //convenience - назначенный. Он не создает объект, а присваивает значения УЖЕ СОЗДАННОМУ объекту
    convenience init(userName: String, geoName: String,
                     address: String?, type: String?, geoPoint: GeoPoint?) {
        self.init() //для начала инициализация по умолчанию
        self.userName = userName
        self.geoName = geoName
        self.address = address
        self.type = type
        self.geoPoint = geoPoint
    }
}


