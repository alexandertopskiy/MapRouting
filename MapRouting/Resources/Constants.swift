//TO DO
//3. Маршруты (выбор в качестве точки "моя геопозиция")

//БАГИ: при поиске "Россия, Республика Татарстан, Голубые озёра" выдает совсем другую точку. Проверил вручную в api геокодера - там эта же самая точка. Нужная точка (как в я.картах) = 55.914363, 49.168065. Выдает точку 55.350341, 50.911013

import Foundation
import RealmSwift


let MAPKIT_API_KEY = "КЛЮЧ ДЛЯ ЯНДЕКС MAPKIT"
let GEOCODER_API_KEY = "КЛЮЧ ДЛЯ ЯНДЕКС GEOCODER"
let GOOGLE_API_KEY = "КЛЮЧ ДЛЯ GOOGLE MAPS API"

enum NetworkState : Int {
    case Online = 0
    case Offline = 1
}

enum GeoAllowState : Int {
    case no = 0
    case yes = 1
}

enum MapType : String {
    case Yandex = "Yandex"
    case Google = "Google"
}

enum MapMode : Int {
    case Searching = 0
    case Routing = 1
}

enum SaveOrDeleteMode : Int {
    case Delete = 0
    case Save = 1
}

enum SegueTo : Int {
    case goBack = 0
    case makeTheRoute = 1
}

enum AlertSituation : Int {
    case Default = 0
    case Offline = 1
    case routingFromDB = 2
    case askForMapType = 3
}

extension UIImage {
    func tinted(with color: UIColor, isOpaque: Bool = false) -> UIImage? {
        let format = imageRendererFormat
        format.opaque = isOpaque
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            color.set()
            withRenderingMode(.alwaysTemplate).draw(at: .zero)
        }
    }
}

//Расширения для преобразования объекта Realm в Словарь (а далее для преобразования в JSON)

extension URL {
    var typeIdentifier: String? {
        return (try? resourceValues(forKeys: [.typeIdentifierKey]))?.typeIdentifier
    }
    var localizedName: String? {
        return (try? resourceValues(forKeys: [.localizedNameKey]))?.localizedName
    }
}

extension Object {
    func toDictionary() -> [String:AnyObject] {
        let properties = self.objectSchema.properties.map { $0.name }
        var dicProps = [String:AnyObject]()
        for (key, value) in self.dictionaryWithValues(forKeys: properties) {
            //key = key.uppercased()
            if let value = value as? ListBase {
                dicProps[key] = value.toArray1() as AnyObject
            } else if let value = value as? Object {
                dicProps[key] = value.toDictionary() as AnyObject
            } else {
                dicProps[key] = value as AnyObject
            }
        }
        return dicProps
    }
}

extension ListBase {
    func toArray1() -> [AnyObject] {
        var _toArray = [AnyObject]()
        for i in 0..<self._rlmArray.count {
            let obj = unsafeBitCast(self._rlmArray[i], to: Object.self)
            _toArray.append(obj.toDictionary() as AnyObject)
        }
        return _toArray
    }
}


