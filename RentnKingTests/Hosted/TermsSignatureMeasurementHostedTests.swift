//
//  TermsSignatureMeasurementHostedTests.swift
//  RentnKingHostedTests — runs inside the RentnKing app (Simulator or device)
//
//  Measures REAL signature-pad output (the bundled signature_pad v5, the one
//  the web signing page also uses) on both signing canvases — the phone's
//  local page and the web page — at device pixel ratios 1–4, for a typical,
//  a heavy (25 fast strokes) and a dense (80 slow strokes over the whole pad)
//  signature, and a noisy one (every pixel noise, as a canvas read-back in a
//  privacy mode: it does not compress). The shared signature limits
//  (TermsSignatureImage / Laravel's SignatureImage) are derived from these
//  numbers; this test keeps them honest. Both pages cap the pad at
//  TermsSignatureImage.maxPadRatio (3): at ratios 1–3 every signature, the
//  noisy one included, passes the phone's check, and every drawn one stays at
//  least 4× inside the decoded-size limit; ratio 4 is measured UNCAPPED, to
//  prove the cap is needed — its noisy signature is refused.
//

import XCTest
import WebKit
import UIKit
@testable import RentnKing

final class TermsSignatureMeasurementHostedTests: XCTestCase {

    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    private func js(_ webView: WKWebView, _ script: String, file: StaticString = #filePath, line: UInt = #line) -> Any? {
        let done = expectation(description: "js")
        var out: Any?
        webView.evaluateJavaScript(script) { value, error in
            if let error = error { XCTFail("JS failed: \(error)", file: file, line: line) }
            out = value
            done.fulfill()
        }
        wait(for: [done], timeout: 120)
        return out
    }

