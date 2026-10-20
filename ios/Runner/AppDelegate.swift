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
        guard let original = UIImage(contentsOfFile: ruta) else {
          DispatchQueue.main.async { result(FlutterError(code: "imagen", message: "No se pudo abrir la imagen", details: nil)) }
          return
        }
        // se normaliza la orientación (fotos giradas) a una imagen «derecha»
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let derecha = UIGraphicsImageRenderer(size: original.size, format: fmt).image { _ in
          UIColor.white.setFill()
          UIRectFill(CGRect(origin: .zero, size: original.size))
          original.draw(in: CGRect(origin: .zero, size: original.size))
        }
        guard let cg = derecha.cgImage else {
          DispatchQueue.main.async { result(FlutterError(code: "imagen", message: "Imagen no válida", details: nil)) }
          return
        }
        let W = Double(cg.width), H = Double(cg.height)

        func reconocer(_ c: CGImage) throws -> [VNRecognizedTextObservation] {
          let peticion = VNRecognizeTextRequest()
          peticion.recognitionLevel = .accurate
          peticion.recognitionLanguages = ["es-ES", "en-US"]
          peticion.usesLanguageCorrection = false
          try VNImageRequestHandler(cgImage: c, options: [:]).perform([peticion])
          return peticion.results ?? []
        }

        var salida: [[String: Any]] = []
        do {
          if H > W * 1.8 {
            // Imagen muy alta (captura de un ticket largo): Vision la reduce y pierde letras. Se lee por tiras a resolución
            // nativa con solape; cada línea la aporta solo la tira que la contiene entera (por su centro).
            let alto = W * 1.4, paso = alto * 0.88, solape = alto - paso
            var y = 0.0
            var indice = 0
            while y < H {
              let h = min(alto, H - y)
              let ultima = y + h >= H
              guard let tira = cg.cropping(to: CGRect(x: 0, y: y, width: W, height: h)) else { break }
              let desde = indice == 0 ? 0 : y + solape / 2
              let hasta = ultima ? H : y + h - solape / 2
              for obs in try reconocer(tira) {
                guard let c = obs.topCandidates(1).first else { continue }
                let b = obs.boundingBox
                let y0 = y + (1 - b.maxY) * h, y1 = y + (1 - b.minY) * h
                let centro = (y0 + y1) / 2
                if centro < desde || centro >= hasta { continue }
                salida.append(["t": c.string, "x0": b.minX, "x1": b.maxX, "y0": y0 / H, "y1": y1 / H])
              }
              if ultima { break }
              y += paso
              indice += 1
            }
          } else {
            for obs in try reconocer(cg) {
              guard let c = obs.topCandidates(1).first else { continue }
              let b = obs.boundingBox
              salida.append(["t": c.string, "x0": b.minX, "x1": b.maxX, "y0": 1 - b.maxY, "y1": 1 - b.minY])
            }
          }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "vision", message: error.localizedDescription, details: nil)) }
          return
        }
        DispatchQueue.main.async { result(salida) }
      }
    }
  }
}
