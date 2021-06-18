import UIKit
import YandexMapsMobile
import CoreLocation
import RealmSwift
import SwiftyJSON
import GoogleMaps
import GooglePlaces
import Alamofire

class MainViewController: UIViewController, YMKMapCameraListener, YMKUserLocationObjectListener, YMKLayersGeoObjectTapListener, YMKMapInputListener, YMKMapObjectTapListener {

    @IBOutlet weak var myGeoButton: UIButton!
    @IBOutlet weak var routeButton: UIBarButtonItem!
    @IBOutlet weak var viewWithMap: UIView!
    
    // MARK: - Общие свойства
    let scale = UIScreen.main.scale
    var halfModalTransitioningDelegate: HalfModalTransitioningDelegate?
    var alertSituation = AlertSituation.Default //0 - ничего не показываем, 1 - нет соединения с интернетом, 2 - строим по БД
    var currentZoom : Float = 16.0
    let mapKit = YMKMapKit.sharedInstance()
    var YandexMapView : YMKMapView? = YMKMapView()
    var GoogleMapView: GMSMapView? = GMSMapView()
    var wasCameraMovedToPoint : Bool = false //костыль для перемещения камеры на найденную точку (не знаю, как отключить onCameraPositionChanged)
    var isCameraListening : Bool = true //костыль для отключения YMKMapCameraListener
    var mapMode = MapMode.Searching // режим карты (по умолчанию - поиск)
    let documentInteractionController = UIDocumentInteractionController() // контроллер для взаимодействия с файлом (скопировать, отправить и прочее)
    var geoAllowState = GeoAllowState.no //разрешен ли доступ к геопозиции (если нет, то кнопка "Моя геопозиция" не будет работать)
    var mapType = MapType.Yandex // через какой сервис строить маршрут?
    var userLocationLayer : YMKUserLocationLayer?;
        
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
    
    // MARK: - Свойства для построения маршрута
    var route = Route()
    var arrayOfPoints : [GeoPoint] = []
    var arrayOfUserPoints : [GeoPointToSend] = []
    var pointA = YMKPoint(); var pointAName = ""; var pointAAddress = ""
    var pointB = YMKPoint(); var pointBName = ""; var pointBAddress = ""
    var userNameForRoute : String? = ""
    var drivingSession: YMKDrivingSession?
    var drivingSessionForPedestrian : YMKMasstransitSession?
    var typeRoute = "Pedestrian" //тип маршрутизации (по умолчанию - пешеход)
    var saveOrDeleteMode = SaveOrDeleteMode.Save
    var polyline : YMKPolylineMapObject? //линия маршрута (массив точек)
    var geometryOfRoute: String? = "" // закодированная геометрия маршрута (для Google Maps)
    
    // MARK: - Общие Методы
    override func viewDidLoad() {
        super.viewDidLoad()
        
        YandexMapView = YMKMapView(frame: self.view.frame)
        self.viewWithMap.addSubview(YandexMapView!)
        self.viewWithMap.addSubview(myGeoButton!)

        YandexMapView!.mapWindow.map.addTapListener(with: self)
        YandexMapView!.mapWindow.map.addInputListener(with: self)
        YandexMapView!.mapWindow.map.addCameraListener(with: self)
        userLocationLayer = mapKit.createUserLocationLayer(with: YandexMapView!.mapWindow)
        
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
            let mapObjects = YandexMapView!.mapWindow.map.mapObjects
            mapObjects.clear()
            //добавляем маркер на объект
            let placemark = mapObjects.addPlacemark(with: target)
            placemark.setIconWith(UIImage(named: "SearchResult")!)
            wasCameraMovedToPoint = true
            self.performSegue(withIdentifier: "geoObjectInfo", sender: self)
        }

