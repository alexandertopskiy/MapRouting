//
//  GeoObjectInfo.swift
//  YandexMapsApp
//
//  Created by Александр Васильевич on 23/05/2021.
//  Copyright © 2021 Александр Васильевич. All rights reserved.
//

import Foundation

struct GeoPositionData : Codable {
    let response: Response
}

struct Response: Codable {
    let geoObjectCollection: GeoObjectCollection
    
    enum CodingKeys: String, CodingKey {
        case geoObjectCollection = "GeoObjectCollection"
    }
}

struct GeoObjectCollection: Codable {
    let featureMember: [FeatureMember]
}

struct FeatureMember: Codable {
    let geoObject: GeoObject
    
    enum CodingKeys: String, CodingKey {
        case geoObject = "GeoObject"
    }
}

struct GeoObject: Codable {
    let metaDataProperty: GeoObjectMetaDataProperty
    let name : String
    let geoObjectDescription: String?
    let boundedBy: BoundedBy
    let point: Point
    
    enum CodingKeys: String, CodingKey {
        case metaDataProperty, name
        case geoObjectDescription = "description"
        case boundedBy
        case point = "Point"
    }
}

// MARK: - BoundedBy
struct BoundedBy: Codable {
    let envelope: Envelope
    
    enum CodingKeys: String, CodingKey {
        case envelope = "Envelope"
    }
}
struct Envelope: Codable {
    let lowerCorner, upperCorner: String
}

struct GeoObjectMetaDataProperty: Codable {
    let geocoderMetaData: GeocoderMetaData
    
    enum CodingKeys: String, CodingKey {
        case geocoderMetaData = "GeocoderMetaData"
    }
}

struct GeocoderMetaData: Codable {
    let text: String //полный адрес в виде строки
    let address: Address
    
    enum CodingKeys: String, CodingKey {
        case text
        case address = "Address"
    }
}

// MARK: - Address
struct Address: Codable {
    let postalCode: String?
    let components: [Component]
    
    enum CodingKeys: String, CodingKey {
        case postalCode = "postal_code"
        case components = "Components"
    }
}
struct Component: Codable {
    let kind, name: String
}
struct Point: Codable {
    let pos: String
}


