//
//  GeoPosition.swift
//  YandexMapsApp
//
//  Created by Александр Васильевич on 25/05/2021.
//  Copyright © 2021 Александр Васильевич. All rights reserved.
//

import Foundation

struct GeoPosition {
    let name : String
    let geoObjectDescription: String?
    let boundedBy: BoundedBy
    let point: Point
    
    let text: String //полный адрес в виде строки
    let address: Address
    
    init?(geoPositionData: GeoPositionData) {
        let object = geoPositionData.response.geoObjectCollection.featureMember[0].geoObject
        name = object.name
        geoObjectDescription = object.geoObjectDescription
        boundedBy = object.boundedBy
        point = object.point
        text = object.metaDataProperty.geocoderMetaData.text
        address = object.metaDataProperty.geocoderMetaData.address
    }
}
