import UIKit
import YandexMapsMobile
import CoreLocation
import RealmSwift
import SwiftyJSON

class MainViewController: UIViewController, YMKMapCameraListener, YMKUserLocationObjectListener, YMKLayersGeoObjectTapListener, YMKMapInputListener, YMKMapObjectTapListener {

    @IBOutlet weak var mapView: YMKMapView!
    @IBOutlet weak var myGeoButton: UIButton!
    @IBOutlet weak var routeButton: UIBarButtonItem!
    
    var alertSituation = AlertSituation.Default //0 - ничего не показываем, 1 - нет соединения с интернетом, 2 - строим по БД
    
    var halfModalTransitioningDelegate: HalfModalTransitioningDelegate?
    
    // контроллер для взаимодействия с файлом (скопировать, отправить и прочее)
    let documentInteractionController = UIDocumentInteractionController()
    
    // MARK: - Общие свойства
    let scale = UIScreen.main.scale
    var currentZoom : Float = 16.0
    let mapKit = YMKMapKit.sharedInstance()
    var wasCameraMovedToPoint : Bool = false //костыль для перемещения камеры на найденную точку (не знаю, как отключить onCameraPositionChanged)
    var isCameraListening : Bool = true //костыль для отключения YMKMapCameraListener
    var mapMode = MapMode.Searching // режим карты (по умолчанию - поиск)
    
    // MARK: - Свойства для поиска
    var namePlace = "Россия"
    var addressPlace: String? = nil
    var addressForSegue: String? = nil //отобожаемый адрес, если адрес поиска addressPlace содержит название
    var typePlace: String? = nil
    var userPoint : YMKPoint? = nil
    var isUserPointSearching : Bool = false
    var isMultipleSearching : Bool = false // если ищем множество точек (например, все магазины "Пятерочка")
    var isSearchingFromDB : Bool = false //если ищем из Базы Данных
    var searchRequest: String? = nil
    var searchPoint : YMKPoint? = YMKPoint(latitude: 55.796127, longitude: 49.106405) //По умолчанию Казань
    var searchManager: YMKSearchManager?
    var searchSession: YMKSearchSession?
    var userLocationLayer : YMKUserLocationLayer?;

    
    
    // MARK: - Свойства для построения маршрута
    var pointA = YMKPoint(); var pointAName = ""; var pointAAddress = ""
    var pointB = YMKPoint(); var pointBName = ""; var pointBAddress = ""
    var arrayOfPoints = List<GeoPoint>()
    var arrayOfUserPoints = List<GeoPointToSend>()
    
    var userNameForRoute : String? = ""
    var drivingSession: YMKDrivingSession?
    var drivingSessionForPedestrian : YMKMasstransitSession?
    var typeRoute = "Pedestrian" //тип маршрутизации (по умолчанию - пешеход)
    var saveOrDeleteMode = SaveOrDeleteMode.Save
    var polyline : YMKPolylineMapObject? //линия маршрута (массив точек)
    
    // MARK: - Методы
    override func viewDidLoad() {
        super.viewDidLoad()
        mapView.mapWindow.map.addTapListener(with: self)
        mapView.mapWindow.map.addInputListener(with: self)
        mapView.mapWindow.map.addCameraListener(with: self)
        userLocationLayer = mapKit.createUserLocationLayer(with: mapView.mapWindow)
        
        var target = YMKPoint()
        
        routeButton.title = "Построить маршрут"
        
        //если есть интернет, то создаем поискового менеджера
        if(Reachability.isConnectedToNetwork()) {
            searchManager = YMKSearch.sharedInstance().createSearchManager(with: .combined)
        }
        
        //если есть интернет и ищем не из БД
        if (Reachability.isConnectedToNetwork() && !isSearchingFromDB){
            if isUserPointSearching {
                searchRequest = String(userPoint!.latitude) + "," + String(userPoint!.longitude)
                searchPoint = userPoint!
                myGeoButton.sendActions(for: .touchUpInside)
            } else {
                if addressPlace == nil { searchRequest = namePlace }
                else { searchRequest = addressPlace! }
            }
            print("\nначальный запрос: \(searchRequest ?? "nil")")
            print("поиск места: \(namePlace)\nадрес места: \(addressPlace ?? "nil")\n")
            
            if (isMultipleSearching || isUserPointSearching) {
                if isMultipleSearching { currentZoom = 12 }
                target = userPoint!
            } else {
                target = searchPoint!
                addressPlace = addressForSegue
                self.performSegue(withIdentifier: "geoObjectInfo", sender: self)
            }
        }
        else {
            target = searchPoint!
            let mapObjects = mapView.mapWindow.map.mapObjects
            mapObjects.clear()
            //добавляем маркер на объект
            let placemark = mapObjects.addPlacemark(with: target)
            placemark.setIconWith(UIImage(named: "SearchResult")!)
            wasCameraMovedToPoint = true
            self.performSegue(withIdentifier: "geoObjectInfo", sender: self)
        }

        //перемещаем карту к цели
        mapView.mapWindow.map.move(with: YMKCameraPosition(
            target: target,
            zoom: (currentZoom < 16.0 ? 16.0 : currentZoom),
            azimuth: 0,
            tilt: 0)
        )
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if (alertSituation == .routingFromDB) {
            let alertController = UIAlertController(title: "Такой маршрут уже есть в Базе данных \n Строим по нему", message: nil, preferredStyle: .alert)
            let cancelAction = UIAlertAction(title: "Ок", style: .default, handler: { alert -> Void in
                self.showJSON()
            })
            alertController.addAction(cancelAction)
            self.present(alertController, animated: true, completion: nil)
        }
        if (alertSituation == .Offline) {
            let alertController = UIAlertController(title: "Нет соединения с Интернетом", message: "Построить маршрут невозможно", preferredStyle: .alert)
            let cancelAction = UIAlertAction(title: "Ок", style: .default, handler: { (action : UIAlertAction!) -> Void in })
            alertController.addAction(cancelAction)
            self.present(alertController, animated: true, completion: nil)
        }
        
        
    }
    
