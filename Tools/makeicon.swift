import AppKit
import ImageIO
import CoreGraphics

// Halo 앱 아이콘 — 우주 지평선 위로 빛나는 Dynamic 노치(지구 대신 노치 + 일출 빛).
// 결과: Resources/icon_1024.png

let S: CGFloat = 1024

func hex(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((h >> 16) & 0xff) / 255,
            green: CGFloat((h >> 8) & 0xff) / 255,
            blue: CGFloat(h & 0xff) / 255, alpha: a)
}

let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                    bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// 상단-좌측 원점(아래로 +y)
ctx.translateBy(x: 0, y: S)
ctx.scaleBy(x: 1, y: -1)

// macOS 스퀘어클(약간 안쪽 여백)
let margin = S * 0.085
let rect = CGRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
let radius = rect.width * 0.2237
ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()

let cx = S / 2
let horizon = S * 0.55          // 노치 윗변 = 지평선
let notchBottom = S * 0.94
let halfW = S * 0.295
let botR = S * 0.135

func radial(_ colors: [CGColor], _ locs: [CGFloat], at p: CGPoint, r: CGFloat) {
    let g = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locs)!
    ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
}

// 1) 배경: 어두운 상단 → 짙은 파랑 하단
let bg = CGGradient(colorsSpace: cs,
                    colors: [hex(0x04060d), hex(0x07173a), hex(0x0e2f63)] as CFArray,
                    locations: [0, 0.6, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: S), options: [])

// 2) 좌우 네뷸라(은은한 시안)
ctx.setBlendMode(.screen)
radial([hex(0x1f9bff, 0.22), hex(0x000000, 0)], [0, 1], at: CGPoint(x: S * 0.12, y: S * 0.40), r: S * 0.34)
radial([hex(0x2f6bff, 0.16), hex(0x000000, 0)], [0, 1], at: CGPoint(x: S * 0.90, y: S * 0.52), r: S * 0.30)

// 3) 별
for _ in 0..<95 {
    let x = CGFloat.random(in: 0...S)
    let y = CGFloat.random(in: 0...(S * 0.58))
    let sz = CGFloat.random(in: 0.6...2.8)
    ctx.setFillColor(hex(0xffffff, CGFloat.random(in: 0.25...0.95)))
    ctx.fillEllipse(in: CGRect(x: x, y: y, width: sz, height: sz))
}
ctx.setBlendMode(.normal)

// 4) 지평선 글로우(노치 뒤에서 번지는 큰 빛)
ctx.setBlendMode(.screen)
radial([hex(0xdcf3ff, 0.9), hex(0x4fb8ff, 0.45), hex(0x1f6bff, 0)], [0, 0.28, 1],
       at: CGPoint(x: cx, y: horizon), r: S * 0.5)

// 5) 수평 빛줄기
ctx.saveGState()
ctx.clip(to: CGRect(x: 0, y: horizon - S * 0.011, width: S, height: S * 0.022))
let streak = CGGradient(colorsSpace: cs,
                        colors: [hex(0xffffff, 0), hex(0xeafaff, 0.95), hex(0xffffff, 0)] as CFArray,
                        locations: [0, 0.5, 1])!
ctx.drawLinearGradient(streak, start: CGPoint(x: 0, y: horizon), end: CGPoint(x: S, y: horizon), options: [])
ctx.restoreGState()
ctx.setBlendMode(.normal)

// 6) 노치 본체(어두움) + 도시 불빛
func notchPath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: cx - halfW, y: horizon))
    p.addLine(to: CGPoint(x: cx + halfW, y: horizon))
    p.addLine(to: CGPoint(x: cx + halfW, y: notchBottom - botR))
    p.addQuadCurve(to: CGPoint(x: cx + halfW - botR, y: notchBottom), control: CGPoint(x: cx + halfW, y: notchBottom))
    p.addLine(to: CGPoint(x: cx - halfW + botR, y: notchBottom))
    p.addQuadCurve(to: CGPoint(x: cx - halfW, y: notchBottom - botR), control: CGPoint(x: cx - halfW, y: notchBottom))
    p.closeSubpath()
    return p
}
ctx.saveGState()
ctx.addPath(notchPath()); ctx.clip()
let body = CGGradient(colorsSpace: cs, colors: [hex(0x0b1d3c), hex(0x04070f)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(body, start: CGPoint(x: 0, y: horizon), end: CGPoint(x: 0, y: notchBottom), options: [])
// 도시 불빛(따뜻한 흰색 + 시안)
ctx.setBlendMode(.screen)
for _ in 0..<70 {
    let x = CGFloat.random(in: (cx - halfW + 24)...(cx + halfW - 24))
    let y = CGFloat.random(in: (horizon + S * 0.05)...(notchBottom - 30))
    let sz = CGFloat.random(in: 1.2...3.4)
    let warm = Bool.random()
    ctx.setFillColor(warm ? hex(0xffe9b0, CGFloat.random(in: 0.4...0.95))
                          : hex(0x9fd8ff, CGFloat.random(in: 0.4...0.95)))
    ctx.fillEllipse(in: CGRect(x: x, y: y, width: sz, height: sz))
}
// 노치 윗변 림 라이트(빛이 닿는 가장자리)
ctx.setBlendMode(.screen)
ctx.clip(to: CGRect(x: cx - halfW, y: horizon, width: halfW * 2, height: S * 0.05))
let rim = CGGradient(colorsSpace: cs, colors: [hex(0xcdefff, 0.95), hex(0x4fb8ff, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(rim, start: CGPoint(x: 0, y: horizon), end: CGPoint(x: 0, y: horizon + S * 0.05), options: [])
ctx.restoreGState()

// 7) 중앙 태양 블룸(노치 윗변에 떠오르는 가장 밝은 점)
ctx.setBlendMode(.screen)
radial([hex(0xffffff, 1), hex(0xdaf5ff, 0.6), hex(0x4fb8ff, 0)], [0, 0.3, 1],
       at: CGPoint(x: cx, y: horizon), r: S * 0.17)
ctx.setBlendMode(.normal)

// 저장
let img = ctx.makeImage()!
let outURL = URL(fileURLWithPath: "Resources/icon_1024.png")
let dest = CGImageDestinationCreateWithURL(outURL as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
if CGImageDestinationFinalize(dest) {
    print("✅ wrote \(outURL.path)")
} else {
    print("❌ failed to write PNG"); exit(1)
}
