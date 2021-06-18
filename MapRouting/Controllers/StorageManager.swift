//
//  StorageManager.swift
//  YandexMapsApp
//
//  Created by Александр Васильевич on 31.05.2021.
//  Copyright © 2021 Александр Васильевич. All rights reserved.
//

import RealmSwift

// Get on-disk location of the default Realm
let realm = try! Realm()
//print("Realm is located at:", realm.configuration.fileURL!)

class StorageManager {
    
    // MARK: - Удаление всех объектов из базы данных
    static func clearDB() {
        try! realm.write {
            realm.deleteAll()
        }
    }
    
    // MARK: - Точки
    static func savePoint(_ point: GeoPoint) {
        try! realm.write {
            if (self.getPoint(point) == nil) {
                realm.add(point)
            } else {
                print("такая точка уже есть в БД, не сохраняем ее")
            }
        }
    }
    static func filterPoints(_ point: GeoPoint) -> Results<GeoPoint> {
        let querry = "geoPointLatitude == \(point.geoPointLatitude) AND geoPointLongitude == \(point.geoPointLongitude)"
        // Выбираем все точки в базе данных
        let points = realm.objects(GeoPoint.self)
        // Фильтруем их по названию + точке
        let filtredPoints = points.filter(querry)
        return filtredPoints
    }
    static func getPoint(_ point: GeoPoint) -> GeoPoint? {
        let filtredPoints = filterPoints(point)
        if filtredPoints.isEmpty { return nil }
        else { return filtredPoints.first! }
    }
    static func deletePoint(_ point: GeoPoint) {
        try! realm.write {
            let filtredPoints = filterPoints(point)
            if filtredPoints.isEmpty { print("удалять нечего, такого объекта нет") }
            else {
                print("удаляем \(filtredPoints)")
                realm.delete(filtredPoints)
            }
        }
    }
    
    
    // MARK: - Точки пользовтеля
    static func filterUserPoints(_ point: GeoPointToSend) -> Results<GeoPointToSend> {
        let querry = "location == '\(point.location)'"
        // Выбираем все точки в базе данных
        let points = realm.objects(GeoPointToSend.self)
        // Фильтруем их по названию + точке
        let filtredPoints = points.filter(querry)
        return filtredPoints
    }
    static func getUserPoint(_ point: GeoPointToSend) -> GeoPointToSend? {
        let filtredPoints = filterUserPoints(point)
        if filtredPoints.isEmpty { return nil }
        else { return filtredPoints.first! }
    }
    static func saveUserPoint(_ point: GeoPointToSend) { try! realm.write { realm.add(point) } }
    
    // MARK: - "Места"
    
    static func savePlace(_ place: Place) { try! realm.write { realm.add(place) } }
    static func filterPlaces(_ place: Place) -> Results<Place> {
        let querry = "geoPoint.geoPointLatitude == \(place.geoPoint!.geoPointLatitude) AND geoPoint.geoPointLongitude == \(place.geoPoint!.geoPointLongitude)"
        // Выбираем все места в базе данных
        let places = realm.objects(Place.self)
        // Фильтруем их по названию + точке
        let filtredPlaces = places.filter(querry)
        return filtredPlaces
    }
    static func getPlace(_ place: Place) -> Place? {
        let filtredPlaces = filterPlaces(place)
        if filtredPlaces.isEmpty { return nil }
        else { return filtredPlaces.first! }
    }
    static func deletePlace(_ place: Place) { try! realm.write {
        let filtredPlaces = filterPlaces(place)
        if filtredPlaces.isEmpty { print("удалять нечего, такого объекта нет") }
        else {
            print("удаляем \(filtredPlaces)")
            realm.delete(filtredPlaces)
        }
    } }
    
    // MARK: - "Маршруты"
    
    static func updateRoute(_ route: Route, geometryOfRoute: String?, routeArray: List<GeoPoint>, routeUserArray: List<GeoPointToSend>) {
        // Ищем маршрут
        if let existingRoute = StorageManager.getRoute(route) { // если существует, то обновляем
            try! realm.write {
                if (existingRoute.geometryOfRoute == nil) {
                    existingRoute.geometryOfRoute = geometryOfRoute
                }
                if (existingRoute.routeArray.isEmpty) {
                    let routeArray = routeArray
                    try! realm.write {
                        routeArray.removeAll();
                        for point in routeArray { routeArray.append(point) }
                    }
                }
                if (existingRoute.routeUserArray.isEmpty) {
                    let routeUserArray = existingRoute.routeUserArray
                    try! realm.write {
                        routeUserArray.removeAll();
                        for userPoint in routeUserArray { routeUserArray.append(userPoint) }
                    }
                }
            }
        } else { // если не существует, то создаем
            try! realm.write { realm.add(route) }
        }
    }
    
    static func saveRoute(_ route: Route) {
        try! realm.write { realm.add(route) }
    }

        
    static func filterRoutes(_ route: Route) -> Results<Route> {
        
        let querry = "pointA.geoPointLatitude == \(route.pointA!.geoPointLatitude) AND " +
                     "pointA.geoPointLongitude == \(route.pointA!.geoPointLongitude) AND " +
                     "pointB.geoPointLatitude == \(route.pointB!.geoPointLatitude) AND " +
                     "pointB.geoPointLongitude == \(route.pointB!.geoPointLongitude) AND " +
                     "typeOfMap == '\(route.typeOfMap!)'"
        // Выбираем все маршруты в базе данных
        let routes = realm.objects(Route.self)
        // Фильтруем их по точкам А и Б
        if !(routes.isEmpty) {
            var filtredRoutes = routes.filter(querry)
            if filtredRoutes.isEmpty { //проверяем наоборот (не от А к Б, а от Б к А)
                let querry = "pointA.geoPointLatitude == \(route.pointB!.geoPointLatitude) AND " +
                    "pointA.geoPointLongitude == \(route.pointB!.geoPointLongitude) AND " +
                    "pointB.geoPointLatitude == \(route.pointA!.geoPointLatitude) AND " +
                    "pointB.geoPointLongitude == \(route.pointA!.geoPointLongitude) AND " +
                    "typeOfMap == '\(route.typeOfMap!)'"
                filtredRoutes = routes.filter(querry)
            }
            return filtredRoutes
        } else {
            return routes
        }
    }
    
    static func getRoute(_ route: Route) -> Route? {
        let filtredRoutes = filterRoutes(route)
        if filtredRoutes.isEmpty { return nil }
        else { return filtredRoutes.first! }
    }
    static func deleteRoute(_ route: Route) {

        let filtredRoutes = filterRoutes(route)
        
        print("удаляем \(String(describing: filtredRoutes.first?.userNameForRoute))")
        if filtredRoutes.isEmpty { print("удалять нечего, такого объекта нет") }
        else {
            try! realm.write { realm.delete(filtredRoutes.first!) }
//            let routeArray = filtredRoutes.first?.routeAr
            
        }
    }
}
