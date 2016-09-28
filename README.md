# stripe-watchos-tokenizer
Allows to convert authorized PKPayment objects to Stripe tokens.

## Installation
Add the following line to your Podfile for Swift 3.0
```
pod 'Stripe_watchOS'
```
If you want to use Swift 2.3 version then use:
```
pod 'Stripe_watchOS', :git => 'https://github.com/appintheair/stripe-watchos-tokenizer.git', :branch => 'swift-2.3'
```

## Usage
Start by providing you publishable key:
```
WatchOSStripeManager.provide(publishableKey: "pk_test_<KEY>")
```

Then some where in your code you'd probably want to create `PKPayment` (typically when you want to sell something). And present `PKPaymentAuthorizationController`
```
let request = PKPaymentRequest()
request.merchantIdentifier = "<MERCHANT_ID>"
request.supportedNetworks = [.amex, .masterCard, .visa]
request.merchantCapabilities = [.capability3DS]
request.countryCode = "US"
request.currencyCode = "USD"
request.paymentSummaryItems = [
    PKPaymentSummaryItem(label: "App in the Air", amount: NSDecimalNumber(value: 10))
]

let controller = PKPaymentAuthorizationController(paymentRequest: request)
controller.delegate = self
controller.present(completion: nil)
```
Then in `PKPaymentAuthorizationControllerDelegate` handle successful payment's authorization and generate token:
```
func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController, didAuthorizePayment payment: PKPayment, completion: @escaping (PKPaymentAuthorizationStatus) -> Void) {

    WatchOSStripeManager.sharedManager.createToken(withPayment: payment) { token, error in
        if let error = error {
            print(error)
            self.handlePaymentFailure()
            completion(.failure)
            return
        }

        guard let token = token else { return }

        print("TOKEN FOR PAYMENT: \(token.tokenId)")
    }

}
```
## License
Stripe_watchOS is available under the MIT license. See the LICENSE file for more info.
