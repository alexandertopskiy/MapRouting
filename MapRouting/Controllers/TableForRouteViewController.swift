import Foundation
import UIKit
import YandexMapsMobile

class PlaceForRouteCell: UITableViewCell, UIPickerViewDelegate, UIPickerViewDataSource {
    
    @IBOutlet weak var picker: UIPickerView!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        self.picker.delegate = self
        self.picker.dataSource = self
    }
    
    // Выбираем все места в базе данных
    let places = realm.objects(Place.self)
    var selectedPlace = Place()
    
    //число "барабанов"
    func numberOfComponents(in pickerView: UIPickerView) -> Int { return 1 }
    
    //число элементов в "барабане"
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        //если БД пуста, то предупредить об этом
        return places.count != 0 ? places.count : 1
    }
    
    //содержимое "барабанов"
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        if (places.count != 0) {
            if (places.count == 1) { return "Добавьте еще одно место" }
            selectedPlace = places[row]
            return places[row].userName
        }
        return "Сохраненных мест нет"
    }
    
    //обрабатываем выбранный элемент
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        NotificationCenter.default.post(name: Notification.Name("Notification"), object: nil)
        if (places.count != 0) { selectedPlace = places[row] }
    }
        
    
}


class TableForRouteViewController: UIViewController, UITableViewDataSource, UIPickerViewDelegate{
    
    // Выбираем все места в базе данных
    let places = realm.objects(Place.self)
    
    @IBOutlet weak var makeTheRouteButton: UIBarButtonItem!
    @IBOutlet var tableView: UITableView!
            
    var pointA = Place()
    var pointB = Place()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.tableFooterView = UIView(frame: CGRect(x: 0, y: 0,
                                                         width: tableView.frame.size.width, height: 1))
        tableView.dataSource = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(methodOfReceivedNotification(notification:)), name: Notification.Name("Notification"), object: nil)
        
        // MARK: - test
        if (places.count > 1) {
            let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 1)) as! PlaceForRouteCell
            cell.picker.selectRow(1, inComponent: 0, animated: true)
            print(cell.picker.selectedRow(inComponent: 0))
        }
        
        if (places.count < 2 ) { makeTheRouteButton.isEnabled = false }
    }
    
    // сравниваем значение точек А и Б маршрута. Если одинаковые, то кнопка построение неактивная
    @objc func methodOfReceivedNotification(notification: Notification) {
        
        var indexPath = IndexPath(row: 0, section: 0)
        var cell = tableView.cellForRow(at: indexPath) as! PlaceForRouteCell
        let selectRow1 = places[cell.picker.selectedRow(inComponent: 0)]
        print("в первой секции выделен объект \(selectRow1.userName)")
        
        indexPath = IndexPath(row: 0, section: 1)
        cell = tableView.cellForRow(at: indexPath) as! PlaceForRouteCell
        let selectRow2 = places[cell.picker.selectedRow(inComponent: 0)]
        print("во второй секции выделен объект \(selectRow2.userName)")
        
        if (selectRow1.userName == selectRow2.userName) { makeTheRouteButton.isEnabled = false }
        else { makeTheRouteButton.isEnabled = true }
        
    }
    
    func makeTheRoute() {
        let cellA = tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as! PlaceForRouteCell
        pointA = cellA.selectedPlace
        let cellB = tableView.cellForRow(at: IndexPath(row: 0, section: 1)) as! PlaceForRouteCell
        pointB = cellB.selectedPlace
        print("point A: \(pointA.userName), point B: \(pointB.userName)")
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return 1 }
        
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "placeForRouteCell", for: indexPath) as! PlaceForRouteCell
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch(section) {
            case 0:return "Точка А"
            case 1:return "Точка Б"
            default :return ""
        }
    }
        
    // количество секциий
    func numberOfSections(in tableView: UITableView) -> Int { return 2 }
    
}
