//
//  SMC.swift
//  WeAte
//
//  Created by Aarav Gupta on 13/11/26.
//

import IOKit

@MainActor
final class SMC {
    static let shared = SMC()
    
    var connection: io_connect_t = 0
    
    init?() {
        precondition(MemoryLayout<SMCParamStruct>.offset(of: \.result)! == 40, "SMCParamStruct.result must be at byte 40 to match AppleSMC's ABI C layout")
        precondition(MemoryLayout<SMCParamStruct>.offset(of: \.data8)! == 42, "SMCParamStruct.data8 (command byte) must be at byte 42 to match AppleSMC's C layout")
        precondition(MemoryLayout<SMCParamStruct>.offset(of: \.bytes)! == 48, "SMCParamStruct.bytes (command byte) must be at byte 48 to match AppleSMC's C layout")
        precondition(MemoryLayout<SMCParamStruct>.size == 80, "SMCParamStruct must be exactly 80 bytes to match AppleSMC's C layout")
        
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        if service == 0 {
            print("No SMC Found")
            return nil
        }
        
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        
        if result != kIOReturnSuccess {
            print("failed")
            return nil
        }
    }
    
    deinit {
        IOServiceClose(connection)
    }
    
    func call(_ input: SMCParamStruct) -> SMCParamStruct? {
        var inputCopy = input
        var output = SMCParamStruct()
        var outSize = MemoryLayout<SMCParamStruct>.stride
        
        let callMethod = IOConnectCallStructMethod(connection, 2, &inputCopy, MemoryLayout<SMCParamStruct>.stride, &output, &outSize)
        
        if callMethod != kIOReturnSuccess {
            print("IOKit error: 0x" + String(UInt32(bitPattern: callMethod), radix: 16))
            return nil
        }
        
        return output
    }
    
    func fourCC(_ name: String) -> UInt32 {
        name.utf8.reduce(UInt32(0)) { acc, byte in
            UInt32(acc << 8) | UInt32(byte)
        }
    }
    
    func keyInfo(_ name: String) -> SMCKeyInfo? {
        var input = SMCParamStruct()
        input.key = fourCC(name)
        input.data8 = 9
        
        guard let out = call(input), out.result == 0 else { return nil }
        return out.keyInfo
    }
    
    func readBytes(_ name: String) -> [UInt8]? {
        guard let info = keyInfo(name) else { return nil }
        var input = SMCParamStruct()
        
        input.key = fourCC(name)
        input.keyInfo.dataSize = info.dataSize
        input.data8 = 5
        
        guard let out = call(input), out.result == 0 else { return nil }
        return withUnsafeBytes(of: out.bytes) {
            Array($0.prefix(Int(info.dataSize)))
        }
    }
    
    func writeBytes(_ name: String, _ bytes: [UInt8]) -> Bool {
        guard let info = keyInfo(name) else { return false }
        guard bytes.count == Int(info.dataSize) else { return false }
        var input = SMCParamStruct()
        
        input.key = fourCC(name)
        input.keyInfo.dataSize = info.dataSize
        input.data8 = 6
        
        withUnsafeMutableBytes(of: &input.bytes) {
            $0.copyBytes(from: bytes)
        }
        
        guard let out = call(input) else { return false }
        guard out.result == 0 else {
            print("SMC result:", out.result, "for", name)
            return false
        }
        
        return true
    }
    
    func readFloat(_ name: String) -> Float? {
        guard keyInfo(name)?.dataType == fourCC("flt "),
              let bytes = readBytes(name), bytes.count == 4 else { return nil }

        var bits: UInt32 = 0
        for (index, byte) in bytes.enumerated() {
            bits |= UInt32(byte) << (index * 8)
        }
        
        return Float(bitPattern: bits)
    }
    
    func writeFloat(_ name: String, _ value: Float) -> Bool {
        guard value.isFinite, keyInfo(name)?.dataType == fourCC("flt ") else { return false }
        let bits = value.bitPattern
        let bytes = (0..<4).map { UInt8((bits >> ($0 * 8)) & 0xFF) }
        return writeBytes(name, bytes)
    }

    /// Unlock (Ftst = 1), then switch fan 0 to manual (F0Md = 1). Verified by read-back.
    /// If it doesn't stick, hand the fan straight back to firmware.
    /// Firmware rejects F0Md right after unlocking (seen: SMC result 130), so retry until it
    /// sticks or we give up. Logs how long it took so we can measure, not guess.
    /// async + Task.sleep so the UI keeps running while we wait.
    func takeControl(timeout: Duration = .seconds(10)) async -> Bool {
        let clock = ContinuousClock()
        let start = clock.now
        _ = writeBytes("Ftst", [1])
        while clock.now - start < timeout {
            if readBytes("F0Md") == [1] || (writeBytes("F0Md", [1]) && readBytes("F0Md") == [1]) {
                print("manual mode after", clock.now - start)
                return true
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        print("manual mode refused for", timeout)
        _ = restoreAuto()
        return false
    }

    func restoreAuto() -> Bool {
        _ = writeBytes("F0Md", [0])
        _ = writeBytes("Ftst", [0])
        
        let mode = readBytes("F0Md")
        return (mode == [0] || mode == [3]) && readBytes("Ftst") == [0]
    }
}


struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}
struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}
struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}
struct SMCParamStruct {
    var key: UInt32 = 0
    var vers: SMCVersion = SMCVersion()
    var pLimitData: SMCPLimitData = SMCPLimitData()
    var keyInfo: SMCKeyInfo = SMCKeyInfo()
    
    // Padding added 2 bytes -> becomes 3 bytes due to tail-padding
    // since UInt16 wants an even byte to start or something
    // this makes the rest of the fields correctly placed.
    var _pad: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}
