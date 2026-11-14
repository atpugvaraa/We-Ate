//
//  Engine.swift
//  WeAte
//
//  Created by Aarav Gupta on 14/11/26.
//  https://github.com/atpugvaraa
//  https://x.com/atpugvaraa
//
    
struct Engine {
    let idle: Float = 900
    let redline: Float = 7000
    let riseRate: Float = 8     // snappier rev-up so short blips register
    let fallRate: Float = 1.0   // slower fall so repeated blips stack up
    
    var rpm: Float
    
    init() {
        self.rpm = idle
    }
    
    mutating func update(throttle: Float, dt: Float) {
        let wanted = idle + throttle * (redline - idle)
        let rate = wanted > rpm ? riseRate : fallRate
        rpm += (wanted - rpm) * rate * dt
    }
}
