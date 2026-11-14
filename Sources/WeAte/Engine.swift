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
    let fallRate: Float = 4     // clutch drags revs down quickly on upshifts and lift-off

    // Rev limiter: cut fuel at the limit, bring it back a bit lower -> the "brrap" bounce
    let limiterCut: Float = 6900
    let limiterResume: Float = 6800

    // Gearbox (overall ratios, simplified). speed = rpm / ratio * kmhPerRPM
    let gears: [Float] = [3.0, 2.0, 1.45, 1.1, 0.9]
    let kmhPerRPM: Float = 0.0257   // 1st tops out ~60 km/h, 5th ~200 km/h
    let shiftUp: Float = 6600
    let shiftDown: Float = 2400
    let shiftTime: Float = 0.25     // seconds of no throttle while the clutch is in

    // Road (all in km/h per second)
    let pull: Float = 14            // per unit of gear ratio, at full throttle
    let rolling: Float = 2          // tyres
    let airDrag: Float = 0.02       // per km/h of speed
    let engineBrake: Float = 8      // per unit of gear ratio, off throttle

    var rpm: Float
    var speed: Float = 0            // km/h
    var gear = 0                    // index into gears, 0 = 1st
    var load: Float = 0             // throttle actually reaching the engine (0 while cut or shifting)
    var fuelCut = false
    var shifting: Float = 0         // seconds left in the current shift

    init() {
        self.rpm = idle
    }

    mutating func update(throttle: Float, dt: Float) {
        // 1. Limiter
        if rpm >= limiterCut { fuelCut = true }
        if rpm <= limiterResume { fuelCut = false }

        // 2. Gearbox
        shifting = max(shifting - dt, 0)
        if shifting == 0 {
            if rpm >= shiftUp && gear < gears.count - 1 {
                gear += 1
                shifting = shiftTime
            } else if rpm <= shiftDown && gear > 0 {
                gear -= 1
                shifting = shiftTime
            }
        }

        let ratio = gears[gear]
        load = (fuelCut || shifting > 0) ? 0 : throttle

        // 3. Road speed: low gears pull harder, drag and engine braking slow you down
        var accel = load * pull * ratio - rolling - airDrag * speed
        if load == 0 { accel -= engineBrake * ratio }
        speed = max(speed + accel * dt, 0)

        // 4. Revs follow the wheels. In 1st the clutch slips at launch so it doesn't bog.
        let wheels = speed * ratio / kmhPerRPM
        let launch = gear == 0 ? idle + load * 2600 : idle
        let wanted = min(max(wheels, launch), redline)
        let rate = wanted > rpm ? riseRate : fallRate
        rpm += (wanted - rpm) * rate * dt
    }
}
