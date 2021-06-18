//
//  NetworkManager.swift
//  YandexMapsApp
//
//  Created by Александр Васильевич on 23/05/2021.
//  Copyright © 2021 Александр Васильевич. All rights reserved.
//

import Foundation
import CoreLocation

protocol NetworkManagerDelegate : AnyObject {
    func loadInfo(_: NetworkManager, with geoPosition: GeoPosition)
    func loadBoundings(_: NetworkManager, with geoCityForSearch: GeoPosition)
}

class NetworkManager {

    let urlAddress = "https://geocode-maps.yandex.ru/1.x/?apikey=\(GEOCODER_API_KEY)&format=json"
//    let urlAddressOrg = "https://search-maps.yandex.ru/v1/?apikey=\()&text=text=55.750788,37.618534&lang=ru_RU"
    
    weak var delegate : NetworkManagerDelegate?
    
    func getGeoposition(lat: CLLocationDegrees, long: CLLocationDegrees) {
        let urlString = urlAddress + "&sco=latlong&geocode=\(lat),\(long)"
        guard let url = URL(string: urlString) else { return}
        let session = URLSession(configuration: .default)
        
        let task = session.dataTask(with: url) { data, response, error in
            if let data = data {
                if let geoPosition = self.parseJSON(withData: data) {
                    self.delegate?.loadInfo(self, with: geoPosition)
                }
            }
        }
        task.resume()
    }
    
    // MARK: - Получаем границы региона для поиска
    func getBoundings(cityPath: String) {
        if let cityPath = cityPath.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {
            let urlString = urlAddress + "&geocode=\(cityPath)"
            guard let url = URL(string: urlString) else { print("ошибка"); return}
            let session = URLSession(configuration: .default)
            let task = session.dataTask(with: url) { data, response, error in
                if let data = data {
                    if let geoCityForSearch = self.parseJSON(withData: data) {
                        self.delegate?.loadBoundings(self, with: geoCityForSearch)
                    } else { print("ошибка") }
                } else { print("ошибка") }
            }
            task.resume()
        } else { print("ошибка") }
    }
    
    // MARK: - Парсим JSON (раскладываем полученные данные по модели)
    func parseJSON(withData data: Data) -> GeoPosition? {
        let decoder = JSONDecoder()
        do {
            let geoPositionData = try decoder.decode(GeoPositionData.self, from: data)
            guard let geoPosition = GeoPosition(geoPositionData: geoPositionData) else {
                return nil
            }
            return geoPosition
        } catch let error as NSError {
            print("\(error.localizedDescription), fullNameOfError: \(error)")
        }
        return nil
    }
}