    private func load(_ html: String) -> WKWebView {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 1000))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.addSubview(webView)
        window.makeKeyAndVisible()
        self.window = window
        webView.loadHTMLString(html, baseURL: nil)
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if (js(webView, "document.readyState === 'complete' && typeof window.SignaturePad === 'function'") as? Bool) == true { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return webView
    }

    /// Seeded strokes (deterministic): `strokes` strokes of `points` points each, 16 ms apart.
    private static let strokesJS = """
        function kabbaStrokes(strokes, points, width, height, seed, step) {
          var s = seed; function r() { s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648; }
          var groups = [], t = 1;
          for (var i = 0; i < strokes; i++) {
            var x = r() * width, y = r() * height, list = [];
            for (var j = 0; j < points; j++) {
              x = Math.min(width - 2, Math.max(2, x + (r() - 0.5) * width / step));
              y = Math.min(height - 2, Math.max(2, y + (r() - 0.5) * height / (step / 2)));
              list.push({x: x, y: y, pressure: 0.5, time: t}); t += 16;
            }
            groups.push({points: list}); t += 200;
          }
          return groups;
        }
        """

    private struct Sample { let canvas: String; let ratio: Int; let kind: String; let width: Int; let height: Int; let encoded: Int; let decoded: Int; let dataURL: String }

    private func measure(page: String, canvas: String, cssWidth: Int, cssHeight: Int) -> [Sample] {
        var samples: [Sample] = []
        for ratio in 1...4 {
            let webView = load(page)
            let script = Self.strokesJS + """
                Object.defineProperty(window, 'devicePixelRatio', { get: function () { return \(ratio); } });
                var c = document.getElementById('signature-pad');
                c.width = c.offsetWidth * \(ratio); c.height = c.offsetHeight * \(ratio); c.getContext('2d').scale(\(ratio), \(ratio));
                var pad = new window.SignaturePad(c, { backgroundColor: 'rgba(255,255,255,1)', penColor: 'rgb(0,0,0)' });
                var out = [];
                function sample(kind) {
                  var url = pad.toDataURL('image/png');
                  var b64 = url.slice('data:image/png;base64,'.length);
                  var pad0 = (b64.match(/=+$/) || [''])[0].length;
                  out.push([kind, c.width, c.height, url.length, b64.length / 4 * 3 - pad0, url]);
                }
                // typical: a signature's few slow strokes; heavy: 25 fast strokes; dense: 80 slow, wide
                // strokes over the whole pad (the worst drawn case: antialiased edges everywhere).
                [['typical', 3, 60, 20], ['heavy', 25, 80, 6], ['dense', 80, 150, 40]].forEach(function (k) {
                  pad.fromData(kabbaStrokes(k[1], k[2], c.offsetWidth, c.offsetHeight, 7, k[3]));
                  sample(k[0]);
                });
                // noisy: every pixel random (opaque, as the pad's white background is) — WebKit's own
                // PNG encoder on an incompressible canvas, the worst case for size.
                var ctx = c.getContext('2d'), img = ctx.createImageData(c.width, c.height), x = 7; // xorshift32: incompressible
                for (var i = 0; i < img.data.length; i++) { x ^= x << 13; x ^= x >>> 17; x ^= x << 5; x >>>= 0; img.data[i] = i % 4 === 3 ? 255 : x & 255; }
                ctx.putImageData(img, 0, 0);
                sample('noisy');
                JSON.stringify(out);
                """
            let raw = js(webView, script) as? String ?? "[]"
            let rows = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [[Any]] ?? []
            for row in rows {
                samples.append(Sample(canvas: canvas, ratio: ratio, kind: row[0] as? String ?? "",
                                      width: (row[1] as? NSNumber)?.intValue ?? 0, height: (row[2] as? NSNumber)?.intValue ?? 0,
                                      encoded: (row[3] as? NSNumber)?.intValue ?? 0, decoded: (row[4] as? NSNumber)?.intValue ?? 0,
                                      dataURL: row[5] as? String ?? ""))
            }
            XCTAssertEqual(js(webView, "document.getElementById('signature-pad').offsetWidth") as? Int, cssWidth, canvas)
            XCTAssertEqual(js(webView, "document.getElementById('signature-pad').offsetHeight") as? Int, cssHeight, canvas)
        }
        return samples
    }

    private func signaturePad() throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "signature_pad.umd.min", withExtension: "js"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testMeasureRealSignaturePadOutput() throws {
        let pad = try signaturePad()
        // The phone's local page geometry: .signature-pad { width: 100%; height: 160px } in a 480px card, 16px padding.
        let local = "<!DOCTYPE html><html><head><meta name=viewport content='width=device-width, initial-scale=1'></head><body style='margin:0'>"
            + "<div style='max-width:480px;padding:16px;box-sizing:border-box'><canvas id='signature-pad' style='display:block;width:100%;height:160px;box-sizing:content-box;border:0'></canvas></div>"
            + "<script>\(pad)</script></body></html>"
        // The web page geometry: canvas.w-full.h-32 in max-w-md (448px) with p-6 (24px) padding.
        let web = "<!DOCTYPE html><html><head><meta name=viewport content='width=device-width, initial-scale=1'></head><body style='margin:0'>"
            + "<div style='max-width:448px;padding:24px;box-sizing:border-box'><canvas id='signature-pad' style='display:block;width:100%;height:128px;border:0'></canvas></div>"
            + "<script>\(pad)</script></body></html>"
        let samples = measure(page: local, canvas: "local", cssWidth: 448, cssHeight: 160)
            + measure(page: web, canvas: "web", cssWidth: 400, cssHeight: 128)
        for s in samples {
            print("P5-SIGNATURE-MEASURE canvas=\(s.canvas) ratio=\(s.ratio) kind=\(s.kind) px=\(s.width)x\(s.height) encoded=\(s.encoded) decoded=\(s.decoded)")
        }
        XCTAssertEqual(samples.count, 32)

        for s in samples {
            let label = "\(s.canvas) ratio \(s.ratio) \(s.kind)"
            guard s.ratio <= TermsSignatureImage.maxPadRatio else {
                // Uncapped (neither page draws at 4): the noisy signature is over the size limit.
                if s.kind == "noisy" {
                    XCTAssertNil(TermsAndConditionViewController.signaturePNG(fromDataURL: s.dataURL), label)
                    XCTAssertGreaterThan(s.decoded, TermsSignatureImage.maxDecodedBytes, label)
                }
                continue
            }
            // The real format passes the phone's check (and so the server's shared contract).
            XCTAssertNotNil(TermsAndConditionViewController.signaturePNG(fromDataURL: s.dataURL), label)
            XCTAssertLessThanOrEqual(s.decoded * (s.kind == "noisy" ? 1 : 4), TermsSignatureImage.maxDecodedBytes, "\(label): size headroom")
            XCTAssertLessThanOrEqual(s.encoded * (s.kind == "noisy" ? 1 : 4), TermsSignatureImage.maxEncodedLength, "\(label): encoded headroom")
            XCTAssertLessThanOrEqual(s.width * 3, TermsSignatureImage.maxWidth, "\(label): width headroom")
            XCTAssertLessThanOrEqual(s.height * 4, TermsSignatureImage.maxHeight, "\(label): height headroom")
            XCTAssertLessThanOrEqual(s.width * s.height * 6, TermsSignatureImage.maxPixels, "\(label): pixel headroom")
        }
        // One real web-page signature (ratio 1, typical) for the shared fixture's valid vectors.
        if let sample = samples.first(where: { $0.canvas == "web" && $0.ratio == 1 && $0.kind == "typical" }) {
            print("P5-SIGNATURE-SAMPLE \(sample.dataURL)")
        }
    }

    /// The phone's REAL signing page (TermsSigningShell) draws the pad at a pixel ratio of at most
    /// TermsSignatureImage.maxPadRatio — a 4× display or zoom draws at 3, below 1 at 1 — and a
    /// noisy signature on its largest canvas (448×160 CSS px, capped) still passes the phone's check.
    func testThePhonePageCapsThePadRatioAndItsNoisiestSignatureFits() throws {
        let entries = [TermsAgreement.Entry(isGlobal: true, content: "<p>Standard terms.</p>[customer_approval][/customer_approval]", signatureBlock: "")]
        let agreement = TermsAgreement(identity: TermsAgreement.computeIdentity(orderUniqueId: "ORD-RATIO", customerName: "Jane", entries: entries),
                                       orderUniqueId: "ORD-RATIO", orderNumber: "#1", customerName: "Jane", approvalsRequired: 1, entries: entries)
        let webView = load(try XCTUnwrap(TermsSigningShell.html(for: agreement)))
        let size = "var c = document.getElementById('signature-pad'); JSON.stringify([c.width, c.height, c.offsetWidth, c.offsetHeight])"

        for (index, (ratio, drawn)) in [(0.5, 1), (1, 1), (2, 2), (3, 3), (4, 3), (10, 3)].enumerated() {
            _ = js(webView, "Object.defineProperty(window, 'devicePixelRatio', { configurable: true, get: function () { return \(ratio); } }); true;")
            // The first open sizes the pad; afterwards the page re-sizes it on resize.
            _ = js(webView, index == 0 ? "document.getElementById('open-signature-btn').click(); true;" : "window.dispatchEvent(new Event('resize')); true;")
            let dims = (try? JSONSerialization.jsonObject(with: Data((js(webView, size) as? String ?? "[]").utf8))) as? [Int] ?? []
            XCTAssertEqual(dims.count, 4, "ratio \(ratio)")
            guard dims.count == 4 else { continue }
            XCTAssertEqual([dims[2], dims[3]], [448, 160], "the largest phone canvas")
            XCTAssertEqual([dims[0], dims[1]], [dims[2] * drawn, dims[3] * drawn], "ratio \(ratio) draws at \(drawn)")
        }

        // At ratio 10 (capped at 3): a drawn signature and a noise-filled one both pass the phone's check.
        let drawn = js(webView, "window.kabbaTerms.pad.fromData([{points: [{x: 20, y: 30, pressure: 0.5, time: 1}, {x: 90, y: 70, pressure: 0.5, time: 20}, {x: 160, y: 40, pressure: 0.5, time: 40}]}]); window.kabbaTerms.pad.toDataURL('image/png')") as? String ?? ""
        let noisy = js(webView, """
            var c = document.getElementById('signature-pad'), ctx = c.getContext('2d'), img = ctx.createImageData(c.width, c.height), x = 11;
            for (var i = 0; i < img.data.length; i++) { x ^= x << 13; x ^= x >>> 17; x ^= x << 5; x >>>= 0; img.data[i] = i % 4 === 3 ? 255 : x & 255; }
            ctx.putImageData(img, 0, 0); c.toDataURL('image/png');
            """) as? String ?? ""
        for (kind, url) in [("drawn", drawn), ("noisy", noisy)] {
            let png = try XCTUnwrap(TermsAndConditionViewController.signaturePNG(fromDataURL: url), kind)
            guard case .success(let dims) = TermsSignatureImage.inspect(png) else { XCTFail(kind); continue }
            XCTAssertEqual([dims.width, dims.height], [448 * 3, 160 * 3], kind)
            print("P5-SIGNATURE-PHONE-PAGE ratio=10 kind=\(kind) px=\(dims.width)x\(dims.height) decoded=\(png.count) limit=\(TermsSignatureImage.maxDecodedBytes)")
        }
    }

    /// The capture check refuses what the server refuses on form, base64, structure, size and
    /// dimensions. An image whose data only fails to DECODE is the server's check alone (GD):
    /// ImageIO renders corrupt PNG data without complaint, so the phone passes it and the server's
    /// refusal would park it as Needs Attention (kept, never counting).
    func testTheCaptureCheckRefusesEveryVectorTheServerRefuses() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KabbaSyncCore/Fixtures/terms_signature_image.json")
        let contract = try XCTUnwrap(JSONValue.parse(try Data(contentsOf: url)))
        for vector in try XCTUnwrap(contract["valid"]?.arrayValue) {
            XCTAssertNotNil(TermsAndConditionViewController.signaturePNG(fromDataURL: vector["data_url"]?.stringValue ?? ""),
                            vector["name"]?.stringValue ?? "?")
        }
        for vector in try XCTUnwrap(contract["invalid"]?.arrayValue) {
            let result = TermsAndConditionViewController.signaturePNG(fromDataURL: vector["value"]?.stringValue ?? "")
            if vector["reason"]?.stringValue == "undecodable" {
                XCTAssertNotNil(result, "decoding is the server's check alone")
            } else {
                XCTAssertNil(result, vector["name"]?.stringValue ?? "?")
            }
        }
    }
}
