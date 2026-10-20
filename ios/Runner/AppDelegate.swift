import Flutter
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registrarOcr(engineBridge.pluginRegistry)
  }

  /// OCR de tickets con el reconocimiento de texto nativo de Apple (Vision). Todo ocurre en el dispositivo.
  /// Devuelve fragmentos con su caja normalizada (0–1, origen arriba-izquierda); Dart los agrupa en filas.
  private func registrarOcr(_ registry: FlutterPluginRegistry) {
    guard let reg = registry.registrar(forPlugin: "MMOcr") else { return }
    let canal = FlutterMethodChannel(name: "es.uverse.multimarket/ocr", binaryMessenger: reg.messenger())
    canal.setMethodCallHandler { call, result in
      guard call.method == "reconocer", let ruta = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        guard let img = UIImage(contentsOfFile: ruta), let cg = img.cgImage else {
          DispatchQueue.main.async { result(FlutterError(code: "imagen", message: "No se pudo abrir la imagen", details: nil)) }
          return
        }
        let peticion = VNRecognizeTextRequest()
        peticion.recognitionLevel = .accurate
        peticion.recognitionLanguages = ["es-ES", "en-US"]
        peticion.usesLanguageCorrection = false
        let manejador = VNImageRequestHandler(cgImage: cg, orientation: AppDelegate.orientacion(img.imageOrientation), options: [:])
        do {
          try manejador.perform([peticion])
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "vision", message: error.localizedDescription, details: nil)) }
          return
        }
        var salida: [[String: Any]] = []
        for obs in peticion.results ?? [] {
          guard let c = obs.topCandidates(1).first else { continue }
          let b = obs.boundingBox
          salida.append([
            "t": c.string,
            "x0": b.minX, "x1": b.maxX,
            "y0": 1 - b.maxY, "y1": 1 - b.minY,
          ])
        }
        DispatchQueue.main.async { result(salida) }
      }
    }
  }

  private static func orientacion(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
    switch o {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }
}
