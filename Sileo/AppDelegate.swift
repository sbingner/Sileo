//
//  AppDelegate.swift
//  Sileo
//
//  Created by CoolStar on 8/29/19.
//  Copyright © 2019 CoolStar. All rights reserved.
//

import Foundation
import UserNotifications
import SDWebImage

class AppDelegate: UIResponder, UIApplicationDelegate, UITabBarControllerDelegate {
    public var window: UIWindow?
    
    func applicationDidFinishLaunching(_ application: UIApplication) {
        DispatchQueue.global(qos: .background).async {
            spawn(command: "/usr/bin/uicache", args: ["uicache", "-p", "/Applications/Cydia.app"])
        }
        
        UserDefaults.standard.register(defaults: [
            "userType": 0
        ])
        
        _ = DownloadManager.shared
        
        // Override point for customization after application launch.
        guard let tabBarController = self.window?.rootViewController as? UITabBarController else {
            fatalError("Invalid Storyboard")
        }
        tabBarController.delegate = self
        tabBarController.tabBar._blurEnabled = true
        tabBarController.tabBar.tag = WHITE_BLUR_TAG
        
        if let cacheClearFile = try? FileManager.default.url(for: .cachesDirectory,
                                                             in: .userDomainMask,
                                                             appropriateFor: nil,
                                                             create: true).appendingPathComponent(".sileoCacheCleared") {
            var cacheNeedsUpdating = false
            if FileManager.default.fileExists(atPath: cacheClearFile.path) {
                let attributes = try? FileManager.default.attributesOfItem(atPath: cacheClearFile.path)
                if let modifiedDate = attributes?[FileAttributeKey.modificationDate] as? Date {
                    if Date().timeIntervalSince(modifiedDate) > 3 * 24 * 3600 {
                        cacheNeedsUpdating = true
                        try? FileManager.default.removeItem(at: cacheClearFile)
                    }
                }
            } else {
                cacheNeedsUpdating = true
            }
        
            if cacheNeedsUpdating {
                SDImageCache.shared().clearDisk(onCompletion: nil)
                try? "".write(to: cacheClearFile, atomically: true, encoding: .utf8)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .seconds(3)) {
            let updatesPrompt = UserDefaults.standard.bool(forKey: "updatesPrompt")
            if !updatesPrompt {
                if UIApplication.shared.backgroundRefreshStatus == .denied {
                    DispatchQueue.main.async {
                        // swiftlint:disable line_length
                        let alertController = UIAlertController(title: String(localizationKey: "Background App Refresh"),
                                                                message: String(localizationKey: "For the best experience, it is recommended to enable background app refresh so you can get a faster experience, as well as notifications for when your tweaks have updates available!"),
                                                                preferredStyle: .alert)
                        // swiftlint:enable line_length
                        alertController.addAction(UIAlertAction(title: String(localizationKey: "OK"), style: .default) { _ in
                            self.window?.rootViewController?.dismiss(animated: true, completion: nil)
                        })
                        alertController.addAction(UIAlertAction(title: String(localizationKey: "Cancel"), style: .cancel) { _ in
                            UserDefaults.standard.set(true, forKey: "updatesPrompt")
                            UserDefaults.standard.synchronize()
                            self.window?.rootViewController?.dismiss(animated: true, completion: nil)
                        })
                        self.window?.rootViewController?.present(alertController, animated: true, completion: nil)
                    }
                }
            }
        }
        
        UIApplication.shared.setMinimumBackgroundFetchInterval(4 * 3600)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {_, _ in
            
        }
        
        _ = NotificationCenter.default.addObserver(forName: UIColor.sileoDarkModeNotification, object: nil, queue: nil) { _ in
            self.updateTintColor()
            for window in UIApplication.shared.windows {
                for view in window.subviews {
                    view.removeFromSuperview()
                    window.addSubview(view)
                }
            }
        }
        UIColor.isDarkModeEnabled = UserDefaults.standard.bool(forKey: "darkMode")
        UIApplication.enableStatusBarFlip = false
        self.updateTintColor()
        UIApplication.enableStatusBarFlip = true
        if UIColor.isDarkModeEnabled {
            UIApplication.shared.flipStatusBar()
        }
        
        //Force all view controllers to load now
        
        for controller in tabBarController.viewControllers ?? [] {
            _ = controller.view
            if let navController = controller as? UINavigationController {
                _ = navController.viewControllers[0].view
            }
        }
        
        #if targetEnvironment(simulator) || TARGET_SANDBOX
        let appVer = "2.0.0a-demo"
        #else
        var appVer = "2.0.0a"
        
        if FileManager.default.fileExists(atPath: "/chimera/jailbreakd") {
            appVer = "2.0.0a-chimera"
        } else if FileManager.default.fileExists(atPath: "/electra/jailbreakd") {
            appVer = "2.0.0a-electra"
        } else if FileManager.default.fileExists(atPath: "/var/checkra1n.dmg") {
            appVer = "2.0.0a-checkrain"
        } else if FileManager.default.fileExists(atPath: "/usr/libexec/substrated") {
            appVer = "2.0.0a-substrate"
        } else if FileManager.default.fileExists(atPath: "/usr/libexec/substituted") {
            appVer = "2.0.0a-unc0ver"
        }
        #endif
        
        /*let builder = FlurrySessionBuilder()
            .withAppVersion(appVer)
            .withLogLevel(FlurryLogLevelAll)
            .withCrashReporting(true).withSessionContinueSeconds(10)
        Flurry.startSession("", with: builder)*/
    }
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        PackageListManager.shared.waitForReady()
        
        let currentUpdates = PackageListManager.shared.availableUpdates()
        guard let currentPackages = PackageListManager.shared.packagesList(loadIdentifier: "", repoContext: nil) else {
            return
        }
        RepoManager.shared.update(force: false, forceReload: false, isBackground: true) { _, _ in
            let newUpdates = PackageListManager.shared.availableUpdates()
            guard let newPackages = PackageListManager.shared.packagesList(loadIdentifier: "", repoContext: nil) else {
                return
            }
            
            let diffUpdates = newUpdates.filter { !currentUpdates.contains($0) }
            if diffUpdates.count > 3 {
                let content = UNMutableNotificationContent()
                content.title = String(localizationKey: "Updates Available")
                content.body = String(format: String(localizationKey: "New updates for %d packages are available"), diffUpdates.count)
                content.badge = newUpdates.count as NSNumber
                
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                
                let request = UNNotificationRequest(identifier: "org.coolstar.sileo.updates", content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
            } else {
                for package in diffUpdates {
                    let content = UNMutableNotificationContent()
                    content.title = String(localizationKey: "New Update")
                    content.body = String(format: String(localizationKey: "%@ by %@ has been updated to version %@ on %@"),
                                          package.name ?? "",
                                          ControlFileParser.authorName(string: package.author ?? ""),
                                          package.version,
                                          package.sourceRepo?.displayName ?? "")
                    content.badge = newUpdates.count as NSNumber
                    
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                    
                    let request = UNNotificationRequest(identifier: "org.coolstar.sileo.update-\(package.package)",
                                                        content: content,
                                                        trigger: trigger)
                    UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
                }
            }
            
            let diffPackages = newPackages.filter { !currentPackages.contains($0) }
            
            let wishlist = WishListManager.shared.wishlist
            for package in diffPackages {
                if wishlist.contains(package.package) {
                    let content = UNMutableNotificationContent()
                    content.title = String(localizationKey: "New Update")
                    content.body = String(format: String(localizationKey: "%@ by %@ has been updated to version %@ on %@"),
                                          package.name ?? "",
                                          ControlFileParser.authorName(string: package.author ?? ""),
                                          package.version,
                                          package.sourceRepo?.displayName ?? "")
                    content.badge = newUpdates.count as NSNumber
                    
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                    
                    let request = UNNotificationRequest(identifier: "org.coolstar.sileo.update-\(package.package)",
                                                        content: content,
                                                        trigger: trigger)
                    UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
                }
            }
            
            completionHandler(.newData)
        }
    }
    
    func updateTintColor() {
        var tintColor = UIColor(red: 44/255, green: 177/255, blue: 190/255, alpha: 1)
        if UIAccessibility.isInvertColorsEnabled {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            tintColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            
            tintColor = UIColor(red: 1 - red, green: 1 - green, blue: 1 - blue, alpha: 1 - alpha)
        }
        
        if #available(iOS 13, *) {
        } else {
            if UIColor.isDarkModeEnabled {
                UINavigationBar.appearance().barStyle = .blackTranslucent
                UITabBar.appearance().barStyle = .black
                UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).keyboardAppearance = .dark
            } else {
                UINavigationBar.appearance().barStyle = .default
                UITabBar.appearance().barStyle = .default
                UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).keyboardAppearance = .default
            }
            UIApplication.shared.flipStatusBar()
        }
        
        UINavigationBar.appearance().tintColor = tintColor
        UIToolbar.appearance().tintColor = tintColor
        UISearchBar.appearance().tintColor = tintColor
        UITabBar.appearance().tintColor = tintColor
        
        UICollectionView.appearance().tintColor = tintColor
        UITableView.appearance().tintColor = tintColor
        DepictionBaseView.appearance().tintColor = tintColor
        self.window?.tintColor = tintColor
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        DispatchQueue.global(qos: .default).async {
            PackageListManager.shared.waitForReady()
            DispatchQueue.main.async {
                if url.scheme == "file" {
                    // The file is a deb. Open the package view controller to that file.
                    let viewController = PackageViewController()
                    viewController.package = PackageListManager.shared.package(url: url)
                    viewController.isPresentedModally = true
                    guard let tabBarController = self.window?.rootViewController as? UITabBarController,
                        let featuredVc = tabBarController.viewControllers?[0] as? UINavigationController? else {
                        return
                    }
                    featuredVc?.pushViewController(viewController, animated: true)
                    tabBarController.selectedIndex = 0
                } else {
                    // presentModally ignored; we always present modally for an external URL open.
                    var presentModally = false
                    if let viewController = URLManager.viewController(url: url, isExternalOpen: true, presentModally: &presentModally) {
                        self.window?.rootViewController?.present(viewController, animated: true, completion: nil)
                    }
                }
            }
        }
        
        if url.scheme == "cydia" && url.absoluteString.count >= 55 {
            let fullURL = url.absoluteString
            let itemsSource = fullURL.components(separatedBy: "source=")
            if itemsSource.count < 2 {
                return false
            }
            
            guard let parsedURLStr = itemsSource[1].removingPercentEncoding else {
                return false
            }
            
            let parsedURL = URL(string: parsedURLStr)
            if !url.absoluteString.contains("package=") {
                if let tabBarController = self.window?.rootViewController as? UITabBarController,
                    let sourcesNavNV = tabBarController.viewControllers?[2] as? UINavigationController {
                    tabBarController.selectedViewController = sourcesNavNV
                    if let sourcesVC = sourcesNavNV.viewControllers[0] as? SourcesViewController {
                        sourcesVC.presentAddSourceEntryField(url: parsedURL)
                    }
                }
            }
        } else if url.host == "source" && url.scheme == "sileo" {
            guard let tabBarController = self.window?.rootViewController as? UITabBarController,
                let sourcesNavNV = tabBarController.viewControllers?[2] as? UINavigationController,
                let sourcesVC = sourcesNavNV.viewControllers[0] as? SourcesViewController else {
                return false
            }
            let newURL = url.absoluteURL
            tabBarController.selectedViewController = sourcesNavNV
            sourcesVC.presentAddSourceEntryField(url: newURL)
        }
        return false
    }
    
    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        guard let tabBarController = self.window?.rootViewController as? UITabBarController else {
            return
        }
        if shortcutItem.type.hasSuffix("Search") {
            tabBarController.selectedViewController = tabBarController.viewControllers?.last
        }
        if shortcutItem.type.hasSuffix("Installed") {
            tabBarController.selectedViewController = tabBarController.viewControllers?[3]
        }
        
        guard let sourcesNavVc = tabBarController.viewControllers?[2] as? UINavigationController,
            let sourcesVC = sourcesNavVc.viewControllers[0] as? SourcesViewController else {
            return
        }
        
        if shortcutItem.type.hasSuffix("AddSource") {
            tabBarController.selectedViewController = sourcesNavVc
            sourcesVC.addSource(nil)
        }
        if shortcutItem.type.hasSuffix("Refresh") {
            tabBarController.selectedViewController = sourcesNavVc
            sourcesVC.refreshSources(control: nil, forceUpdate: true, forceReload: true)
        }
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        UIColor.isTransitionLockedForiOS13Bug = true
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        UIColor.isTransitionLockedForiOS13Bug = false
    }
}
