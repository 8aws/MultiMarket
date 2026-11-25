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
    registrarICloud(engineBridge.pluginRegistry)
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

  // MARK: - iCloud Drive (copia de seguridad y muestras de desarrollo)
  private static let contenedorICloud = "iCloud.es.uverse.multimarket"
  private let colaICloud = DispatchQueue(label: "es.uverse.multimarket.icloud", qos: .utility)

  /// Ficheros en <contenedor>/Documents/<ruta>. Todo fuera del hilo principal (obtener el contenedor puede bloquear) y con
  /// NSFileCoordinator para que iCloud nunca vea un fichero a medio escribir. La ruta puede llevar subcarpetas.
  private func registrarICloud(_ registry: FlutterPluginRegistry) {
    guard let reg = registry.registrar(forPlugin: "MMICloud") else { return }
    let canal = FlutterMethodChannel(name: "es.uverse.multimarket/icloud", binaryMessenger: reg.messenger())
    canal.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      self.colaICloud.async {
        let args = call.arguments as? [String: Any]
        let ok: (Any?) -> Void = { v in DispatchQueue.main.async { result(v) } }
        let fallo: (String, String) -> Void = { c, m in
          DispatchQueue.main.async { result(FlutterError(code: c, message: m, details: nil)) }
        }
        guard FileManager.default.ubiquityIdentityToken != nil,
              let base = FileManager.default.url(forUbiquityContainerIdentifier: AppDelegate.contenedorICloud) else {
          if call.method == "disponible" { ok(false) } else { fallo("no_disponible", "iCloud no disponible") }
          return
        }
        let docs = base.appendingPathComponent("Documents", isDirectory: true)
        func url(_ ruta: String) -> URL? {
          // sin «..» ni rutas absolutas: nunca se sale de Documents
          if ruta.hasPrefix("/") || ruta.contains("..") { return nil }
          return docs.appendingPathComponent(ruta)
        }
        switch call.method {
        case "disponible":
          ok(true)
        case "escribir":
          guard let ruta = args?["ruta"] as? String, let u = url(ruta),
                let datos = (args?["datos"] as? FlutterStandardTypedData)?.data else { fallo("args", "ruta/datos"); return }
          do {
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            var errCoord: NSError?; var errEsc: Error?
            NSFileCoordinator().coordinate(writingItemAt: u, options: .forReplacing, error: &errCoord) { destino in
              do { try datos.write(to: destino, options: .atomic) } catch { errEsc = error }
            }
            if let e = errCoord ?? (errEsc as NSError?) { fallo("escritura", e.localizedDescription) } else { ok(true) }
          } catch { fallo("escritura", error.localizedDescription) }
        case "leer":
          guard let ruta = args?["ruta"] as? String, let u = url(ruta) else { fallo("args", "ruta"); return }
          try? FileManager.default.startDownloadingUbiquitousItem(at: u)
          var errCoord: NSError?; var salida: Data?
          NSFileCoordinator().coordinate(readingItemAt: u, options: [], error: &errCoord) { origen in
            salida = try? Data(contentsOf: origen)
          }
          if let s = salida { ok(FlutterStandardTypedData(bytes: s)) } else { ok(nil) }
        case "info":
          guard let ruta = args?["ruta"] as? String, let u = url(ruta) else { fallo("args", "ruta"); return }
          if let a = try? FileManager.default.attributesOfItem(atPath: u.path), let f = a[.modificationDate] as? Date {
            ok(["modificado": Int(f.timeIntervalSince1970 * 1000), "tamano": (a[.size] as? Int) ?? 0])
          } else { ok(nil) }
        case "listar":
          guard let ruta = args?["ruta"] as? String, let u = url(ruta) else { fallo("args", "ruta"); return }
          let items = (try? FileManager.default.contentsOfDirectory(
            at: u, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
          ok(items.map { i -> [String: Any] in
            let v = try? i.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            return ["nombre": i.lastPathComponent, "carpeta": v?.isDirectory ?? false,
                    "modificado": Int((v?.contentModificationDate ?? Date(timeIntervalSince1970: 0)).timeIntervalSince1970 * 1000)]
          })
        case "borrar":
          guard let ruta = args?["ruta"] as? String, let u = url(ruta) else { fallo("args", "ruta"); return }
          var errCoord: NSError?; var errBorrar: Error?
          NSFileCoordinator().coordinate(writingItemAt: u, options: .forDeleting, error: &errCoord) { destino in
            do { try FileManager.default.removeItem(at: destino) } catch { errBorrar = error }
          }
          if let e = errCoord ?? (errBorrar as NSError?) { fallo("borrado", e.localizedDescription) } else { ok(true) }
        default:
          DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
        }
      }
    }
  }
}