    @IBAction func cancelAction(_ sender: UIBarButtonItem) {
        print("test 2")
        searchManager = nil
        searchRequest = nil
        searchSession = nil
//        networkManager = nil
        userLocationLayer = nil
        mapView = nil
        dismiss(animated: true)
        print("test 3")
    }
    
    func makeFirstSearchRequest(searchRequest: String?) {
        let responseHandler = {(searchResponse: YMKSearchResponse?, error: Error?) -> Void in
            if let response = searchResponse { self.onSearchResponse(response) }
            else { self.onSearchError(error!) }
        }
        searchSession = searchManager!.submit(
            withText: searchRequest!, //что ищем
            geometry: YMKVisibleRegionUtils.toPolygon(with: mapView.mapWindow.map.visibleRegion),
            searchOptions: YMKSearchOptions(),
            responseHandler: responseHandler)
    }
    // MARK: - При измеенении позиции камеры обновить найденные точки на карте на видимой части карты
    func onCameraPositionChanged(with map: YMKMap, cameraPosition: YMKCameraPosition,
                                 cameraUpdateReason: YMKCameraUpdateReason, finished: Bool) {
        currentZoom = cameraPosition.zoom //меняем зум на текущий
        if (cameraUpdateReason != .application) { //обновление камеры пользователем, прекращаем следить за геопозицией
            userLocationLayer?.resetAnchor()
        }
        if (isCameraListening && finished) {
            //если есть интернет, то обновляем запрос
            if (Reachability.isConnectedToNetwork()){
                let responseHandler = {(searchResponse: YMKSearchResponse?, error: Error?) -> Void in
                    if let response = searchResponse { self.onSearchResponse(response) }
                    else { self.onSearchError(error!) }
                }
                if (searchRequest != nil) {
                    searchSession = searchManager?.submit(
                        withText: searchRequest!, //что ищем
                        geometry: YMKVisibleRegionUtils.toPolygon(with: map.visibleRegion),
                        searchOptions: YMKSearchOptions(),
                        responseHandler: responseHandler)
                }
            }
        }
    }
    // MARK: - Получаем название найденного места
    func getName(point : YMKPoint, zoom : NSNumber, nameOfGeoObject : String?) {
        var query : String = ""
        // MARK: - bug: если выбрать велопарковку, то делает неверный запрос
        if (nameOfGeoObject != nil && nameOfGeoObject != "" && nameOfGeoObject != "unknown") { query = nameOfGeoObject! }
        else { query = "\(String(point.latitude)),\(String(point.longitude))" }
        print("ПОИСК ПОЛНОГО НАЗВАНИЯ И АДРЕСА ДЛЯ ЗАПРОСА : \(query)")
        let responseHandler = {(searchResponse: YMKSearchResponse?, error: Error?) -> Void in
            if let response = searchResponse { self.onSearchResponseName(response) }
            else { self.onSearchError(error!) }
        }
        searchSession = searchManager?.submit(
            withText: query,
            geometry: YMKGeometry(point: point),
            searchOptions: YMKSearchOptions(),
            responseHandler: responseHandler
        )
    }
    func onSearchResponseName(_ response: YMKSearchResponse) {
        var arePointsEqual : Bool = false
        for searchResult in response.collection.children {
            if let point = searchResult.obj?.geometry.first?.point {
                print("\nсравниваем координаты точек")
                print("исходная точка: \(searchPoint!.latitude),\(searchPoint!.longitude)")
                print("точка из массива точка: \(point.latitude),\(point.longitude)")
                if (NSString(format: "%.4f", searchPoint!.latitude) == NSString(format: "%.4f", point.latitude) ) {
                    if (NSString(format: "%.4f", searchPoint!.latitude) == NSString(format: "%.4f", point.latitude) ) {
                        arePointsEqual = true
                        print("объект найден")
                    }
                }
                if (arePointsEqual) {
                    if let name = searchResult.obj?.name {
                        namePlace = name
                        print("имя геообъекта: \(name)")
                    }
                    print("адрес: \(searchResult.obj?.descriptionText ?? "nil")")
                    addressPlace = searchResult.obj?.descriptionText
                    if let objMetadata = searchResult.obj?.metadataContainer.getItemOf(YMKSearchBusinessObjectMetadata.self) as? YMKSearchBusinessObjectMetadata {
                        let categorie = objMetadata.categories[0].name
                        print("тип: \(categorie)")
                        typePlace = categorie
                    } else {
                        typePlace = nil
                        print("тип: nil")
                    }
                    break;
                    
                }
            }
        }
        if (!arePointsEqual) {
            print("совпадений нет -> берем первый географический адрес (самый точный)")
            let searchResult = response.collection.children[0]
            if let name = searchResult.obj?.name {
                namePlace = name
                print("имя геообъекта: \(name)")
            }
            if let address = searchResult.obj!.descriptionText {
                print("адрес: \(address)")
                addressPlace = "\(namePlace), \(address)"
            }
            
            if let objMetadata = searchResult.obj?.metadataContainer.getItemOf(YMKSearchBusinessObjectMetadata.self) as? YMKSearchBusinessObjectMetadata {
                let categorie = objMetadata.categories[0].name
                print("тип: \(categorie)")
                typePlace = categorie
            } else {
                typePlace = nil
                print("тип: nil")
            }
        }
        if (mapMode == .Searching) {
            self.performSegue(withIdentifier: "geoObjectInfo", sender: self)
        } else if (mapMode == .Routing) {
            let message : String? = namePlace + " \n" + (addressPlace! ?? "")
            let alertController = UIAlertController(title: "Точка добавлена в маршрут", message: message, preferredStyle: .alert)
            let cancelAction = UIAlertAction(title: "Ок", style: .default, handler: { (action : UIAlertAction!) -> Void in })
            alertController.addAction(cancelAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
    // MARK: - ОБРАБОТКА ПОИСКОВОГО ЗАПРОСА
    func onSearchResponse(_ response: YMKSearchResponse) {
        let metadata = response.collection.children.first?.obj?.metadataContainer
        //если это географический объект (топоним)
        if let x = metadata?.getItemOf(YMKSearchToponymObjectMetadata.self) as? YMKSearchToponymObjectMetadata {
            var address : [String] = []
            for item in x.address.components {
//                print(item.kinds, item.name)
                if (Int(truncating: item.kinds[0]) >= 5) {
                    address.append(item.name)
                }
            }
            let addressString = address.joined(separator: ", ")
            print("\n\nАДРЕС ТОПОНИМА: \(addressString)\n\n")
            addressPlace = addressString
        }
        //если это организация
        if let x = metadata?.getItemOf(YMKSearchBusinessObjectMetadata.self) as? YMKSearchBusinessObjectMetadata {
            var address : [String] = []
            for item in x.address.components {
//                print(item.kinds, item.name)
                if (Int(truncating: item.kinds[0]) >= 5) {
                    address.append(item.name)
                }
            }
            let addressString = address.joined(separator: ", ")
            print("\n\nАДРЕС ОРГАНИЗАЦИИ: \(addressString)")
            print("НАЗВАНИЕ ОРГАНИЗАЦИИ: \(x.name)\n\n")
            addressPlace = addressString
        }
        
        //если определяем местоположение пользователя
        if isUserPointSearching {
        } else {
            let mapObjects = mapView.mapWindow.map.mapObjects
            mapObjects.clear()
            //добавляем маркеры на найденные объекты
            for searchResult in response.collection.children {
                if let point = searchResult.obj?.geometry.first?.point {
                    let placemark = mapObjects.addPlacemark(with: point)
                    placemark.setIconWith(UIImage(named: "SearchResult")!)
                    searchPoint = point
                    if (!isMultipleSearching && !wasCameraMovedToPoint) {
                        mapView.mapWindow.map.move(with: YMKCameraPosition(
                                                    target: point,
                                                    zoom: (currentZoom < 16.0 ? 16.0 : currentZoom),
                                                    azimuth: 0,
                                                    tilt: 0)
                        )
                        wasCameraMovedToPoint = true
                    }
                }
            }
        }
    }
    func onSearchError(_ error: Error) {
        let searchError = (error as NSError).userInfo[YRTUnderlyingErrorKey] as! YRTError
        var errorMessage = "Unknown error: \(searchError.description)"
        if searchError.isKind(of: YRTNetworkError.self) {
            errorMessage = "Network error"
        } else if searchError.isKind(of: YRTRemoteError.self) {
            errorMessage = "Remote server error"
        }
        let alert = UIAlertController(title: "Error", message: errorMessage, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
    // MARK: - Местоположение пользователя
    @IBAction func userLocationButtonPressed(_ sender: UIButton) {
        isCameraListening = true
        mapView.mapWindow.map.deselectGeoObject()
        userLocationLayer!.setVisibleWithOn(true)
        userLocationLayer!.isHeadingEnabled = true
        print("начинаем следить")
        userLocationLayer!.setAnchorWithAnchorNormal(
            CGPoint(x: 0.5 * mapView.frame.size.width * scale, y: 0.5 * mapView.frame.size.height * scale),
            anchorCourse: CGPoint(x: 0.5 * mapView.frame.size.width * scale, y: 0.83 * mapView.frame.size.height * scale))
        userLocationLayer!.setObjectListenerWith(self)
        userLocationLayer!.isHeadingEnabled = false
        print("меняем зум (\(currentZoom) на \(currentZoom < 16.0 ? 16.0 : currentZoom)")
        mapView.mapWindow.map.move(with: YMKCameraPosition(
            target: userPoint!,
            zoom: (currentZoom < 16.0 ? 16.0 : currentZoom), //если зум слишком маленький, то установить на комфортный 16.0
            azimuth: 0,
            tilt: 0)
        )
    }
    //иконка пользователя (all done)
    func onObjectAdded(with view: YMKUserLocationView) {
                
        view.arrow.setIconWith(UIImage(named:"Icon")!)
        
        let pinPlacemark = view.pin.useCompositeIcon()
        
        pinPlacemark.setIconWithName("icon",
                                     image: UIImage(named:"Icon")!,
                                     style:YMKIconStyle(
                                        anchor: CGPoint(x: 0.5, y: 1) as NSValue,
                                        rotationType:YMKRotationType.rotate.rawValue as NSNumber,
                                        zIndex: 1,
                                        flat: true,
                                        visible: true,
                                        scale: 1,
                                        tappableArea: nil))
        
        pinPlacemark.setIconWithName("pin",
            image: UIImage(named:"SearchResult")!,
            style:YMKIconStyle(
                anchor: CGPoint(x: 0.5, y: 0.5) as NSValue,
                rotationType:YMKRotationType.rotate.rawValue as NSNumber,
                zIndex: 1,
                flat: true,
                visible: true,
                scale: 1,
                tappableArea: nil))
        
        view.accuracyCircle.fillColor = UIColor.gray.withAlphaComponent(0.5)
    }
    func onObjectRemoved(with view: YMKUserLocationView) { }
    func onObjectUpdated(with view: YMKUserLocationView, event: YMKObjectEvent) { }
    
    // MARK: - Обработка кликов по объектам
    func checkPlace(point: YMKPoint) -> Place? {
        let geoPointLatitude = point.latitude
        let geoPointLongitude = point.longitude
        let newPlace = Place( userName: "", geoName: "", address: "", type: "",
                              geoPoint: GeoPoint(geoPointLatitude: geoPointLatitude, geoPointLongitude: geoPointLongitude, address: "", location: "")
        )
        let place = StorageManager.getPlace(newPlace)
        if (place != nil) {
            print("такое место уже есть, вот вам инфа о нем")
            return place
        } else {
            print("таких мест нет, сори")
            return nil
        }
    }
    //конкретный геообъект (магазин, памятник, дом, ТЦ...)
    func onObjectTap(with: YMKGeoObjectTapEvent) -> Bool {
        isCameraListening = false //прекращаем отслеживать изменения камеры и делать новые запросы
        if (mapMode == .Routing) {
            if (polyline != nil) { //если маршрут построен
                print("переключаемся на режим поиска")
            } else {
                print("маршрут не построен, переключаемся на режим поиска")
            }
            mapMode = .Searching // переключаемся на режим поиска
            routeButton.title = "Построить маршрут"
            polyline = nil //обнуляем линию маршрута
        }
        mapView.mapWindow.map.deselectGeoObject()
        mapView.mapWindow.map.mapObjects.clear()

        //определеяем название и координаты
        let obj = with.geoObject
        
        print("имя объекта на карте:", obj.name ?? "unknown")
                
        // MARK: - имя объекта на карте + точка -> поиск по этому имени, и среди всех найденных элементов сравнивать точку

        // MARK: - Вычисляем координаты объекта
        guard let point = obj.geometry.first?.point else { return true }
        print("coordinates: lat \(point.latitude) lon \(point.longitude)")
        searchPoint = point
        if (Reachability.isConnectedToNetwork()){
            //получаем информацию об объекте (название, адрес и тип объекта)
            getName(point: point, zoom: NSNumber(value: currentZoom), nameOfGeoObject: obj.name)
        } else {
            let place = checkPlace(point: point)
            if (place != nil) {
                namePlace = "\(place!.userName) (\(place!.geoName))"
                addressPlace = place!.address
                typePlace = place?.type
            } else {
                addressPlace = obj.descriptionText ?? "НЕИЗВЕСТНО"
                namePlace = obj.name ?? "НЕИЗВЕСТНО"
                typePlace = "НЕИЗВЕСТНО"
            }
            self.performSegue(withIdentifier: "geoObjectInfo", sender: self)
        }
        // MARK: - Выделяем объект
        let event = with
        let metadata = event.geoObject.metadataContainer.getItemOf(YMKGeoObjectSelectionMetadata.self)
        if let selectionMetadata = metadata as? YMKGeoObjectSelectionMetadata {
            mapView.mapWindow.map.selectGeoObject(withObjectId: selectionMetadata.id, layerId: selectionMetadata.layerId)
            return true
        }
        return false
        
    }
    //если клик в рандомном месте, не на объекте (озеро, поле, гора)
    func onMapTap(with map: YMKMap, point: YMKPoint) {
        isCameraListening = false //прекращаем отслеживать изменения камеры и делать новые запросы
        if (mapMode == .Routing) {
            if (polyline == nil) { //если маршрут не построен
                print("что-то пошло не так, маршрут не построен")
            }
            mapMode = .Searching // переключаемся на режим поиска
            routeButton.title = "Построить маршрут"
            polyline = nil //обнуляем линию маршрута
        }
        mapView.mapWindow.map.deselectGeoObject()
        let mapObjects = mapView.mapWindow.map.mapObjects
        mapObjects.clear()
        let placemark = mapObjects.addPlacemark(with: point)
        placemark.setIconWith(UIImage(named: "SearchResult")!)
        searchPoint = point
        if (Reachability.isConnectedToNetwork()){
            //получаем информацию об объекте (название, адрес и тип объекта)
            getName(point: point, zoom: NSNumber(value: currentZoom), nameOfGeoObject: nil)
        }
        else {
            let place = checkPlace(point: point)
            if (place != nil) {
                namePlace = place!.userName
                addressPlace = place!.address
                typePlace = place?.type
            } else {
                addressPlace = "НЕИЗВЕСТНО"
                namePlace = "НЕИЗВЕСТНО"
                typePlace = "НЕИЗВЕСТНО"
            }
            
            self.performSegue(withIdentifier: "geoObjectInfo", sender: self)
        }
        print("Широта: \(point.latitude), Долгота: \(point.longitude)")
        
    }
    func onMapLongTap(with map: YMKMap, point: YMKPoint) { }
    
    
    // MARK: - Строим маршрут
    
    func makeTheRoute(from pointA: YMKPoint, to pointB: YMKPoint) {
        
        // очищаем карту от точек и выделений
        mapView.mapWindow.map.deselectGeoObject()
        let mapObjects = mapView.mapWindow.map.mapObjects
        mapObjects.clear()
        
        // перемещаем камеру на точку А
        mapView.mapWindow.map.move(
            with: YMKCameraPosition(target: pointA, zoom: currentZoom, azimuth: 0, tilt: 0),
            animationType: YMKAnimation(type: YMKAnimationType.smooth, duration: 5),
            cameraCallback: nil
        )
        
        //ставим маркеры на точки А и Б
        let placemarkA = mapObjects.addPlacemark(with: pointA)
        placemarkA.setIconWith(UIImage(named: "SearchResult")!)
        let placemarkB = mapObjects.addPlacemark(with: pointB)
        placemarkB.setIconWith(UIImage(named: "SearchResult")!)
        
        //проверяем, есть ли уже этот маршрут в базе данных
        let route = checkRoute(from: pointA, to: pointB)
        
        if (saveOrDeleteMode == .Save) { //маршрута нет в БД, строим и сохраняем
            if (Reachability.isConnectedToNetwork()) { //если есть интернет, то строим по интернету
                //добавляем точки в маршрут
                let requestPoints : [YMKRequestPoint] = [
                    YMKRequestPoint(point: pointA, type: .waypoint, pointContext: nil),
                    YMKRequestPoint(point: pointB, type: .waypoint, pointContext: nil),
                ]
                switch typeRoute {
                case "Pedestrian":
                    // MARK: - Пешеход
                    let responseHandlerForPedestrian = {(routesResponse: [YMKMasstransitRoute]?, error: Error?) -> Void in
                        if let routes = routesResponse {
                            self.onRoutesForPedestrianReceived(routes)
                        } else {
                            self.onRoutesError(error!)
                        }
                    }
                    let pedestrianRouter = YMKTransport.sharedInstance().createPedestrianRouter()
                    drivingSessionForPedestrian = pedestrianRouter.requestRoutes(
                        with: requestPoints,
                        timeOptions: YMKTimeOptions(),
                        routeHandler: responseHandlerForPedestrian
                    )
                case "Car" :
                    // MARK: - Машина
                    //изменил ? на !
                    let responseHandler = {(routesResponse: [YMKDrivingRoute]?, error: Error?) -> Void in
                        if let routes = routesResponse {
                            self.onRoutesReceived(routes)
                        } else {
                            self.onRoutesError(error!)
                        }
                    }
                    let drivingRouter = YMKDirections.sharedInstance().createDrivingRouter()
                    drivingSession = drivingRouter.requestRoutes(
                        with: requestPoints,
                        drivingOptions: YMKDrivingDrivingOptions(),
                        vehicleOptions: YMKDrivingVehicleOptions(),
                        routeHandler: responseHandler)
                default:
                    print("Тип маршрута указан неверно")
                }
            }
            else {
                print("нет интернета, нельзя построить маршрут")
                alertSituation = AlertSituation.Offline
                drivingSessionForPedestrian = nil
                drivingSession = nil
            }
        }
        else { //маршрут есть в БД, строим по данным БД
            print("маршрут есть в БД, строим по данным БД")
            if (route != nil) {
                showRouteFromDB(route: route!)
                
            }
        }
    }
    
    func showRouteFromDB(route: Route) {
    
        // MARK: - test
        let arrayOfPointsForRoute : [GeoPoint] = Array(route.routeArray)
        
        let countOfPoints = arrayOfPointsForRoute.count
        print("в массиве БД есть маршрут с \(countOfPoints) точками, строим маршрут")
        let mapObjects = mapView.mapWindow.map.mapObjects
        
        var polylineArray : [YMKPoint] = []
        
        for point in arrayOfPointsForRoute {
            polylineArray.append(YMKPoint(latitude: point.geoPointLatitude, longitude: point.geoPointLongitude))
        }

        let newPolyline = YMKPolyline(points: polylineArray)
        polyline = mapObjects.addPolyline(with: newPolyline)
        if (polyline != nil) { polyline!.addTapListener(with: self) }
        
        let userPoint = GeoPointToSend(address: pointBAddress, location: "\(route.pointB!.geoPointLatitude);\(route.pointB!.geoPointLongitude)")
        
        try! realm.write { arrayOfUserPoints.append(userPoint) }
        if StorageManager.getPoint(userPoint) == nil {
            print("nil")
            StorageManager.saveUserPoint(userPoint)
            
        } else {
            print("not nil -> сохранить")
//            StorageManager.saveUserPoint(userPoint)
        }
        
        self.viewDidAppear(true)
        alertSituation = AlertSituation.routingFromDB
        
    }
    
    // MARK: - Проверка наличия маршрута в БД (если есть - то режим "Удалить", если нет - то режим "Построить")
    func checkRoute(from pointA: YMKPoint, to pointB: YMKPoint) -> Route? {
        let geoPointA = GeoPoint(geoPointLatitude: pointA.latitude, geoPointLongitude: pointA.longitude, address: "", location: "")
        let geoPointB = GeoPoint(geoPointLatitude: pointB.latitude, geoPointLongitude: pointB.longitude, address: "", location: "")
        let newRoute = Route(
            userNameForRoute: "",
            addressOfPointA: nil,
            addressOfPointB: nil,
            pointA: StorageManager.getPoint(geoPointA) ?? geoPointA,
            pointB: StorageManager.getPoint(geoPointB) ?? geoPointB,
            routeArray: List<GeoPoint>(),
            routeUserArray: List<GeoPointToSend>()
        )
        let routeFromDB = StorageManager.getRoute(newRoute)
        if (routeFromDB != nil) {
            print("такой маршрут уже есть (в нем \(routeFromDB!.routeArray.count) точек)")
            routeButton.title = "Удалить маршрут"
            saveOrDeleteMode = .Delete
        } else {
            print("таких маршрутов нет, сохраняем")
            routeButton.title = "Сохранить маршрут"
            saveOrDeleteMode = .Save
        }
        return routeFromDB
    }
    
    // MARK: - Обрабатываем нажатия на маршрут (добавляем точки в массив пользовательских точек маршрута)
    func onMapObjectTap(with mapObject: YMKMapObject, point: YMKPoint) -> Bool {
                
        saveOrDeleteMode = .Save
        routeButton.title = "Сохранить маршрут"
        
        let mapObjects = mapView.mapWindow.map.mapObjects
        let placemark = mapObjects.addPlacemark(with: point)
        placemark.setIconWith(UIImage(named: "SearchResult")!)
        
        searchPoint = point
        if (Reachability.isConnectedToNetwork()){
            //получаем информацию об объекте (название и адрес, если они есть)
            getName(point: point, zoom: NSNumber(value: currentZoom), nameOfGeoObject: nil)
        }
        else {
            let place = checkPlace(point: point)
            if (place != nil) {
                namePlace = place!.userName
                addressPlace = place!.address
                typePlace = place?.type
            } else {
                addressPlace = "НЕИЗВЕСТНО"
                namePlace = "НЕИЗВЕСТНО"
                typePlace = "НЕИЗВЕСТНО"
            }
            
            let alertController = UIAlertController(title: "Точка добавлена в маршрут", message: "test", preferredStyle: .alert)
            let cancelAction = UIAlertAction(title: "Ок", style: .default, handler: { (action : UIAlertAction!) -> Void in })
            alertController.addAction(cancelAction)
            self.present(alertController, animated: true, completion: nil)
        }
        
        let userPoint = GeoPointToSend(address: addressPlace!, location: "\(point.latitude);\(point.longitude)")
        try! realm.write { arrayOfUserPoints.append(userPoint) }
        if StorageManager.getPoint(userPoint) == nil { StorageManager.saveUserPoint(userPoint) }
        
        return true
    }
    // MARK: - Обработка пешеходного маршрута
    func onRoutesForPedestrianReceived(_ routes: [YMKMasstransitRoute]) {
        let mapObjects = mapView.mapWindow.map.mapObjects
        // выбираем первый маршрут (самый оптимальный), выбор маршрутов не стал реализовывать
        // вариант взаимодействия с несколькими: на каждый маршрут (polyline) повесить слушателя и определять, на какой из них нажали
        
        if (routes.isEmpty) {
            print("Ошибка. Маршрут не построен")
            
            let alertController = UIAlertController(title: "Маршрут не построен!", message: "Произошла ошибка. \nВозможно, расстояние между точками слишком большое. \nВ приложении реализован только пешеходный маршрут на небольшие расстояния!", preferredStyle: .alert)
            let cancelAction = UIAlertAction(title: "Ок", style: .default, handler: { (action : UIAlertAction!) -> Void in })
            alertController.addAction(cancelAction)
            self.present(alertController, animated: true, completion: nil)
            
        }
        else {
            let route  = routes[0]
            let countOfPoints = route.geometry.points.count
            print("\nВ вашем пешеходном маршруте \(countOfPoints) точек")
            let pointA_ = GeoPoint(geoPointLatitude: pointA.latitude, geoPointLongitude: pointA.longitude, address: pointAAddress, location: "\(pointA.latitude);\(pointA.longitude)")
            try! realm.write { arrayOfPoints.append(pointA_) }
            for i in 0..<countOfPoints {
                let latitude = route.geometry.points[i].latitude
                let longitude = route.geometry.points[i].longitude
                let geoPoint = GeoPoint(geoPointLatitude: latitude, geoPointLongitude: longitude, address: "", location: "")
                StorageManager.savePoint(geoPoint)
                try! realm.write { arrayOfPoints.append(geoPoint) }
            }
            
            let pointB_ = GeoPoint(geoPointLatitude: pointB.latitude, geoPointLongitude: pointB.longitude, address: pointBAddress, location: "\(pointB.latitude);\(pointB.longitude)")
            try! realm.write { arrayOfPoints.append(pointB_) }
                    
            print("Точка А: \(pointA.latitude), \(pointA.longitude)")
            print("Точка Б: \(pointB.latitude), \(pointB.longitude)")
            
            print("\n\nмассив точек: \(arrayOfPoints)\n\n")
            
            polyline = mapObjects.addPolyline(with: route.geometry)
            if (polyline != nil) { polyline!.addTapListener(with: self) }
            
            let alertController = UIAlertController(title: "Нажмите кнопку \n'Сохранить маршрут' \nили выберите конкретные точки маршрута для сохранения", message: nil, preferredStyle: .alert)
            let cancelAction = UIAlertAction(title: "Ок", style: .default, handler: { (action : UIAlertAction!) -> Void in })
            alertController.addAction(cancelAction)
            self.present(alertController, animated: true, completion: nil)
        }
        
        
    }
    // MARK: - Обработка автомобильного маршрута (не использую)
    func onRoutesReceived(_ routes: [YMKDrivingRoute]) {
        let mapObjects = mapView.mapWindow.map.mapObjects
        // MARK: - один маршрут
        let route = routes[0]
        let countOfPoints = route.geometry.points.count
        print("\nСамый оптимальный маршрут c числом точек: \(countOfPoints)")
        for i in 0..<countOfPoints {
//            let latitude = route.geometry.points[i].latitude
//            let longitude = route.geometry.points[i].longitude
//            cordsToFile = cordsToFile + "\(latitude);\(longitude) \n"
        }
        //            writeInFile(text: cordsToFile)
        mapObjects.addPolyline(with: route.geometry)
        
        // MARK: - несколько маршрутов
        if (1 == 2) {
            for (index,route) in routes.enumerated() {
                print("Маршрут №\(index + 1)")
                let countOfPoints = route.geometry.points.count
                print("\nВ вашем маршруте \(countOfPoints) точек")
                for i in 0..<countOfPoints {
//                    let latitude = route.geometry.points[i].latitude
//                    let longitude = route.geometry.points[i].longitude
//                    cordsToFile = cordsToFile + "\(latitude);\(longitude) \n"
                }
                //            writeInFile(text: cordsToFile)
                let polyline = mapObjects.addPolyline(with: route.geometry)
                if (index == 0) { polyline.strokeColor = .blue }
                else { polyline.strokeColor = .gray }
            }
        }
    }
    //проверка ошибок при построении маршрута
    func onRoutesError(_ error: Error) {
        let routingError = (error as NSError).userInfo[YRTUnderlyingErrorKey] as! YRTError
        var errorMessage = "Unknown error"
        if routingError.isKind(of: YRTNetworkError.self) { errorMessage = "Network error" }
        else if routingError.isKind(of: YRTRemoteError.self) { errorMessage = "Remote server error" }
        let alert = UIAlertController(title: "Error", message: errorMessage, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
        routeButton.isEnabled = false
    }
    

    
    func share(url: URL) {
        documentInteractionController.url = url
        documentInteractionController.uti = url.typeIdentifier ?? "public.data, public.content"
        documentInteractionController.name = url.localizedName ?? url.lastPathComponent
        documentInteractionController.presentOptionsMenu(from: view.frame, in: view, animated: true)
    }
    
    func deleteCache() {
        let fileManager = FileManager.default
        let documentsUrl =  fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!.path
        do {
            let fileNames = try fileManager.contentsOfDirectory(atPath: "\(documentsUrl)")
            print("all files in cache: \(fileNames)")
            for fileName in fileNames {
                if (fileName.hasSuffix(".json"))
                {
                    let filePathName = "\(documentsUrl)/\(fileName)"
                    try fileManager.removeItem(atPath: filePathName)
                }
            }
            let files = try fileManager.contentsOfDirectory(atPath: "\(documentsUrl)")
            print("all files in cache after deleting images: \(files)")
        } catch {
            print("Could not clear temp folder: \(error)")
        }
    }
    
    func showJSON() {
        
        deleteCache() //удаляем все предыдущие json файлы
        
        // получаем текущую дату
        let time = NSDate()
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.YYYY-HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)            // указатель временной зоны относительно гринвича
        let formatteddate = formatter.string(from: time as Date)
        let dateString = "\(formatteddate)"
        
        var info :  [String : AnyObject] = [:] //во что преобразуем
        let routeToSend = RouteToSend(
            NameRoute: userNameForRoute!,
            Point_A: pointAAddress,
            Point_B: pointBAddress,
            ArrData: arrayOfUserPoints
        )
        var dicArray = Dictionary<String,AnyObject>()
        dicArray = routeToSend.toDictionary()
        info = dicArray
        
        //сохраняем объект routeToSend в виде JSON
        let documentsUrl =  FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.path
        let pathToFile = "\(documentsUrl)/Route (\(dateString)).json"
        do {
            if let data = try? JSONSerialization.data(withJSONObject: info, options: JSONSerialization.WritingOptions.prettyPrinted) {
                if !FileManager.default.fileExists(atPath: URL(fileURLWithPath: pathToFile).path) {
                    FileManager.default.createFile(atPath: pathToFile, contents: data, attributes: nil)
                }
                try data.write(to: URL(fileURLWithPath: pathToFile), options: .atomic)
            } else {
                print("error")
            }
        } catch { print(error) }
        //предлагаем пользователю отправить/сохранить этот JSON-файл
        let url = URL(fileURLWithPath: pathToFile)
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else { return }
            do {
                try data.write(to: url)
                DispatchQueue.main.async { self.share(url: url) }
            }
            catch { print("ошибка: \(error)") }
        }.resume()
        
    }
    
    func saveTheRoute() {
        print("сохраняем маршрут...")
        let pointA = GeoPoint(geoPointLatitude: pointA.latitude, geoPointLongitude: pointA.longitude, address: pointAAddress, location: "\(pointA.latitude);\(pointA.longitude)")
        let pointB = GeoPoint(geoPointLatitude: pointB.latitude, geoPointLongitude: pointB.longitude, address: pointBAddress, location: "\(pointB.latitude);\(pointB.longitude)")
        
        let userPoint = GeoPointToSend(address: pointBAddress, location: "\(pointB.geoPointLatitude);\(pointB.geoPointLongitude)")
        
        if StorageManager.getPoint(userPoint) == nil { //сохраняем в конце массива точку Б
            try! realm.write { arrayOfUserPoints.append(userPoint) }
            StorageManager.saveUserPoint(userPoint)
        }
        
        let route = Route(
            userNameForRoute: userNameForRoute!,
            addressOfPointA: pointAAddress,
            addressOfPointB: pointBAddress,
            pointA: StorageManager.getPoint(pointA) ?? pointA,
            pointB: StorageManager.getPoint(pointB) ?? pointB,
            routeArray: arrayOfPoints,
            routeUserArray: arrayOfUserPoints
        )
        
        showJSON()
        
        StorageManager.saveRoute(route)
        
        routeButton.title = "Удалить маршрут"
        saveOrDeleteMode = .Delete
    }
    
    // MARK: - тест - удаление маршрутов с пересекающимися точками
    func deleteTheRoute() {
        print("удаляем маршрут...")
        let route = checkRoute(from: pointA, to: pointB)
        StorageManager.deleteRoute(route!)
        routeButton.title = "Сохранить маршрут"
        saveOrDeleteMode = .Save
    }
    
    //ALL DONE //сохраняем или удаляем маршрут в/из БД
    func saveOrDeleteTheRouteButtonPressed() {
        if (saveOrDeleteMode == .Save) {
            let alertController = UIAlertController(title: "Как сохранить этот маршрут?", message: "", preferredStyle: .alert)
            alertController.addTextField { (textField : UITextField!) -> Void in
                textField.placeholder = "Название маршрута"
                textField.clearButtonMode = .whileEditing
            }
            let saveAction = UIAlertAction(title: "Сохранить", style: .default, handler: { alert -> Void in
                let textField = alertController.textFields![0] as UITextField
                if (textField.text == "") {
                    let defaultRouteName = "от \(self.pointAName) до \(self.pointBName)"
                    print("сохраняем по умолчанию как \(defaultRouteName)")
                    self.userNameForRoute = defaultRouteName
                } else {
                    print("сохраняем с пользовательским именем \(textField.text!)")
                    self.userNameForRoute = textField.text!
                }
                self.saveTheRoute()
            })
            let cancelAction = UIAlertAction(title: "Отменить", style: .default, handler: { (action : UIAlertAction!) -> Void in })
            alertController.addAction(saveAction)
            alertController.addAction(cancelAction)
            self.present(alertController, animated: true, completion: nil)
        }
        else {
            let alertController = UIAlertController(title: "Вы уверены, что хотите удалить этот маршрут?", message: "", preferredStyle: .alert)
            let deleteAction = UIAlertAction(title: "Удалить", style: .default, handler: { alert -> Void in
                self.deleteTheRoute()
            })
            let cancelAction = UIAlertAction(title: "Отменить", style: .default, handler: { (action : UIAlertAction!) -> Void in })
            alertController.addAction(deleteAction)
            alertController.addAction(cancelAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    // MARK: - Segues
        
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if (segue.identifier == "geoObjectInfo") {
            if let dest = segue.destination as? TappedObjectTableTableViewController {
                dest.infoForPoint = searchPoint!
                dest.addressPlaceFromTap = addressPlace
                dest.namePlaceFromTap = namePlace
                dest.typePlaceFromTap = typePlace
                self.halfModalTransitioningDelegate = HalfModalTransitioningDelegate(viewController: self, presentingViewController: dest)
                dest.modalPresentationStyle = .custom
                dest.transitioningDelegate = self.halfModalTransitioningDelegate
            } else {
                print("ошибка")
            }
        }
        if (segue.identifier == "placesForRoute") {
            print("segue to placesForRoute")
            isCameraListening = false //перестаем слушать камеру
            userLocationLayer?.resetAnchor()
        }
    }
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        if (identifier == "placesForRoute") {
            if (mapMode == MapMode.Routing) {
                print("отключаем сегвей к placesForRoute")
                saveOrDeleteTheRouteButtonPressed()
                return false
            }
        }
        return true
    }
    
    @IBAction func unwindSegue(_ segue: UIStoryboardSegue) {
        alertSituation = .Default
        guard let sourceVC = segue.source as? TableForRouteViewController else { return }
        if (segue.identifier == "makeTheRoute") {
            sourceVC.makeTheRoute()
            pointA = YMKPoint(latitude: sourceVC.pointA.geoPoint!.geoPointLatitude, longitude: sourceVC.pointA.geoPoint!.geoPointLongitude)
            pointB = YMKPoint(latitude: sourceVC.pointB.geoPoint!.geoPointLatitude, longitude: sourceVC.pointB.geoPoint!.geoPointLongitude)
            pointAName = sourceVC.pointA.userName
            pointBName = sourceVC.pointB.userName
            pointAAddress = sourceVC.pointA.address!
            pointBAddress = sourceVC.pointB.address!
            print("строим маршрут от \(pointAName) до \(pointBName)")
            routeButton.title = "Сохранить маршрут"
            mapMode = MapMode.Routing
                    
//            try! realm.write { realm.delete(arrayOfUserPoints) }
            
            let userPoint = GeoPointToSend(address: pointAAddress, location: "\(pointA.latitude);\(pointA.longitude)")
            try! realm.write { arrayOfUserPoints.append(userPoint) }
            if StorageManager.getPoint(userPoint) == nil {
                StorageManager.saveUserPoint(userPoint)
            }
            
            makeTheRoute(from: pointA, to: pointB)
//            print("\n если переходим из построения маршрута, то теперь кнопка Назад ведет к нему же \n")
        }
        if (segue.identifier == "backToSearch") { mapMode = MapMode.Searching }
        print("очищаем все после выхода")
        sourceVC.tableView = nil
    }
    
}


// MARK: - Местоположение пользователя (YMKLocationDelegate) - не разобрался, не стал использовать
//extension SearchViewController : YMKLocationDelegate {
//    func onLocationUpdated(with location: YMKLocation) {
//        print("Новые координаты: \(location.position.latitude), \(location.position.longitude)")
//    }
//
//    func onLocationStatusUpdated(with status: YMKLocationStatus) {
//        print("Новый статус")
//    }
//}

