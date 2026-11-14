// The Swift Programming Language
// https://docs.swift.org/swift-book
//
// Aarav Gupta (@atpugvaraa) on 11/11/26
//
//

import SwiftUI
import OpenMultitouchSupport

let deadzone: Float = 40
let full: Float = 330
let minFanSpeed: Float = 2317
let maxFanSpeed: Float = 6550

func throttle(from pressure: Float) -> Float {
    let pushed = pressure - deadzone
    let fraction = pushed / (full - deadzone)
    return min(max(fraction, 0), 1)
}

func fanTarget(for throttle: Float) -> Float {
    let target = minFanSpeed + throttle * (maxFanSpeed - minFanSpeed)      // min 2317, max 6550 from recon
    return target
}

@main
struct WeAte: App {
    // Signal sources stop firing if deallocated, so keep them for the app's lifetime.
    private static var signalSources: [DispatchSourceSignal] = []

    init() {
        Self.restoreFanOnExit()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 1080, height: 720)
        }
    }

    /// Puts the fan back in firmware control on ⌘Q, Ctrl-C (SIGINT) and `kill` (SIGTERM).
    /// ponytail: crash / kill -9 can't be caught; restoreAuto at launch covers the next run.
    private static func restoreFanOnExit() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { _ = SMC.shared?.restoreAuto() }
        }

        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN) // stop the default instant kill so we get a chance to clean up
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { _ = SMC.shared?.restoreAuto() }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}

struct ContentView: View {
    let manager: OMSManager = .shared
    let smc = SMC.shared
    @State private var fanRPM: Float = 0
    
    init() {
        manager.startListening()
        /// Read the fan speed
//        var smc = SMC()
//        var FNum = smc?.readBytes("FNum")
//        print("FNum =", FNum as Any)
//        var F0Ac = smc?.readBytes("F0Ac")
//        print("F0Ac (bytes) =", F0Ac as Any)
//        print("F0Ac (keyInfo) =", smc?.keyInfo("F0Ac") as Any)
//        print(smc?.readFloat("F0Ac") as Any)
        
        /// Read fan speed min
//        print("F0Mn (keyInfo) =", smc?.keyInfo("F0Mn") as Any)
//        print("F0Mn (float) =", smc?.readFloat("F0Mn") as Any)
        
        /// Read fan speed max
//        print("F0Mx (keyInfo) =", smc?.keyInfo("F0Mx") as Any)
//        print("F0Mx (float) =", smc?.readFloat("F0Mx") as Any)
        
        /// Target rpm
//        print("F0Tg (keyInfo) =", smc?.keyInfo("F0Tg") as Any)
//        print("F0Tg (float) =", smc?.readFloat("F0Tg") as Any)
        
        /// Fan mode
//        print("F0md (keyInfo) =", smc?.keyInfo("F0md") as Any)
//        print("F0md (float) =", smc?.readBytes("F0md") as Any)
        
        /// Fan mode (fallback?)
//        print("F0Md (keyInfo) =", smc?.keyInfo("F0Md") as Any)
//        print("F0Md (float) =", smc?.readBytes("F0Md") as Any)
        
        /// firmware unlock flag
//        print("Ftst (keyInfo) =", smc?.keyInfo("Ftst") as Any)
//        print("Ftst (float) =", smc?.readBytes("Ftst") as Any)
        
        /// only runs with sudo
        /// try to write the bytes
//        print(smc?.writeBytes("Ftst", [0]) as Any)
        
        /// only runs with sudo
        /// try to write the bytes
        print(smc?.restoreAuto() as Any)
        
    }
    
    @State private var pressure: Float = 0
    
    var body: some View {
        Accelerometer(progress: $pressure)
        
        Text("Accelerometer: \(String(describing: pressure)) km/h")
            .onAppear() {
                Task { [self, manager] in
                    for await touchData in manager.touchDataStream {
                        // use touchData
                        let touchPressure = touchData.map { data -> Float in
                            return (data.pressure / 10)
                        }
                        
                        pressure = touchPressure.first ?? 0
                    }
                }
            }
            .onDisappear {
                manager.stopListening()
            }
        
        Text("rpm = \(String(describing: Int(fanRPM)))")
            .task {
                let inControl = await smc?.takeControl() == true
                var lastTarget: Float = 0
                while !Task.isCancelled {
                    if inControl {
                        let target: Float = fanTarget(for: throttle(from: pressure))
                        
                        if abs(target - lastTarget) > 50 {
                            if smc?.writeFloat("F0Tg", target) == true {
                                lastTarget = target
                            }
                            lastTarget = target
                        }
                    }
                    fanRPM = smc?.readFloat("F0Ac") ?? 0
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
    }
}

struct Accelerometer: View {
    @Binding var progress: Float
    
    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .fill(.black)
                .mask {
                    Circle()
                        .strokeBorder(.white, lineWidth: 20)
                        .fill(.clear)
                }
                .rotationEffect(.degrees(90))
        }
    }
}
