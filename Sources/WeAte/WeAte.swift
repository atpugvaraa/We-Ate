// The Swift Programming Language
// https://docs.swift.org/swift-book
//
// Aarav Gupta (@atpugvaraa) on 11/11/26
//
//

import SwiftUI
import OpenMultitouchSupport

@main
struct WeAte: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 1080, height: 720)
        }
    }
}

struct ContentView: View {
    let manager: OMSManager = .shared
    
    init() {
        manager.startListening()
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
