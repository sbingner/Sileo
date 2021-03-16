//
//  PaymentAuthenticator.swift
//  Sileo
//
//  Created by Skitty on 6/28/20.
//  Copyright © 2020 CoolStar. All rights reserved.
//

import Foundation
//import AuthenticationServices
import SafariServices

class PaymentAuthenticator: NSObject/*, ASWebAuthenticationPresentationContextProviding*/ {
    public static let shared = PaymentAuthenticator()
    var currentAuthenticationSession: SFAuthenticationSession?
    var lastWindow: UIWindow?
    
    func authenticate(provider: PaymentProvider, window: UIWindow?, completion: ((PaymentError?, Bool) -> Void)?) {
        currentAuthenticationSession = SFAuthenticationSession(url: provider.authenticationURL, callbackURLScheme: "sileo") { url, error in
            if let error = error {
                if let error = error as? SFAuthenticationError,
                    error.code == SFAuthenticationError.canceledLogin {
                    completion?(nil, false)
                    return
                }
                completion?(PaymentError(error: error), false)
                return
            }
            guard let url = url,
                url.host == "authentication_success" else {
                    completion?(PaymentError.invalidResponse, false)
                    return
            }
            
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var token: String?
            var secret: String?
            
            for item in components?.queryItems ?? [] {
                if item.name == "token" && item.value != nil {
                    token = item.value
                } else if item.name == "payment_secret" && item.value != nil {
                    secret = item.value
                }
                if token != nil && secret != nil {
                    break
                }
            }
            
            if token == nil || secret == nil {
                completion?(PaymentError.invalidResponse, false)
                return
            }
            
            provider.authenticate(withToken: token!, paymentSecret: secret!)
            completion?(nil, false)
        }
        /*
        if #available(iOS 13.0, *) {
            self.lastWindow = window
            currentAuthenticationSession?.presentationContextProvider = self
        }
        */
        currentAuthenticationSession?.start()
    }
    
    func handlePayment(actionURL url: URL, provider: PaymentProvider, window: UIWindow?, completion: ((PaymentError?, Bool) -> Void)?) {
        currentAuthenticationSession = SFAuthenticationSession(url: url, callbackURLScheme: "sileo") { url, error in
            if let error = error {
                if let error = error as? SFAuthenticationError,
                    error.code == SFAuthenticationError.canceledLogin {
                    completion?(nil, false)
                    return
                }
                completion?(PaymentError(error: error), false)
                return
            }
            guard let url = url,
                url.host == "payment_completed" else {
                    completion?(PaymentError.invalidResponse, false)
                    return
            }
            
            completion?(nil, false)
        }
        /*
        if #available(iOS 13.0, *) {
            currentAuthenticationSession?.presentationContextProvider = self
            if #available(iOS 13.4, *) {
                for window in UIApplication.shared.windows {
                    self.lastWindow = window
                    if self.currentAuthenticationSession?.canStart ?? false {
                        break
                    }
                }
            } else {
                self.lastWindow = window
            }
        }
        */
        self.currentAuthenticationSession?.start()
    }
    /*
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        lastWindow ?? ASPresentationAnchor()
    }
    */
}
