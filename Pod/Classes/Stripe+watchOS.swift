import Foundation
import WatchKit
import PassKit

let StripeBaseURL = NSURL(string: "https://api.stripe.com/v1")!
let StripeAPIVersion = "2015-10-12"

///NSError's userInfo will contain this key if error occurred communicating data to Stripe API
public let WatchOSStripeErrorKey = "WatchOSStripeErrorKey"

///The simplest wrapper around Stripe Payment Token
public struct StripeToken {
    public let tokenId: String
    public let livemode: Bool
    public let created: NSDate

    init?(dictionary: [String: AnyObject]) {
        guard let id = dictionary["id"] as? String,
            let liveMode = dictionary["livemode"] as? Bool,
            let created = dictionary["created"] as? Double else { return nil }

        self.tokenId = id
        self.livemode = liveMode
        self.created = NSDate(timeIntervalSince1970: created)
    }
}

@available(watchOSApplicationExtension 3.0, *)
public class WatchOSStripeManager {

    ///Should call this before providing making any requests
    public class func providePublishableKey(key: String) {
        let sessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration()
        sessionConfiguration.HTTPAdditionalHeaders = [
            "X-Stripe-User-Agent": WatchOSStripeManager.stripeUserAgentDetails(),
            "Stripe-Version": StripeAPIVersion,
            "Authorization": "Bearer \(key)"
        ]
        sharedManager.urlSession = NSURLSession(configuration: sessionConfiguration)
    }

    private init() {
        //The intended use is to be a singleton
    }

    ///Main entry point
    public static let sharedManager = WatchOSStripeManager()

    private var urlSession: NSURLSession!

    ///The simplest requests wrapper
    private func startRequest(endpoint: String, postData: NSData, completion: (Any?, NSError?) -> Void) {
        assert(urlSession != nil, "Publishable key should be provided before making a request")

        let url = StripeBaseURL.URLByAppendingPathComponent(endpoint)!
        let request = NSMutableURLRequest(URL: url)
        request.HTTPMethod = "POST"
        request.HTTPBody = postData

        urlSession.dataTaskWithRequest(request) { body, response, error in

            if let error = error {
                dispatch_async(dispatch_get_main_queue()) {
                    completion(nil, error)
                }
                return
            }

            do {
                if let body = body, json = try NSJSONSerialization.JSONObjectWithData(body, options: []) as? [String: AnyObject] {
                    dispatch_async(dispatch_get_main_queue()) {
                        if let token = StripeToken(dictionary: json) {
                            completion(token, nil)
                        } else {
                            completion(nil, NSError(domain: "WatchOSStripeDomain", code: 0, userInfo: [
                                NSLocalizedDescriptionKey: "Unknown error",
                                WatchOSStripeErrorKey: json
                            ]))
                        }
                    }
                }
            } catch let error as NSError {
                dispatch_async(dispatch_get_main_queue()) {
                    completion(nil, error)
                }
            }
        }.resume()
    }

    /**
     Use this method to convert `PKPayment` object given by Apple Pay authorization to Stripe Payment Token.

     - parameter payment: Payment object received from `func paymentAuthorizationController(controller: PKPaymentAuthorizationController, didAuthorizePayment payment: PKPayment, completion: (PKPaymentAuthorizationStatus) -> Void) {`
     - parameter completion: Will contain either Token or Error
     */
    func createTokenWithPayment(payment: PKPayment, completion: (StripeToken?, NSError?) -> Void) {
        createTokenWithPaymentData(WatchOSStripeManager.formEncodedDataForPayment(payment), completion: completion)
    }

    private func createTokenWithPaymentData(data: NSData, completion: (StripeToken?, NSError?) -> Void) {
        startRequest("tokens", postData: data, completion: { object, error in
            if let token = object as? StripeToken {
                completion(token, nil)
            } else if let error = error {
                print("[Stripe] Token creation error: \(error)")
                completion(nil, error)
            }
        })
    }

    /* The whole logic below is taken from Stripe-iOS-SDK */

    private class func formEncodedDataForPayment(payment: PKPayment) -> NSData {
        let set = NSCharacterSet.URLQueryAllowedCharacterSet().mutableCopy() as! NSMutableCharacterSet
        set.removeCharactersInString("+=")

        let paymentString = String(data: payment.token.paymentData, encoding: NSUTF8StringEncoding)!.stringByAddingPercentEncodingWithAllowedCharacters(set)!

        var payloadString = "pk_token=\(paymentString)"

        if let billingContact = payment.billingContact {
            var params = [String: String]()

            if let firstName = billingContact.name?.givenName, lastName = billingContact.name?.familyName {
                params["name"] = "\(firstName) \(lastName)"
            }

            if let addressValues = billingContact.postalAddress {
                params["address_line1"] = addressValues.street
                params["address_city"] = addressValues.city
                params["address_state"] = addressValues.state
                params["address_zip"] = addressValues.postalCode
                params["address_country"] = addressValues.country
            }

            for (key, value) in params {
                let param = String(format: "&card[%@]=%@", key, value.stringByAddingPercentEncodingWithAllowedCharacters(set)!)
                payloadString = payloadString + param
            }
        }

        if let name = payment.token.paymentMethod.displayName {
            payloadString = payloadString + "&pk_token_instrument_name=\(name.stringByAddingPercentEncodingWithAllowedCharacters(set)!)"
        }

        if let network = payment.token.paymentMethod.network {
            payloadString = payloadString + "&pk_token_payment_network=\(network.stringByAddingPercentEncodingWithAllowedCharacters(set)!)"
        }

        var transactionIdentifier = payment.token.transactionIdentifier
        if transactionIdentifier == "Simulated Identifier" {
            transactionIdentifier = testTransactionIdentifier()
        }
        payloadString = payloadString + "&pk_token_transaction_id=\(transactionIdentifier)"

        return payloadString.dataUsingEncoding(NSUTF8StringEncoding)!
    }


    private class func testTransactionIdentifier() -> String {
        let uuid = NSUUID().UUIDString.stringByReplacingOccurrencesOfString("~", withString: "")

        // Simulated cards don't have enough info yet. For now, use a fake Visa number
        let number = "4242424242424242"

        // Without the original PKPaymentRequest, we'll need to use fake data here.
        let amount = NSDecimalNumber(string: "0")
        let cents = amount.decimalNumberByMultiplyingByPowerOf10(2).integerValue.description
        let currency = "USD"
        return ["ApplePayStubs", number, cents, currency, uuid].joinWithSeparator("~")
    }


    private class func stripeUserAgentDetails() -> String {
        var details: [String: AnyObject] = [
            "lang": "objective-c",
            "bindings_version": "8.0.5"
        ]

        details["os_version"] = WKInterfaceDevice.currentDevice().systemVersion
        details["model"] = WKInterfaceDevice.currentDevice().localizedModel

        return String(data: try! NSJSONSerialization.dataWithJSONObject(details, options: []), encoding: NSUTF8StringEncoding)!
    }
}