        //перемещаем карту к цели
        YandexMapView!.mapWindow.map.move(with: YMKCameraPosition(
            target: target,
            zoom: (currentZoom < 16.0 ? 16.0 : currentZoom),
            azimuth: 0,
            tilt: 0)
        )
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if (alertSituation == .askForMapType) {
            print("askForMapType alertSituation called")
            let alertController = UIAlertController(title: "С помощью какого сервиса вы хотите построить маршрут?", message: nil, preferredStyle: .alert)
            let routeFromYandex = UIAlertAction(title: "Яндекс.Карты", style: .default, handler: { alert -> Void in
                if (self.YandexMapView == nil) {

                    self.YandexMapView = YMKMapView(frame: self.view.frame)
                    self.viewWithMap.addSubview(self.YandexMapView!)
                    self.viewWithMap.addSubview(self.myGeoButton!)

                    self.YandexMapView!.mapWindow.map.addTapListener(with: self)
                    self.YandexMapView!.mapWindow.map.addInputListener(with: self)
                    self.YandexMapView!.mapWindow.map.addCameraListener(with: self)
                    self.userLocationLayer = self.mapKit.createUserLocationLayer(with: self.YandexMapView!.mapWindow)
                    
                }
                self.mapType = .Yandex
                self.GoogleMapView?.removeFromSuperview()
                self.GoogleMapView = nil
                self.makeTheRoute(from: self.pointA, to: self.pointB)
            })
            let routeFromGoogle = UIAlertAction(title: "Google Maps", style: .default, handler: { alert -> Void in
                self.mapType = .Google
                self.YandexMapView?.removeFromSuperview() //убираем яндекс-карты с экрана
                self.YandexMapView = nil //удаляем яндекс-карты из памяти
                
                let camera = GMSCameraPosition.camera(withLatitude: 0, longitude: 0, zoom: 15.0) //Казань
                self.GoogleMapView = GMSMapView.map(withFrame: self.view.frame, camera: camera)
                self.view.addSubview(self.GoogleMapView!)
                
                self.makeTheRoute(from: self.pointA, to: self.pointB)
            })
            alertController.addAction(routeFromYandex)
            alertController.addAction(routeFromGoogle)
            self.present(alertController, animated: true, completion: nil)
        }
        if (alertSituation == .routingFromDB) {
            let alertController = UIAlertController(title: "Маршрут '\(userNameForRoute!)'", message: "Такой маршрут уже есть в Базе данных \n Строим по нему", preferredStyle: .alert)
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
    //удаляем все данные при переходе назад, чтобы не грузить память устройства
    func cancelAction() {
        searchManager = nil
        searchRequest = nil
        searchSession = nil
        userLocationLayer = nil
        if (YandexMapView != nil) { YandexMapView?.removeFromSuperview() } //убираем с экрана
        YandexMapView = nil //удаляем из памяти
        if (GoogleMapView != nil) { GoogleMapView?.removeFromSuperview() } //убираем с экрана
        GoogleMapView = nil //удаляем из памяти
        dismiss(animated: true)
    }
    
    // !!! MARK: - обработка для гугла
    // MARK: - Местоположение пользователя
    @IBAction func userLocationButtonPressed(_ sender: UIButton) {
        
        if (geoAllowState == .no) {
            print("\nИщем мое местоположение, но доступа нет")
            let alertController = UIAlertController(title: "Нет доступа к вашей геопозиции!", message: "Измените доступ в настройках!", preferredStyle: .alert)
            let cancelAction = UIAlertAction(title: "Ок", style: .default, handler: { alert -> Void in })
            alertController.addAction(cancelAction)
            self.present(alertController, animated: true, completion: nil)
        } else {
            isCameraListening = true
            YandexMapView!.mapWindow.map.deselectGeoObject()
            userLocationLayer!.setVisibleWithOn(true)
            userLocationLayer!.isHeadingEnabled = true
            print("начинаем следить")
            userLocationLayer!.setAnchorWithAnchorNormal(
                CGPoint(x: 0.5 * YandexMapView!.frame.size.width * scale, y: 0.5 * YandexMapView!.frame.size.height * scale),
                anchorCourse: CGPoint(x: 0.5 * YandexMapView!.frame.size.width * scale, y: 0.83 * YandexMapView!.frame.size.height * scale))
            userLocationLayer!.setObjectListenerWith(self)
            userLocationLayer!.isHeadingEnabled = false
            print("меняем зум (\(currentZoom) на \(currentZoom < 16.0 ? 16.0 : currentZoom)")
            YandexMapView!.mapWindow.map.move(with: YMKCameraPosition(
                target: userPoint!,
                zoom: (currentZoom < 16.0 ? 16.0 : currentZoom), //если зум слишком маленький, то установить на комфортный 16.0
                azimuth: 0,
                tilt: 0)
            )
        }
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
        YandexMapView!.mapWindow.map.deselectGeoObject()
        YandexMapView!.mapWindow.map.mapObjects.clear()

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
            YandexMapView!.mapWindow.map.selectGeoObject(withObjectId: selectionMetadata.id, layerId: selectionMetadata.layerId)
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
        YandexMapView!.mapWindow.map.deselectGeoObject()
        let mapObjects = YandexMapView!.mapWindow.map.mapObjects
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
    
    
    // MARK: - Методы для построения маршрута
    
    //Построение маршрута
    func makeTheRoute(from pointA: YMKPoint, to pointB: YMKPoint) {
        
        if (mapType == .Yandex) {
            // очищаем карту от точек и выделений
            YandexMapView!.mapWindow.map.deselectGeoObject()
            let mapObjects = YandexMapView!.mapWindow.map.mapObjects
            mapObjects.clear()
            
            // перемещаем камеру на точку А
            YandexMapView!.mapWindow.map.move(
                with: YMKCameraPosition(target: pointA, zoom: currentZoom, azimuth: 0, tilt: 0),
                animationType: YMKAnimation(type: YMKAnimationType.smooth, duration: 5),
                cameraCallback: nil
            )
            
            //ставим маркеры на точки А и Б
            let placemarkA = mapObjects.addPlacemark(with: pointA)
            placemarkA.setIconWith(UIImage(named: "SearchResult")!)
            let placemarkB = mapObjects.addPlacemark(with: pointB)
            placemarkB.setIconWith(UIImage(named: "SearchResult")!)
        }
        
        if (mapType == .Google) {
            // перемещаем камеру на точку А
            let camera = GMSCameraPosition(latitude: pointA.latitude, longitude: pointA.longitude, zoom: currentZoom)
            GoogleMapView?.animate(to: camera)
            
            // Создаем маркеры для точек А и Б
            let markerA = GMSMarker()
            markerA.position = CLLocationCoordinate2D(latitude: pointA.latitude, longitude: pointA.longitude)
            markerA.title = pointAName
            let markerB = GMSMarker()
            markerB.position = CLLocationCoordinate2D(latitude: pointB.latitude, longitude: pointB.longitude)
            markerB.title = pointBName
            // добавляем маркеры на карту
            markerA.map = GoogleMapView; markerB.map = GoogleMapView
            
        }
       
        
        //проверяем, есть ли уже этот маршрут в базе данных
        let route = checkRoute(from: pointA, to: pointB)
        
        if (saveOrDeleteMode == .Save) { //маршрута нет в БД, строим и сохраняем
            
            if (Reachability.isConnectedToNetwork()) { //если есть интернет, то строим по интернету
                //очищаем массив точек перед заполнением
                arrayOfPoints.removeAll()
                arrayOfUserPoints.removeAll()
                if (mapType == .Google) { // строим маршрут по картам Google
                    print("строим маршрут по интернету для гугла")
                    makeTheGoogleRoute(from: pointA, to: pointB)
                }
                else { // строим маршрут по картам Яндекс
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
            }
            else {
                print("нет интернета, нельзя построить маршрут")
                alertSituation = AlertSituation.Offline
                viewDidAppear(true)
                drivingSessionForPedestrian = nil
                drivingSession = nil
            }
        }
        else { //маршрут есть в БД, строим по данным БД
            print("маршрут есть в БД, строим по данным БД")
            if (route != nil) { showRouteFromDB(route: route!) }
        }
    }
    //Если маршрут есть в БД, то строим по данным из нее
    func showRouteFromDB(route: Route) {

        // MARK: - test
        let arrayOfPointsForRoute : [GeoPoint] = Array(route.routeArray)
        let arrayOfUserPointsForRoute : [GeoPointToSend] = Array(route.routeUserArray)
        let countOfPoints = arrayOfPointsForRoute.count
        let countOfUserPoints = arrayOfUserPointsForRoute.count
        print("в массиве БД есть маршрут с \(countOfPoints) точками (в том числе \(countOfUserPoints) пользовательских), строим маршрут")
        
        if (mapType == .Google) {
            print("строим ИЗ БД для гугла")
            let path = GMSPath.init(fromEncodedPath: route.geometryOfRoute!)
            let polyline = GMSPolyline.init(path: path)
            polyline.strokeColor = UIColor.blue
            polyline.strokeWidth = 2
            polyline.map = self.GoogleMapView
            
            for point in arrayOfUserPointsForRoute {
                let points = point.location.split(separator: ";")
                let firstPoint = Double(points[0])
                let secondPoint = Double(points[1])
                let placemark = GMSMarker()
                placemark.position = CLLocationCoordinate2D(latitude: firstPoint!, longitude: secondPoint!)
                placemark.map = GoogleMapView;
            }
            
        }
        else {
            let mapObjects = YandexMapView!.mapWindow.map.mapObjects
            var polylineArray : [YMKPoint] = [] // маршрут точек для отображения пользователю
            for point in arrayOfPointsForRoute {
                polylineArray.append(YMKPoint(latitude: point.geoPointLatitude, longitude: point.geoPointLongitude))
            }
            let newPolyline = YMKPolyline(points: polylineArray)
            polyline = mapObjects.addPolyline(with: newPolyline)
            
            //ставим маркеры на пользовательские точки маршрута
            for point in arrayOfUserPointsForRoute {
                let points = point.location.split(separator: ";")
                let firstPoint = Double(points[0])
                let secondPoint = Double(points[1])
                let marker = YMKPoint(latitude: firstPoint!, longitude: secondPoint!)
                let placemark = mapObjects.addPlacemark(with: marker)
                placemark.setIconWith(UIImage(named: "SearchResult")!)
            }
            
            if (polyline != nil) { polyline!.addTapListener(with: self) }
        }

        let userPoint = GeoPointToSend(address: pointBAddress, location: "\(route.pointB!.geoPointLatitude);\(route.pointB!.geoPointLongitude)")
        
        arrayOfUserPoints.append(userPoint)
        if StorageManager.getUserPoint(userPoint) == nil {
            print("nil")
            StorageManager.saveUserPoint(userPoint)
        }
        
        arrayOfPoints = Array(route.routeArray)
        arrayOfUserPoints = Array(route.routeUserArray)

        alertSituation = AlertSituation.routingFromDB
        viewDidAppear(true)
        
    }
    
    //построение маршрута через сервис Google
    func makeTheGoogleRoute(from: YMKPoint, to: YMKPoint) {
        //сохраняем точку А
        arrayOfPoints.append(GeoPoint(geoPointLatitude: pointA.latitude, geoPointLongitude: pointA.longitude, address: pointAAddress, location: "\(pointA.latitude);\(pointA.longitude)"))
        arrayOfUserPoints.append(GeoPointToSend(address: pointAAddress, location: "\(pointA.latitude);\(pointA.longitude)"))
        
        let origin = "\(pointA.latitude),\(pointA.longitude)"
        let destination = "\(pointB.latitude),\(pointB.longitude)"
        let url = "https://maps.googleapis.com/maps/api/directions/json?origin=\(origin)&destination=\(destination)&key=\(GOOGLE_API_KEY)&mode=walking"
        AF.request(url).responseJSON { response in
            do {
                let json = try JSON(data: response.data!)
                let routes = json["routes"].arrayValue
                for route in routes
                {
                    //сохранение узловых точек маршрута
                    let legs = route["legs"].arrayValue
                    let steps = legs[0]["steps"].arrayValue
                    print("всего будет \(steps.count) пользовательских точек")
                    
                    for step in steps {
                        
                        var html_instructions = ""
                        html_instructions = step["html_instructions"].stringValue
                        print("html_instructions: \(html_instructions)")
                        var formattedsrt : String = ""
                        var outputstr : String = ""
                        var arr : [String] = []
                        //переводим изначальную строку в массив
                        for char in html_instructions { arr.append(String(char)) }
                        //ставим точку в этой строке на месте <div>
                        for (i,char) in arr.enumerated() {
                            if (char == "<") { if (arr[i+1] == "d") { if (arr[i+2] == "i") { if (arr[i+3] == "v") {
                                print("div найден"); arr[i] = String(". <")
                            } } } }
                        }
                        //записываем результат в новую строку
                        for item in arr { formattedsrt = formattedsrt + String(item) }
                        //переводим отформатированную строку в массив
                        var formattedArray : [String] = []
                        for char in formattedsrt { formattedArray.append(String(char)) }
                        //записываем результат в строку без элементов HTML
                        var shouldIAddThis = 1
                        for item in formattedArray {
                            if (item == "<") { shouldIAddThis = 0 }
                            if (shouldIAddThis == 1) { outputstr = outputstr + String(item) }
                            if (item == ">") { shouldIAddThis = 1 }
                        }
                        //получаем итоговую строку
                        html_instructions = outputstr
                    
                        let point = step["start_location"].dictionary
                        let pointLat = point?["lat"]?.doubleValue
                        let pointLong = point?["lng"]?.doubleValue
                        print("point: \(pointLat!),\(pointLong!)")
                        // сохраняем пользовательские точки
                        let userPoint = GeoPointToSend(address: "\(html_instructions)", location: "\(pointLat!);\(pointLong!)")
                        self.arrayOfUserPoints.append(userPoint)
                        if StorageManager.getUserPoint(userPoint) == nil { StorageManager.saveUserPoint(userPoint) }
                    }
                    
                    //отрисовка маршрута
                    let routeOverviewPolyline = route["overview_polyline"].dictionary
                    let points = routeOverviewPolyline?["points"]?.stringValue
                    let code = #"\#(points!)"#
                    print(#"\#(code)"#)
                    self.geometryOfRoute = code //сохраняем геометрию маршрута
                    let path = GMSPath.init(fromEncodedPath: code)
                    let polyline = GMSPolyline.init(path: path)
                    polyline.strokeColor = UIColor.blue
                    polyline.strokeWidth = 2
                    polyline.map = self.GoogleMapView
                    
                    //ставим на карту узловые точки
                    for point in self.arrayOfUserPoints {
                        let points = point.location.split(separator: ";")
                        let firstPoint = Double(points[0])
                        let secondPoint = Double(points[1])
                        let placemark = GMSMarker()
                        placemark.position = CLLocationCoordinate2D(latitude: firstPoint!, longitude: secondPoint!)
                        placemark.map = self.GoogleMapView;
                    }
                    
                }
            }
            catch { print(error) }
        }
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
            typeOfMap: mapType.rawValue,
            geometryOfRoute: ""
        )
        
        let routeFromDB = StorageManager.getRoute(newRoute)
        if (routeFromDB != nil) {
            print("такой маршрут уже есть (в нем \(routeFromDB!.routeArray.count) точек)")
            userNameForRoute = routeFromDB?.userNameForRoute
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
        print("до нажатия на маршрут было \(arrayOfUserPoints.count) пользовательских точек")
        if (saveOrDeleteMode == .Delete) {
            //если маршрут уже сохранен, то удалить последнюю точку массива (точку Б), чтобы не было дублирования
            arrayOfUserPoints.removeLast()
        }
        saveOrDeleteMode = .Save
        
        routeButton.title = "Сохранить маршрут"
        let mapObjects = YandexMapView!.mapWindow.map.mapObjects
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
            
            let alertController = UIAlertController(title: "Точка добавлена в маршрут", message: "Нет подключения к интернету", preferredStyle: .alert)
            let cancelAction = UIAlertAction(title: "Ок", style: .default, handler: { (action : UIAlertAction!) -> Void in })
            alertController.addAction(cancelAction)
            self.present(alertController, animated: true, completion: nil)
        }
        
        let userPoint = GeoPointToSend(address: addressPlace!, location: "\(point.latitude);\(point.longitude)")
        arrayOfUserPoints.append(userPoint)
        print("после нажатия на маршрут стало \(arrayOfUserPoints.count) пользовательских точек")
        if StorageManager.getUserPoint(userPoint) == nil { StorageManager.saveUserPoint(userPoint) }
        
        return true
    }
    // MARK: - Обработка пешеходного маршрута
    func onRoutesForPedestrianReceived(_ routes: [YMKMasstransitRoute]) {
        let mapObjects = YandexMapView!.mapWindow.map.mapObjects
        // выбираем первый маршрут (самый оптимальный), выбор маршрутов не стал реализовывать
        // вариант взаимодействия с несколькими: на каждый маршрут (polyline) повесить слушателя и определять, на какой из них нажали
        
        if (routes.isEmpty) {
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
            arrayOfPoints.append(pointA_)
            arrayOfUserPoints.append(GeoPointToSend(address: pointAAddress, location: "\(pointA.latitude);\(pointA.longitude)"))
            for i in 1..<countOfPoints - 1 {
                let latitude = route.geometry.points[i].latitude
                let longitude = route.geometry.points[i].longitude
                let geoPoint = GeoPoint(geoPointLatitude: latitude, geoPointLongitude: longitude, address: "", location: "")
                if (StorageManager.getPoint(geoPoint) == nil) { StorageManager.savePoint(geoPoint) }
                arrayOfPoints.append(geoPoint)
            }
            
            let pointB_ = GeoPoint(geoPointLatitude: pointB.latitude, geoPointLongitude: pointB.longitude, address: pointBAddress, location: "\(pointB.latitude);\(pointB.longitude)")
            arrayOfPoints.append(pointB_)
                    
            print("Точка А: \(pointA.latitude), \(pointA.longitude)")
            print("Точка Б: \(pointB.latitude), \(pointB.longitude)")
            
            polyline = mapObjects.addPolyline(with: route.geometry)
            if (polyline != nil) { polyline!.addTapListener(with: self) }
            
            let alertController = UIAlertController(title: "Нажмите кнопку \n'Сохранить маршрут' \nили выберите конкретные точки маршрута для сохранения", message: nil, preferredStyle: .alert)
            let cancelAction = UIAlertAction(title: "Ок", style: .default, handler: { (action : UIAlertAction!) -> Void in })
            alertController.addAction(cancelAction)
            self.present(alertController, animated: true, completion: nil)
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
        
    // Сохраняем маршрут в БД
    func saveTheRoute() {
        if let oldRoute = checkRoute(from: self.pointA, to: self.pointB) {
            print("такой маршрут есть, обновляем его")
//            arrayOfUserPoints = Array(oldRoute.routeUserArray)
            arrayOfPoints = Array(oldRoute.routeArray)
            StorageManager.deleteRoute(oldRoute)
        } else {
            print("таких маршрутов нет, сохранем впервые")
        }
        
        print("сохраняем маршрут...")
        let pointA = GeoPoint(geoPointLatitude: pointA.latitude, geoPointLongitude: pointA.longitude, address: pointAAddress, location: "\(pointA.latitude);\(pointA.longitude)")
        let pointB = GeoPoint(geoPointLatitude: pointB.latitude, geoPointLongitude: pointB.longitude, address: pointBAddress, location: "\(pointB.latitude);\(pointB.longitude)")
        
        //сохраняем в конце массива точку Б
        let userPoint = GeoPointToSend(address: pointBAddress, location: "\(pointB.geoPointLatitude);\(pointB.geoPointLongitude)")
        
        var checkPointB = 0
        for point in arrayOfUserPoints {
            if (point.location == userPoint.location) { checkPointB = 1 }
        }
        
        // если точка Б не нашлась в массиве, то добавляем ее в конец
        if (checkPointB == 0) { arrayOfUserPoints.append(userPoint) }
        
//        if !arrayOfUserPoints.contains(userPoint) {
//             arrayOfUserPoints.append(userPoint)
//        }
        
        if StorageManager.getUserPoint(userPoint) == nil { StorageManager.saveUserPoint(userPoint) }
        
        let route = Route(
            userNameForRoute: userNameForRoute!,
            addressOfPointA: pointAAddress,
            addressOfPointB: pointBAddress,
            pointA: StorageManager.getPoint(pointA) ?? pointA,
            pointB: StorageManager.getPoint(pointB) ?? pointB,
            typeOfMap: mapType.rawValue,
            geometryOfRoute: geometryOfRoute
        )
                
        try! realm.write { route.routeArray.append(objectsIn: arrayOfPoints) }
        try! realm.write { route.routeUserArray.append(objectsIn: arrayOfUserPoints) }
        
        showJSON()
        StorageManager.saveRoute(route)
        routeButton.title = "Удалить маршрут"
        saveOrDeleteMode = .Delete
    }
    // Удаляем маршрут из БД
    func deleteTheRoute() {
        print("удаляем маршрут...")
        let route = checkRoute(from: pointA, to: pointB)
        StorageManager.deleteRoute(route!)
        if (mapType == .Yandex) {
            let mapObjects = YandexMapView!.mapWindow.map.mapObjects
            mapObjects.clear()
        }
        routeButton.title = "Построить маршрут"
        mapMode = .Searching
    }
    
    //Кнопка "Сохранить/Удалить маршрут"
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
            if (mapType == .Yandex) { userLocationLayer?.resetAnchor() }
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
        
        guard let sourceVC = segue.source as? TableForRouteViewController else { return }
        if (segue.identifier == "makeTheRoute") {
            alertSituation = .askForMapType //вызываем alertcontroller с вопросом, через какой сервис строить маршрут
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
            
            // MARK: - ?? нужно ли делать то же самое с arrayOfPoints?
            arrayOfUserPoints.removeAll() //очищаем массив пользовательских точек перед добавлением
            let userPoint = GeoPointToSend(address: pointAAddress, location: "\(pointA.latitude);\(pointA.longitude)")
            arrayOfUserPoints.append(userPoint) //добавляем в массив точек точку А
            if StorageManager.getUserPoint(userPoint) == nil { StorageManager.saveUserPoint(userPoint) }
        }
        if (segue.identifier == "backToSearch") {
            alertSituation = .Default 
            mapMode = MapMode.Searching
        }
        print("очищаем все после выхода")
        sourceVC.tableView = nil
    }
    
}


// расширение для сохранения json файла и его отправки
extension MainViewController {
    // MARK: - После построения маршрута предлагаем пользователю использовать JSON файл с маршрутом
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
        formatter.timeZone = TimeZone.current // указатель временной зоны относительно гринвича - TimeZone(secondsFromGMT: 0)
        let formatteddate = formatter.string(from: time as Date)
        let dateString = "\(formatteddate)"

        var info :  [String : AnyObject] = [:] //во что преобразуем
        let routeToSend = RouteToSend(
            NameRoute: userNameForRoute!,
            Point_A: pointAAddress,
            Point_B: pointBAddress
        )
        try! realm.write { routeToSend.ArrData.append(objectsIn: arrayOfUserPoints) }
        // !!! MARK: - ArrData: arrayOfUserPoints
        var dicArray = Dictionary<String,AnyObject>()
        dicArray = routeToSend.toDictionary()
        info = dicArray
        
        //сохраняем объект routeToSend в виде JSON
        let documentsUrl =  FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.path
        let pathToFile = "\(documentsUrl)/Route (\(dateString)) - \(mapType.rawValue).json"
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
}

// MARK: - Обработка автомобильного маршрута (не использую)
extension MainViewController {
    func onRoutesReceived(_ routes: [YMKDrivingRoute]) {
        let mapObjects = YandexMapView!.mapWindow.map.mapObjects
        
        enum RoutingType : Int {
            case single = 0
            case multi = 1
        }
        let routingType : RoutingType = .single
        
        var cordsToFile : String = ""
        if (routingType == .single) {
            // MARK: - один маршрут
            let route = routes[0]
            let countOfPoints = route.geometry.points.count
            print("\nСамый оптимальный маршрут c числом точек: \(countOfPoints)")
            
            for i in 0..<countOfPoints {
                let latitude = route.geometry.points[i].latitude
                let longitude = route.geometry.points[i].longitude
                cordsToFile = cordsToFile + "\(latitude);\(longitude) \n"
            }
            mapObjects.addPolyline(with: route.geometry)
        }
        else {
            // MARK: - несколько маршрутов
            for (index,route) in routes.enumerated() {
                print("Маршрут №\(index + 1)")
                let countOfPoints = route.geometry.points.count
                print("\nВ вашем маршруте \(countOfPoints) точек")
                for i in 0..<countOfPoints {
                    let latitude = route.geometry.points[i].latitude
                    let longitude = route.geometry.points[i].longitude
                    cordsToFile = cordsToFile + "\(latitude);\(longitude) \n"
                }
                let polyline = mapObjects.addPolyline(with: route.geometry)
                if (index == 0) { polyline.strokeColor = .blue }
                else { polyline.strokeColor = .gray }
            }
        }
    }
}

// MARK: - Поиск по карте (Яндекс)
extension MainViewController {
    
    //первый поисковый запрос при запуске View
    func makeFirstSearchRequest(searchRequest: String?) {
        let responseHandler = {(searchResponse: YMKSearchResponse?, error: Error?) -> Void in
            if let response = searchResponse { self.onSearchResponse(response) }
            else { self.onSearchError(error!) }
        }
        searchSession = searchManager!.submit(
            withText: searchRequest!, //что ищем
            geometry: YMKVisibleRegionUtils.toPolygon(with: YandexMapView!.mapWindow.map.visibleRegion),
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
            let message : String? = namePlace + " \n" + (addressPlace!)
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
        }
        else {
            let mapObjects = YandexMapView!.mapWindow.map.mapObjects
            mapObjects.clear()
            //добавляем маркеры на найденные объекты
            for searchResult in response.collection.children {
                if let point = searchResult.obj?.geometry.first?.point {
                    let placemark = mapObjects.addPlacemark(with: point)
                    placemark.setIconWith(UIImage(named: "SearchResult")!)
                    searchPoint = point
                    if (!isMultipleSearching && !wasCameraMovedToPoint) {
                        YandexMapView!.mapWindow.map.move(with: YMKCameraPosition(
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
}
