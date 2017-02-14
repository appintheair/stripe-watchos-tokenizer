import Foundation
import WatchKit
import PassKit

///The simplest wrapper around Stripe Payment Token
public struct StripeToken {
    public let tokenId: String
    public let livemode: Bool
    public let created: Date

    init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String,
            let liveMode = dictionary["livemode"] as? Bool,
            let created = dictionary["created"] as? Double else { return nil }

        self.tokenId = id
        self.livemode = liveMode
        self.created = Date(timeIntervalSince1970: created)
    }
}

@available(watchOSApplicationExtension 3.0, *)
public class WatchOSStripeManager {

    static let StripeBaseURL = URL(string: "https://api.stripe.com/v1")!
    static let StripeAPIVersion = "2015-10-12"

    ///Error's userInfo will contain this key if error occurred communicating data to Stripe API
    public static let WatchOSStripeErrorKey = "WatchOSStripeErrorKey"

    ///Should call this before providing making any requests
    public static func provide(publishableKey key: String) {
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.httpAdditionalHeaders = [
            "X-Stripe-User-Agent": WatchOSStripeManager.stripeUserAgentDetails(),
            "Stripe-Version": StripeAPIVersion,
            "Authorization": "Bearer \(key)"
        ]
        shared.urlSession = URLSession(configuration: sessionConfiguration)
    }

    private init() {
        //The intended use is to be a singleton
    }

    ///Main entry point
    public static let shared = WatchOSStripeManager()

    private var urlSession: URLSession!

    ///The simplest requests wrapper
    private func startRequest(endpoint: String, postData: Data, completion: @escaping (Any?, Error?) -> Void) {
        assert(urlSession != nil, "Publishable key should be provided before making a request")

        let url = WatchOSStripeManager.StripeBaseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = postData

        urlSession.dataTask(with: request) { body, response, error in

            if let error = error {
                DispatchQueue.main.async {
                    completion(nil, error)
                }
                return
            }

            do {
                if let body = body, let json = try JSONSerialization.jsonObject(with: body, options: []) as? [String: Any] {
                    DispatchQueue.main.async {
                        if let token = StripeToken(dictionary: json) {
                            completion(token, nil)
                        } else {
                            completion(nil, NSError(domain: "WatchOSStripeDomain", code: 0, userInfo: [
                                NSLocalizedDescriptionKey: "Unknown error",
                                WatchOSStripeManager.WatchOSStripeErrorKey: json
                                ]))
                        }
                    }
                }
            } catch let error {
                DispatchQueue.main.async {
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
    func createToken(with payment: PKPayment, completion: @escaping (StripeToken?, Error?) -> Void) {
        createToken(with: WatchOSStripeManager.formEncodedData(for: payment), completion: completion)
    }

    private func createToken(with data: Data, completion: @escaping (StripeToken?, Error?) -> Void) {
        startRequest(endpoint: "tokens", postData: data, completion: { object, error in
            if let token = object as? StripeToken {
                completion(token, nil)
            } else if let error = error {
                print("[Stripe] Token creation error: \(error)")
                completion(nil, error)
            }
        })
    }

    /* The whole logic below is taken from Stripe-iOS-SDK */

    private static func formEncodedData(for payment: PKPayment) -> Data {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "+=")

        let paymentString = String(data: payment.token.paymentData, encoding: String.Encoding.utf8)!
            .addingPercentEncoding(withAllowedCharacters: set)!

        var payloadString = "pk_token=\(paymentString)"

        if let billingContact = payment.billingContact {
            var params = [String: String]()

            if let firstName = billingContact.name?.givenName, let lastName = billingContact.name?.familyName {
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
                let param = String(format: "&card[%@]=%@", key, value.addingPercentEncoding(withAllowedCharacters: set)!)
                payloadString = payloadString + param
            }
        }

        if let name = payment.token.paymentMethod.displayName {
            payloadString = payloadString + "&pk_token_instrument_name=\(name.addingPercentEncoding(withAllowedCharacters: set)!)"
        }

        if let network = payment.token.paymentMethod.network {
            payloadString = payloadString + "&pk_token_payment_network=\(network.rawValue.addingPercentEncoding(withAllowedCharacters: set)!)"
        }

        var transactionIdentifier = payment.token.transactionIdentifier
        if transactionIdentifier == "Simulated Identifier" {
            transactionIdentifier = testTransactionIdentifier()
        }
        payloadString = payloadString + "&pk_token_transaction_id=\(transactionIdentifier)"

        return payloadString.data(using: String.Encoding.utf8)!
    }


    private static func testTransactionIdentifier() -> String {
        let uuid = NSUUID().uuidString.replacingOccurrences(of: "~", with: "")

        // Simulated cards don't have enough info yet. For now, use a fake Visa number
        let number = "4242424242424242"

        // Without the original PKPaymentRequest, we'll need to use fake data here.
        let amount = NSDecimalNumber(string: "0")
        let cents = amount.multiplying(byPowerOf10: 2).intValue.description
        let currency = "USD"
        return ["ApplePayStubs", number, cents, currency, uuid].joined(separator: "~")
    }


    private static func stripeUserAgentDetails() -> String {
        var details: [String: Any] = [
            "lang": "objective-c",
            "bindings_version": "8.0.5"
        ]

        details["os_version"] = WKInterfaceDevice.current().systemVersion
        details["model"] = WKInterfaceDevice.current().localizedModel

        return String(data: try! JSONSerialization.data(withJSONObject: details, options: []), encoding: String.Encoding.utf8)!
    }
}
