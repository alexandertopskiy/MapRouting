//
//  TappedObjectTableTableViewController.swift
//  YandexMapsApp
//
//  Created by Александр Васильевич on 26.05.2021.
//  Copyright © 2021 Александр Васильевич. All rights reserved.
//

import UIKit
import YandexMapsMobile
import CoreLocation
import RealmSwift

class TappedObjectTableTableViewController: UITableViewController, HalfModalPresentable  {
    
    var tapGestureRecognizer: UITapGestureRecognizer = UITapGestureRecognizer()
    
    var userNamePlace = ""
    var namePlaceFromTap = "namePlace"
    var addressPlaceFromTap: String? = "addressPlace"
    var typePlaceFromTap: String? = "typePlace"
    var infoForPoint = YMKPoint()
    var saveOrDeleteMode = SaveOrDeleteMode.Save
//    var networkManager = NetworkManager()
    
    @IBOutlet weak var namePlace: UITextField!
    @IBOutlet weak var addressPlace: UITextField!
    @IBOutlet weak var typePlace: UITextField!
    
    @IBOutlet weak var saveOrDeleteButton: UIButton!
    
    override func viewDidLoad() {
        print("создаем таблицу")
        super.viewDidLoad()
        checkPlace()
        namePlace.text = namePlaceFromTap
        addressPlace.text = addressPlaceFromTap
        typePlace.text = typePlaceFromTap
        tableView.tableFooterView = UIView(frame: CGRect(x: 0, y: 0,
                                                         width: tableView.frame.size.width, height: 1))
        tableView.reloadData()
    }
    
    func checkPlace() {
        let geoPoint = GeoPoint(geoPointLatitude: infoForPoint.latitude, geoPointLongitude: infoForPoint.longitude, address: namePlaceFromTap, location: "\(infoForPoint.latitude);\(infoForPoint.longitude)")
        let newPlace = Place(
            userName: userNamePlace,
            geoName: namePlaceFromTap,
            address: addressPlaceFromTap,
            type: typePlaceFromTap,
            geoPoint: StorageManager.getPoint(geoPoint) ?? geoPoint
        )
        let isTherePlaceInDB = StorageManager.getPlace(newPlace)
        if (isTherePlaceInDB != nil) {
            print("такое место уже есть, перезаписываем или удаляем")
            saveOrDeleteButton.setTitle("Удалить", for: .normal)
            saveOrDeleteMode = .Delete
        } else {
            print("таких мест нет, сохраняем")
        }
    }
    
    func savePlace() {
        let geoPoint = GeoPoint(geoPointLatitude: infoForPoint.latitude, geoPointLongitude: infoForPoint.longitude, address: namePlaceFromTap, location: "\(infoForPoint.latitude);\(infoForPoint.longitude)")
        let newPlace = Place(
            userName: userNamePlace,
            geoName: namePlaceFromTap,
            address: addressPlaceFromTap,
            type: typePlaceFromTap,
            geoPoint: StorageManager.getPoint(geoPoint) ?? geoPoint
        )
        StorageManager.savePlace(newPlace)
        saveOrDeleteButton.setTitle("Удалить", for: .normal)
        saveOrDeleteMode = .Delete
    }
    
    func deletePlace() {
        let place = Place(
            userName: userNamePlace,
            geoName: namePlaceFromTap,
            address: addressPlaceFromTap,
            type: typePlaceFromTap,
            geoPoint: GeoPoint(geoPointLatitude: infoForPoint.latitude, geoPointLongitude: infoForPoint.longitude, address: namePlaceFromTap, location: "\(infoForPoint.latitude);\(infoForPoint.longitude)")
        )
        StorageManager.deletePlace(place)
        saveOrDeleteButton.setTitle("Сохранить место", for: .normal)
        saveOrDeleteMode = .Save
    }
    
    @IBAction func saveOrDeletePlaceButtonPressed(_ sender: UIButton) {
        if (saveOrDeleteMode == .Save) {
            let alertController = UIAlertController(title: "Как сохранить это место?", message: "", preferredStyle: .alert)
            alertController.addTextField { (textField : UITextField!) -> Void in
                textField.placeholder = self.namePlaceFromTap
                textField.clearButtonMode = .whileEditing
            }
            let saveAction = UIAlertAction(title: "Сохранить", style: .default, handler: { alert -> Void in
                let textField = alertController.textFields![0] as UITextField
                if (textField.text == "") {
                    print("сохраняем по умолчанию как \(self.namePlaceFromTap)")
                    self.userNamePlace = self.namePlaceFromTap
                } else {
                    print("сохраняем с пользовательским именем \(textField.text!)")
                    self.userNamePlace = textField.text!
                }
                self.savePlace()
            })
            
            let cancelAction = UIAlertAction(title: "Отменить", style: .default, handler: { (action : UIAlertAction!) -> Void in })
            alertController.addAction(saveAction)
            alertController.addAction(cancelAction)
            self.present(alertController, animated: true, completion: nil)
        }
        else {
            let alertController = UIAlertController(title: "Вы уверены, что хотите удалить это место?", message: "", preferredStyle: .alert)
            let deleteAction = UIAlertAction(title: "Удалить", style: .default, handler: { alert -> Void in
                print("удаляем место")
                self.deletePlace()
            })
            
            let cancelAction = UIAlertAction(title: "Отменить", style: .default, handler: { (action : UIAlertAction!) -> Void in })
            alertController.addAction(deleteAction)
            alertController.addAction(cancelAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
}


