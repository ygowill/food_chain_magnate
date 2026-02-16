import Foundation
import PDFKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct Options {
	var targetWidth: Int = 1600
	var prefix: String = "page_"
	var pad: Int = 3
	var format: String = "png" // png|jpg
	var quality: Double = 0.9 // jpg only
	var force: Bool = false
	var verbose: Bool = true
}

func usage() -> Never {
	fputs(
		"""
		Usage:
		  render_pdf_pages.swift <input_pdf> <output_dir> [options]

		Options:
		  --width <px>        Target pixel width (default: 1600)
		  --prefix <str>      Output filename prefix (default: page_)
		  --pad <n>           Page number zero-padding (default: 3)
		  --format png|jpg    Output format (default: png)
		  --quality <0..1>    JPG quality (default: 0.9)
		  --force             Overwrite existing files
		  --quiet             Less output

		Output filenames:
		  <prefix><pageNumber>.<ext>  (pageNumber is 1-based)
		""",
		stderr
	)
	exit(2)
}

func parseArgs(_ args: [String]) -> (String, String, Options) {
	if args.count < 3 {
		usage()
	}

	let inputPath = args[1]
	let outputDir = args[2]
	var opt = Options()

	var i = 3
	while i < args.count {
		let a = args[i]
		switch a {
		case "--width":
			guard i + 1 < args.count, let v = Int(args[i + 1]), v > 0 else { usage() }
			opt.targetWidth = v
			i += 2
		case "--prefix":
			guard i + 1 < args.count else { usage() }
			opt.prefix = args[i + 1]
			i += 2
		case "--pad":
			guard i + 1 < args.count, let v = Int(args[i + 1]), v >= 1, v <= 6 else { usage() }
			opt.pad = v
			i += 2
		case "--format":
			guard i + 1 < args.count else { usage() }
			let v = args[i + 1].lowercased()
			guard v == "png" || v == "jpg" || v == "jpeg" else { usage() }
			opt.format = (v == "jpeg") ? "jpg" : v
			i += 2
		case "--quality":
			guard i + 1 < args.count, let v = Double(args[i + 1]), v >= 0.0, v <= 1.0 else { usage() }
			opt.quality = v
			i += 2
		case "--force":
			opt.force = true
			i += 1
		case "--quiet":
			opt.verbose = false
			i += 1
		default:
			usage()
		}
	}

	return (inputPath, outputDir, opt)
}

func ensureDir(_ path: String) throws {
	try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
}

func renderPage(_ page: PDFPage, targetWidth: Int) -> CGImage? {
	let bounds = page.bounds(for: .mediaBox)
	if bounds.width <= 1 || bounds.height <= 1 {
		return nil
	}

	let scale = CGFloat(targetWidth) / bounds.width
	let w = Int((bounds.width * scale).rounded())
	let h = Int((bounds.height * scale).rounded())
	if w <= 0 || h <= 0 {
		return nil
	}

	let colorSpace = CGColorSpaceCreateDeviceRGB()
	let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
	guard let ctx = CGContext(
		data: nil,
		width: w,
		height: h,
		bitsPerComponent: 8,
		bytesPerRow: 0,
		space: colorSpace,
		bitmapInfo: bitmapInfo
	) else {
		return nil
	}

	ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
	ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
	ctx.interpolationQuality = .high

	ctx.saveGState()
	ctx.scaleBy(x: scale, y: scale)
	ctx.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
	page.draw(with: .mediaBox, to: ctx)
	ctx.restoreGState()

	return ctx.makeImage()
}

func writeImage(_ image: CGImage, to url: URL, format: String, quality: Double) throws {
	let type: UTType
	var props: [CFString: Any] = [:]
	if format == "jpg" {
		type = .jpeg
		props[kCGImageDestinationLossyCompressionQuality] = quality
	} else {
		type = .png
	}

	guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
		throw NSError(domain: "render_pdf_pages", code: 1, userInfo: [NSLocalizedDescriptionKey: "CGImageDestinationCreateWithURL failed"])
	}
	CGImageDestinationAddImage(dest, image, props as CFDictionary)
	if !CGImageDestinationFinalize(dest) {
		throw NSError(domain: "render_pdf_pages", code: 2, userInfo: [NSLocalizedDescriptionKey: "CGImageDestinationFinalize failed"])
	}
}

let (inputPath, outputDir, opt) = parseArgs(CommandLine.arguments)
let inputURL = URL(fileURLWithPath: inputPath)

guard let doc = PDFDocument(url: inputURL) else {
	fputs("FAIL: could not open PDF: \(inputPath)\n", stderr)
	exit(1)
}

do {
	try ensureDir(outputDir)
} catch {
	fputs("FAIL: could not create output dir: \(outputDir)\n", stderr)
	exit(1)
}

let pageCount = doc.pageCount
if opt.verbose {
	print("PDF=\(inputPath) pages=\(pageCount) out=\(outputDir) width=\(opt.targetWidth) format=\(opt.format)")
}

var wrote = 0
for i in 0..<pageCount {
	guard let page = doc.page(at: i) else { continue }
	let pageNum = i + 1
	let numStr = String(format: "%0*d", opt.pad, pageNum)
	let ext = (opt.format == "jpg") ? "jpg" : "png"
	let outURL = URL(fileURLWithPath: outputDir).appendingPathComponent("\(opt.prefix)\(numStr).\(ext)")

	if !opt.force && FileManager.default.fileExists(atPath: outURL.path) {
		continue
	}

	guard let image = renderPage(page, targetWidth: opt.targetWidth) else {
		fputs("WARN: could not render page \(pageNum)\n", stderr)
		continue
	}

	do {
		try writeImage(image, to: outURL, format: opt.format, quality: opt.quality)
		wrote += 1
		if opt.verbose {
			print("wrote \(outURL.path)")
		}
	} catch {
		fputs("FAIL: write error page \(pageNum): \(error)\n", stderr)
		exit(1)
	}
}

if opt.verbose {
	print("done wrote=\(wrote)")
}
