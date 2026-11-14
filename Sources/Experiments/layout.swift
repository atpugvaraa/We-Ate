//
//  layout.swift
//  WeAte
//
//  Created by Aarav Gupta on 12/11/26.
//

struct Toy {
    var a: UInt8
    var b: UInt32
    var c: UInt64
}
print(MemoryLayout<Toy>.offset(of: \.b)!)
print(MemoryLayout<Toy>.size)
print(MemoryLayout<Toy>.stride)

struct Flipped {
    var b: UInt32
    var a: UInt8
}
print(MemoryLayout<Flipped>.offset(of: \.a)!)
print(MemoryLayout<Flipped>.size)
print(MemoryLayout<Flipped>.stride)

struct Outer {
    var inner: Flipped
    var next: UInt8
}
print(MemoryLayout<Outer>.offset(of: \.next)!)
