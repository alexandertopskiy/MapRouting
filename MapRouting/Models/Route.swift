import Foundation
import RealmSwift



class Route: Object {

    @objc dynamic var userNameForRoute : String? = nil
    @objc dynamic var addressOfPointA: String?
    @objc dynamic var addressOfPointB: String?
    @objc dynamic var pointA : GeoPoint?
    @objc dynamic var pointB : GeoPoint?
    @objc dynamic var typeOfMap : String? = nil
    @objc dynamic var geometryOfRoute : String? = nil // закодированная геометрия маршрута (для Google Maps)
    
    let routeArray = List<GeoPoint>()
    let routeUserArray = List<GeoPointToSend>()
        
    convenience init(userNameForRoute: String?, addressOfPointA: String?, addressOfPointB: String?, pointA: GeoPoint, pointB: GeoPoint, typeOfMap: String?, geometryOfRoute: String?) {
        self.init()
        self.userNameForRoute = userNameForRoute
        self.addressOfPointA = addressOfPointA
        self.addressOfPointB = addressOfPointB
        self.pointA = pointA
        self.pointB = pointB
        self.typeOfMap = typeOfMap
        self.geometryOfRoute = geometryOfRoute
    }
    
}

class RouteToSend : Object {
    @objc dynamic var NameRoute = ""
    @objc dynamic var Point_A: String? //Point_A
    @objc dynamic var Point_B: String? //Point_B
    
    let ArrData = List<GeoPointToSend>()
    
    convenience init(NameRoute: String, Point_A: String?, Point_B: String?) {
        self.init()
        self.NameRoute = NameRoute
        self.Point_A = Point_A
        self.Point_B = Point_B
    }
}


