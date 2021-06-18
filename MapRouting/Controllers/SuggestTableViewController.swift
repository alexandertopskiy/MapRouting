import UIKit
import YandexMapsMobile
import CoreLocation

class SuggestCell: UITableViewCell {
    @IBOutlet weak var itemName: UILabel!
    @IBOutlet weak var adressLabel: UILabel!
    var isFromDB : Bool = false
}

class SuggestViewController: UIViewController, UITableViewDataSource {
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var searchBar: UITextField!
            
    var suggestResults: [YMKSuggestItem] = []
    let searchManager = YMKSearch.sharedInstance().createSearchManager(with: .combined)
    var suggestSession: YMKSearchSuggestSession!
    
    var addressOfUser : String = ""
    var userPoint = YMKPoint()
    var isQueryEmpty : Bool = true
    
    
    var geoAllowState = GeoAllowState.no //разрешен ли доступ к геопозиции (если нет, то кнопка "Моя геопозиция" не будет работать)
    var networkManager = NetworkManager()
    
    //lazy потому что пользователь может не разрешить доступ к геопозиции, тогда незачем держать в памяти менеджера
    lazy var locationManager: CLLocationManager = {
        let lm = CLLocationManager()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyKilometer //точность, с которой будем определять геопозицию
        lm.requestWhenInUseAuthorization() //запрашиваем у пользователя геопозицию
        
        return lm
    }()
    
    //область ограничения (по умолчанию - советск)
    var BOUNDING_BOX = YMKBoundingBox(
        southWest: YMKPoint(latitude: 57.566602, longitude: 48.927883), //57.566602, 48.927883
        northEast: YMKPoint(latitude: 57.612412, longitude: 48.956341)) //57.612412, 48.956341
    
    override func viewDidLoad() {
        super.viewDidLoad()
        

        if Reachability.isConnectedToNetwork(){
            print("Internet Connection Available!")
            suggestSession = searchManager.createSuggestSession()
        }else{
            print("Internet Connection not Available!")
        }
        tableView.tableFooterView = UIView(frame: CGRect(x: 0, y: 0,
                                                         width: tableView.frame.size.width, height: 1))
        networkManager.delegate = self
        if CLLocationManager.locationServicesEnabled() { //если пользователь разрешил определение геопозиции
            geoAllowState = .yes
            locationManager.requestLocation()
        } else {
            geoAllowState = .no
        }
        
        tableView.dataSource = self
    }
    
    
    @IBAction func clearDBButtonPressed(_ sender: UIBarButtonItem) {
        StorageManager.clearDB()
        tableView.reloadData()
    }
    
    func onSuggestResponse(_ items: [YMKSuggestItem]) {
        suggestResults = items
        tableView.reloadData()
    }

