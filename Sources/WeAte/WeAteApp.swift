// The Swift Programming Language
// https://docs.swift.org/swift-book
//
// Aarav Gupta (@atpugvaraa) on 11/11/26
//
//

import SwiftUI
import OpenMultitouchSupport

// Throttle feel knobs — tune these by ear.
let deadzone: Float = 40     // below this = idle (finger resting)
let full: Float = 140        // pressure for full throttle (sensor max ~331, so no need to mash)
let curve: Float = 0.5       // < 1 = light/medium presses rev harder; 1 = linear
let minFanSpeed: Float = 2317
let maxFanSpeed: Float = 6550

func throttle(from pressure: Float) -> Float {
    let pushed = pressure - deadzone
    let fraction = min(max(pushed / (full - deadzone), 0), 1)
    return pow(fraction, curve)
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
                .frame(minWidth: 1080, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
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
    let v8 = V8Sound.shared
    
    @State private var fanRPM: Float = 0
    @State private var engine = Engine()
    
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
        
        
        /// running the test
//        var e = Engine()
//        for _ in 0..<30 {
//            e.update(throttle: 1, dt: 1.0 / 60)
//        }
//        
//        print("after 30 ticks: ", e.rpm)
    }
    
    @State private var pressure: Float = 0
    
    var body: some View {
        VStack(spacing: 24) {
            Text("WeAte (V8)")
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(.white)
        
            HStack(spacing: 40) {
                Dial(value: engine.rpm / 1000, max: 8, labelStep: 1,
                     redline: engine.limiterCut / 1000,
                     title: "RPM ×1000", readout: "\(Int(engine.rpm))")
            
                VStack(spacing: 4) {
                    Text("\(engine.gear + 1)")
                        .font(.system(size: 96, weight: .heavy, design: .rounded))
                        .foregroundStyle(engine.fuelCut ? .red : .white)
                    Text("GEAR")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.5))
                    Text("fan \(Int(fanRPM)) rpm")
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 32)
                }
                .frame(width: 120)
            
                Dial(value: engine.speed, max: 240, labelStep: 40,
                     title: "KM/H", readout: "\(Int(engine.speed))")
            
                PressureBar(fraction: pressure / full)
            }
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .ignoresSafeArea()
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
            .task {
                let inControl = await smc?.takeControl() == true
                var lastTarget: Float = 0
                while !Task.isCancelled {
                    if inControl {
                        let engineFraction = (engine.rpm - engine.idle) / (engine.redline - engine.idle)
                        let target: Float = fanTarget(for: engineFraction)
                        
                        if abs(target - lastTarget) > 50 {
                            if smc?.writeFloat("F0Tg", target) == true {
                                lastTarget = target
                            }
                        }
                    }
                    fanRPM = smc?.readFloat("F0Ac") ?? 0
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            .task {
                let clock = ContinuousClock()
                var last = clock.now
                v8.start()
                
                while !Task.isCancelled {
                    let now = clock.now
                    let dt = Float((now - last) / .seconds(1))
                    last = now
                    engine.update(throttle: throttle(from: pressure), dt: dt)
                    v8.update(rpm: engine.rpm, load: engine.load)
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
    }
}

/// Vertical pressure bar: fills from the bottom, green -> yellow -> orange -> red.
struct PressureBar: View {
    let fraction: Float
    
    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let filled = geo.size.height * CGFloat(min(max(fraction, 0), 1))
                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(.white.opacity(0.08))
                    LinearGradient(colors: [.green, .yellow, .orange, .red],
                                   startPoint: .bottom, endPoint: .top)
                        .mask(alignment: .bottom) {
                            Capsule().frame(height: filled)
                        }
                }
            }
            .frame(width: 18, height: 320)
            
            Text("PRESSURE")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
