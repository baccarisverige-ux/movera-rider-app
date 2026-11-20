import Flutter
import UIKit
import GoogleMaps
import DeviceCheck

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // GMSApiKey comes from the GOOGLE_MAPS_API_KEY build setting
    // (ios/Flutter/Secrets.xcconfig). Without a key the Maps SDK must not be
    // used, so Dart asks over "movera/maps_config" and shows its no-map
    // fallback instead of creating a GoogleMap.
    let mapsAPIKey = (Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let hasMapsAPIKey = !mapsAPIKey.isEmpty && !mapsAPIKey.hasPrefix("$(")
    if hasMapsAPIKey {
      GMSServices.provideAPIKey(mapsAPIKey)
    } else {
      NSLog("[movera] GOOGLE_MAPS_API_KEY is not set: maps are disabled in this build.")
    }
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "MoveraMapsConfig") {
      let channel = FlutterMethodChannel(
        name: "movera/maps_config",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        if call.method == "hasGoogleMapsKey" {
          result(hasMapsAPIKey)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
    // Contract v0.18.138 (deviceCheck.check, iPhone): Apple App Attest. INACTIVE
    // until the owner's Apple account exists: the Dart side calls this only in
    // a build made with --dart-define=APP_ATTEST=true and the App Attest
    // capability. A new key per request, attested with the app's binding as
    // clientDataHash. Any failure answers nil: the request goes without a check.
    if let registrar = self.registrar(forPlugin: "MoveraDeviceCheck") {
      let channel = FlutterMethodChannel(
        name: "movera/device_check", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "appAttest",
              let arguments = call.arguments as? [String: Any],
              let hashText = arguments["clientDataHash"] as? String,
              let hash = Data(base64Encoded: hashText) else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard #available(iOS 14.0, *), DCAppAttestService.shared.isSupported else {
          result(nil)
          return
        }
        let service = DCAppAttestService.shared
        service.generateKey { keyId, error in
          guard let keyId = keyId, error == nil else {
            DispatchQueue.main.async { result(nil) }
            return
          }
          service.attestKey(keyId, clientDataHash: hash) { attestation, error in
            DispatchQueue.main.async {
              guard let attestation = attestation, error == nil else {
                result(nil)
                return
              }
              result(["keyId": keyId, "attestation": attestation.base64EncodedString()])
            }
          }
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