    func onSuggestError(_ error: Error) {
        let suggestError = (error as NSError).userInfo[YRTUnderlyingErrorKey] as! YRTError
        var errorMessage = "Unknown error"
        if suggestError.isKind(of: YRTNetworkError.self) {
            errorMessage = "Network error"
        } else if suggestError.isKind(of: YRTRemoteError.self) {
            errorMessage = "Remote server error"
        }
        
        let alert = UIAlertController(title: "Error", message: errorMessage, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        
        present(alert, animated: true, completion: nil)
    }
    
    // MARK: - добавить поиск в офлайне?
    @IBAction func queryChanged(_ sender: UITextField) {
        //если поле поиска пустое, то показать только из БД
        if (sender.text?.isEmpty == true) {
            isQueryEmpty = true
            tableView.reloadData()
        }
        else {
            isQueryEmpty = false
            if Reachability.isConnectedToNetwork(){
                print("Internet Connection Available!")
                let suggestHandler = {(response: [YMKSuggestItem]?, error: Error?) -> Void in
                    if let items = response {
                        self.onSuggestResponse(items)
                    } else {
                        self.onSuggestError(error!)
                    }
                }

                suggestSession.suggest(
                    withText: sender.text!,
                    window: BOUNDING_BOX,
                    suggestOptions: YMKSuggestOptions(),
                    responseHandler: suggestHandler)
            }
            // только оффлайн
            else {
                
            }
        }
    }
    
    // MARK: - Segue
    
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        if (identifier == "searchPlaceOnMap") {
            guard let indexPath = tableView.indexPathForSelectedRow else { return false }
            let cell = tableView.cellForRow(at: indexPath) as! SuggestCell
  
            if CLLocationManager.locationServicesEnabled() { //если пользователь разрешил определение геопозиции
                geoAllowState = .yes
                locationManager.requestLocation()
            } else {
                geoAllowState = .no
            }
            
            if (geoAllowState == .no && indexPath.row == 0) {
                print("\nИщем мое местоположение, но доступа нет")
                print("отключаем сегвей к searchPlaceOnMap")
                
                let alertController = UIAlertController(title: "Нет доступа к вашей геопозиции!", message: "Измените доступ в настройках!", preferredStyle: .alert)
                let cancelAction = UIAlertAction(title: "Ок", style: .default, handler: { alert -> Void in })
                alertController.addAction(cancelAction)
                self.present(alertController, animated: true, completion: nil)
                cell.isSelected = false //убираем выделение с ячейки

                return false
            }
        }
        return true
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "searchPlaceOnMap" {
            
            var namePlace = "МОЕ МЕСТОПОЛОЖЕНИЕ"
            var addressPlace : String? = addressOfUser
            //определяем, какая ячейка выделена
            guard let indexPath = tableView.indexPathForSelectedRow else { return }
            let cell = tableView.cellForRow(at: indexPath) as! SuggestCell
            let nav = segue.destination as! UINavigationController
            let svc = nav.topViewController as! MainViewController
            if (cell.isFromDB) {
                print("выделена ячейка из БД")
                let x = realm.objects(Place.self)[indexPath.row-1]
                namePlace = x.geoName
                addressPlace = x.address
                svc.isSearchingFromDB = true
                svc.searchPoint = YMKPoint(latitude: x.geoPoint!.geoPointLatitude, longitude: x.geoPoint!.geoPointLongitude)
                svc.isUserPointSearching = false
            }
            else {
                print("выделена ячейка из запроса")
                svc.isSearchingFromDB = false
                if (indexPath.row == 0) {
                    print("\nИщем мое местоположение")
                    svc.searchPoint = userPoint
                    svc.isUserPointSearching = true
                }
                else {
                    print("\nИщем адрес")
                    let x = suggestResults[indexPath.row-1]
                    namePlace = x.displayText!
                    addressPlace = x.subtitle?.text
                    if addressPlace != nil {
                        let result: [String] =  addressPlace!.components(separatedBy: " · ")
                        // проверка result: если это множество "организаций", то поиск по названию
                        if result.count > 1 {
                            //пятерочка - "супермаркет . 123 организаций"  -> поиск по названию
                            //пятерочка - "супермаркет . адрес" -> поиск по адресу
                            addressPlace = namePlace + " " + result[1] //адрес для поиска
                            svc.addressForSegue = result[1]
                            let x = result[1].split(separator: " ")
                            if (x.contains("организация") || x.contains("организаций") || x.contains("организации")) {
                                addressPlace = namePlace
                                svc.isMultipleSearching = true
                                print("это организация, ищем по названию")
                            }
                        }
                        else {
                            // аптека - "321 организация"   -> поиск по названию
                            addressPlace = namePlace
                        }
                    }
                    svc.isUserPointSearching = false
                }
            }
            svc.userPoint = userPoint
            svc.namePlace = namePlace
            svc.addressPlace = addressPlace
            svc.mapMode = MapMode.Searching
            svc.geoAllowState = geoAllowState
        }
    }
    
    @IBAction func unwindSegue(_ segue: UIStoryboardSegue) {
        guard let sourceVC = segue.source as? MainViewController else { return }
        sourceVC.cancelAction()
        tableView.reloadData()
    }
    
    // MARK: - конфигурация таблицы
    
