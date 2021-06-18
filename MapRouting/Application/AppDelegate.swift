//
//  AppDelegate.swift
//  YandexMapsApp
//
//  Created by Александр Васильевич on 08/04/2021.
//  Copyright © 2021 Александр Васильевич. All rights reserved.
//

import UIKit
import YandexMapsMobile
import GoogleMaps

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        YMKMapKit.setApiKey(MAPKIT_API_KEY)
        YMKMapKit.setLocale("ru_Ru")
        GMSServices.provideAPIKey(GOOGLE_API_KEY)
        return true
    }
    
}

