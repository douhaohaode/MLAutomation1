//
//  KeyCode.swift
//  MLAutomation
//
//  从 WindowService.swift 独立出来，确保全局可见
//

import CoreGraphics

// MARK: - 常用 CGKeyCode 常量
struct KeyCode {
    // 字母
    static let a: CGKeyCode = 0;  static let b: CGKeyCode = 11
    static let c: CGKeyCode = 8;  static let d: CGKeyCode = 2
    static let e: CGKeyCode = 14; static let f: CGKeyCode = 3
    static let g: CGKeyCode = 5;  static let h: CGKeyCode = 4
    static let i: CGKeyCode = 34; static let j: CGKeyCode = 38
    static let k: CGKeyCode = 40; static let l: CGKeyCode = 37
    static let m: CGKeyCode = 46; static let n: CGKeyCode = 45
    static let o: CGKeyCode = 31; static let p: CGKeyCode = 35
    static let q: CGKeyCode = 12; static let r: CGKeyCode = 15
    static let s: CGKeyCode = 1;  static let t: CGKeyCode = 17
    static let u: CGKeyCode = 32; static let v: CGKeyCode = 9
    static let w: CGKeyCode = 13; static let x: CGKeyCode = 7
    static let y: CGKeyCode = 16; static let z: CGKeyCode = 6

    // 数字行
    static let num1: CGKeyCode = 18; static let num2: CGKeyCode = 19
    static let num3: CGKeyCode = 20; static let num4: CGKeyCode = 21
    static let num5: CGKeyCode = 23; static let num6: CGKeyCode = 22
    static let num7: CGKeyCode = 26; static let num8: CGKeyCode = 28
    static let num9: CGKeyCode = 25; static let num0: CGKeyCode = 29

    // 功能键
    static let f1:  CGKeyCode = 122; static let f2:  CGKeyCode = 120
    static let f3:  CGKeyCode = 99;  static let f4:  CGKeyCode = 118
    static let f5:  CGKeyCode = 96;  static let f6:  CGKeyCode = 97
    static let f7:  CGKeyCode = 98;  static let f8:  CGKeyCode = 100
    static let f9:  CGKeyCode = 101; static let f10: CGKeyCode = 109
    static let f11: CGKeyCode = 103; static let f12: CGKeyCode = 111

    // 方向键
    static let arrowUp:    CGKeyCode = 126
    static let arrowDown:  CGKeyCode = 125
    static let arrowLeft:  CGKeyCode = 123
    static let arrowRight: CGKeyCode = 124

    // 控制键
    static let `return`: CGKeyCode = 36
    static let escape:   CGKeyCode = 53
    static let space:    CGKeyCode = 49
    static let tab:      CGKeyCode = 48
    static let delete:   CGKeyCode = 51

    // 小键盘（技能常用）
    static let kp0: CGKeyCode = 82; static let kp1: CGKeyCode = 83
    static let kp2: CGKeyCode = 84; static let kp3: CGKeyCode = 85
    static let kp4: CGKeyCode = 86; static let kp5: CGKeyCode = 87
    static let kp6: CGKeyCode = 88; static let kp7: CGKeyCode = 89
    static let kp8: CGKeyCode = 91; static let kp9: CGKeyCode = 92
}