    //  Обязательный метод: конфикурация ячейки. Идентификатор для ячейки присваивается в storyboard. В нашем случае это suggestCell
    func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "suggestCell", for: path) as! SuggestCell
        if (Reachability.isConnectedToNetwork() && !isQueryEmpty){
            if (path.row == 0 ) {
                cell.itemName.text = "МОЕ МЕСТОПОЛОЖЕНИЕ"
                cell.adressLabel.text = addressOfUser
            } else {
                cell.itemName.text = suggestResults[path.row-1].displayText
                cell.adressLabel.text = suggestResults[path.row-1].subtitle?.text
                cell.isFromDB = false
            }
        }
        //оффлайн или запрос пустой
        else {
            if (path.row == 0 ) {
                cell.itemName.text = "МОЕ МЕСТОПОЛОЖЕНИЕ"
                cell.adressLabel.text = addressOfUser
            } else {
                cell.itemName.text = "[Сохранено]" + realm.objects(Place.self)[path.row-1].userName
                cell.adressLabel.text = realm.objects(Place.self)[path.row-1].address
                cell.isFromDB = true
            }
        }
        return cell
    }

    // количество секциий
    func numberOfSections(in tableView: UITableView) -> Int { return 1 }

    // количество строк в секции
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        var countOfRows = 0
        //если есть интернет и запрос не пустой
        if (Reachability.isConnectedToNetwork() && !isQueryEmpty){
            print("Internet Connection Available!")
            countOfRows = suggestResults.count + 1
            print("в таблице будет \(countOfRows) строк")
        }
        else{
            print("Internet Connection not Available! or querry is empty")
            countOfRows = realm.objects(Place.self).count + 1
            print("в таблице будет \(countOfRows) строк")
        }
        return countOfRows
    }
}

// MARK: - Местоположение пользователя (CoreLocation)
extension SuggestViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return } //последний элемент массива locations - это текущая геопозиция
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        var userLocation : [CLLocationDegrees] = [0,0]//позиция пользователя (широта, долгота)
        userLocation[0] = latitude
        userLocation[1] = longitude
        print("Вы находитесь здесь: \(latitude), \(longitude)")
        userPoint = YMKPoint(latitude: latitude, longitude: longitude)
        networkManager.getGeoposition(lat: latitude, long: longitude)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("\n")
        print(error.localizedDescription)
        geoAllowState = .no
        print("\n")
        print("ОШИБКА в locationManager of SuggestViewController: \(error)")
    }
}

// MARK: - Получение адреса и повторный вызов геокодера для определения границ поиска (Геокодер API)
extension SuggestViewController: NetworkManagerDelegate {
    func loadInfo(_: NetworkManager, with geoPosition: GeoPosition) {
        print("Адрес: \(geoPosition.text)")
        addressOfUser = geoPosition.text
        let componentsArray = geoPosition.address.components
        var cityPath : [String] = []
        for item in componentsArray {
            cityPath.append(item.name)
            if (item.kind == "locality") {
                print("Ваш город: \(item.name)")
                break
            }
        }
        let cityPathString = cityPath.joined(separator: ",")
        print("Полный путь города: \(cityPathString)")
        networkManager.getBoundings(cityPath: cityPathString)
    }

    func loadBoundings(_: NetworkManager, with geoCityForSearch: GeoPosition) {
        let lowerCorner = geoCityForSearch.boundedBy.envelope.lowerCorner
        //southWest: YMKPoint(latitude: 57.566602, longitude: 48.927883), //57.566602, 48.927883
        let upperCorner = geoCityForSearch.boundedBy.envelope.upperCorner
        print("Границы: Нижняя = \(lowerCorner), Верхняя = \(upperCorner)")

        var lowerCornerCoords : [Double] = []
        var upperCornerCoords : [Double] = []

        for item in lowerCorner.components(separatedBy: " ") {
            lowerCornerCoords.append(Double(item)!)
        }

        for item in upperCorner.components(separatedBy: " ") {
            upperCornerCoords.append(Double(item)!)
        }
        //область ограничения
        BOUNDING_BOX = YMKBoundingBox(
            southWest: YMKPoint(latitude: lowerCornerCoords[1], longitude: lowerCornerCoords[0]),
            northEast: YMKPoint(latitude: upperCornerCoords[1], longitude: upperCornerCoords[0])
        )
    }

}
