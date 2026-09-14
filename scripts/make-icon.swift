#!/usr/bin/env swift
//
// Builds App/Resources/Assets.xcassets/AppIcon.appiconset from the coin artwork.
//
//   swift scripts/make-icon.swift [quelle.png]
//
// The layout follows Apple's macOS app icon template, measured on the system
// icons of macOS 15: on a 1024 px canvas the tile is 824 x 824, centred with a
// 100 px margin, corner radius 185.4, plus a soft shadow under the tile.
// The artwork is placed inside the tile on a background sampled from its own
// white, so the coin's drop shadow keeps blending into the tile.

import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Layout

let canvas = 1024.0
let kachelGroesse = 824.0
let kachelRadius = 185.4
let muenzeAnteil = 0.76 // coin diameter relative to the tile width
let optischerVersatz = 0.012 // lift the coin slightly; its shadow weighs below
let saumAnteil = 0.02 // feathered edge of the artwork, relative to its width

// MARK: - Input

let repoWurzel = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent()
let quelle = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : repoWurzel.appendingPathComponent("scripts/icon/pfennig-white.png")
let ziel = repoWurzel
    .appendingPathComponent("App/Resources/Assets.xcassets/AppIcon.appiconset")

func abbruch(_ text: String) -> Never {
    FileHandle.standardError.write(Data("error: \(text)\n".utf8))
    exit(1)
}

guard let bildQuelle = CGImageSourceCreateWithURL(quelle as CFURL, nil),
      let bild = CGImageSourceCreateImageAtIndex(bildQuelle, 0, nil)
else { abbruch("cannot read \(quelle.path)") }

// MARK: - Measuring the artwork

/// RGBA pixels of an image, top row first.
func pixel(_ bild: CGImage) -> (daten: [UInt8], breite: Int, hoehe: Int) {
    let breite = bild.width, hoehe = bild.height
    var daten = [UInt8](repeating: 0, count: breite * hoehe * 4)
    let kontext = CGContext(
        data: &daten, width: breite, height: hoehe, bitsPerComponent: 8,
        bytesPerRow: breite * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    kontext.draw(bild, in: CGRect(x: 0, y: 0, width: breite, height: hoehe))
    return (daten, breite, hoehe)
}

let (daten, breite, hoehe) = pixel(bild)
func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
    let i = (y * breite + x) * 4
    return (Int(daten[i]), Int(daten[i + 1]), Int(daten[i + 2]))
}

/// Mean colour of the outermost ring, which is the artwork's white.
var summe = (0, 0, 0)
var zaehler = 0
for x in 0 ..< breite {
    for y in [0, 1, hoehe - 2, hoehe - 1] {
        let p = rgb(x, y); summe = (summe.0 + p.0, summe.1 + p.1, summe.2 + p.2); zaehler += 1
    }
}

for y in 0 ..< hoehe {
    for x in [0, 1, breite - 2, breite - 1] {
        let p = rgb(x, y); summe = (summe.0 + p.0, summe.1 + p.1, summe.2 + p.2); zaehler += 1
    }
}

let hintergrund = CGColor(
    srgbRed: CGFloat(summe.0) / CGFloat(zaehler) / 255,
    green: CGFloat(summe.1) / CGFloat(zaehler) / 255,
    blue: CGFloat(summe.2) / CGFloat(zaehler) / 255,
    alpha: 1
)

/// Bounding box of the copper: the coin, without its grey drop shadow.
var links = breite, oben = hoehe, rechts = -1, unten = -1
for y in 0 ..< hoehe {
    for x in 0 ..< breite where rgb(x, y).0 - rgb(x, y).2 > 25 {
        links = min(links, x); rechts = max(rechts, x)
        oben = min(oben, y); unten = max(unten, y)
    }
}

guard rechts > links else { abbruch("no coin found in \(quelle.lastPathComponent)") }
let muenzeDurchmesser = Double(max(rechts - links, unten - oben) + 1)
let muenzeMitteX = Double(links + rechts) / 2
let muenzeMitteY = Double(hoehe) - Double(oben + unten) / 2 // Core Graphics counts from below

// MARK: - The 1024 master

let farbraum = CGColorSpace(name: CGColorSpace.sRGB)!
let kontext = CGContext(
    data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8,
    bytesPerRow: 0, space: farbraum,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
kontext.interpolationQuality = .high

let kachel = CGRect(
    x: (canvas - kachelGroesse) / 2, y: (canvas - kachelGroesse) / 2,
    width: kachelGroesse, height: kachelGroesse
)
let kachelPfad = CGPath(
    roundedRect: kachel, cornerWidth: kachelRadius, cornerHeight: kachelRadius, transform: nil
)

// Tile plus the soft shadow Apple bakes into its own icons: it reaches about
// 32 px sideways and 44 px below the tile on the 1024 canvas.
kontext.saveGState()
kontext.setShadow(
    offset: CGSize(width: 0, height: -12), blur: 25,
    color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35)
)
kontext.addPath(kachelPfad)
kontext.setFillColor(hintergrund)
kontext.fillPath()
kontext.restoreGState()

