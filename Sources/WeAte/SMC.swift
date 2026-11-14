//
//  SMC.swift
//  WeAte
//
//  Created by Aarav Gupta on 13/11/26.
//

import IOKit

final class SMC {
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
    
    func readFloat(_ name: String) -> Float? {
        guard keyInfo(name)?.dataType == fourCC("flt "),
              let bytes = readBytes(name), bytes.count == 4 else { return nil }

        var bits: UInt32 = 0
        for (index, byte) in bytes.enumerated() {
            bits |= UInt32(byte) << (index * 8)
        }
        return Float(bitPattern: bits)
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