// Everything below stays inside the tile.
kontext.saveGState()
kontext.addPath(kachelPfad)
kontext.clip()

let skala = muenzeAnteil * kachelGroesse / muenzeDurchmesser
let kante = Double(breite) * skala
let bildRahmen = CGRect(
    x: canvas / 2 - muenzeMitteX * skala,
    y: canvas / 2 + optischerVersatz * kachelGroesse - muenzeMitteY * skala,
    width: kante, height: Double(hoehe) * skala
)
kontext.draw(bild, in: bildRahmen)

// Fade the artwork's border into the tile so no edge can ever show. The border
// is the same white as the tile, so this is invisible but makes it certain.
let saum = kante * saumAnteil
let verlauf = CGGradient(
    colorsSpace: farbraum,
    colors: [hintergrund, hintergrund.copy(alpha: 0)!] as CFArray,
    locations: [0, 1]
)!
for (von, bis) in [
    (CGPoint(x: bildRahmen.minX, y: 0), CGPoint(x: bildRahmen.minX + saum, y: 0)),
    (CGPoint(x: bildRahmen.maxX, y: 0), CGPoint(x: bildRahmen.maxX - saum, y: 0)),
    (CGPoint(x: 0, y: bildRahmen.minY), CGPoint(x: 0, y: bildRahmen.minY + saum)),
    (CGPoint(x: 0, y: bildRahmen.maxY), CGPoint(x: 0, y: bildRahmen.maxY - saum))
] {
    kontext.drawLinearGradient(verlauf, start: von, end: bis, options: [
        .drawsBeforeStartLocation, .drawsAfterEndLocation
    ])
}

kontext.restoreGState()

guard let master = kontext.makeImage() else { abbruch("cannot render the icon") }

// MARK: - Asset catalog

func schreibe(_ bild: CGImage, _ kanten: Int, nach datei: URL) {
    let klein: CGImage
    if kanten == bild.width {
        klein = bild
    } else {
        let kontext = CGContext(
            data: nil, width: kanten, height: kanten, bitsPerComponent: 8,
            bytesPerRow: 0, space: farbraum,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        kontext.interpolationQuality = .high
        kontext.draw(bild, in: CGRect(x: 0, y: 0, width: kanten, height: kanten))
        klein = kontext.makeImage()!
    }
    guard let senke = CGImageDestinationCreateWithURL(
        datei as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { abbruch("cannot write \(datei.path)") }
    CGImageDestinationAddImage(senke, klein, nil)
    guard CGImageDestinationFinalize(senke) else { abbruch("cannot write \(datei.path)") }
}

try? FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)

struct Eintrag {
    let punkte: Int
    let faktor: Int
    var kanten: Int {
        punkte * faktor
    }

    var datei: String {
        "icon_\(punkte)x\(punkte)\(faktor == 2 ? "@2x" : "").png"
    }
}

let eintraege = [16, 32, 128, 256, 512].flatMap { punkte in
    [1, 2].map { Eintrag(punkte: punkte, faktor: $0) }
}

for eintrag in eintraege {
    schreibe(master, eintrag.kanten, nach: ziel.appendingPathComponent(eintrag.datei))
}

let bilder = eintraege.map { eintrag in
    """
        {
          "filename" : "\(eintrag.datei)",
          "idiom" : "mac",
          "scale" : "\(eintrag.faktor)x",
          "size" : "\(eintrag.punkte)x\(eintrag.punkte)"
        }
    """
}

let inhalt = """
{
  "images" : [
\(bilder.joined(separator: ",\n"))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try! inhalt.write(
    to: ziel.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8
)

// Previews, when a directory is given as the second argument.
if CommandLine.arguments.count > 2 {
    let vorschau = URL(fileURLWithPath: CommandLine.arguments[2])
    try? FileManager.default.createDirectory(at: vorschau, withIntermediateDirectories: true)
    schreibe(master, 1024, nach: vorschau.appendingPathComponent("preview-1024.png"))
    schreibe(master, 128, nach: vorschau.appendingPathComponent("preview-128.png"))
}

print("AppIcon.appiconset: \(eintraege.count) files, tile \(Int(kachelGroesse)) px, "
    + "coin \(Int(muenzeAnteil * 100)) % of the tile")
