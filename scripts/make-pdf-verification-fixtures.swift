// Synthetic local verification inputs; run from the repository root. Existing files are preserved.
import Foundation
import CoreGraphics
import CoreText
import PDFKit
let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("CloakTools Files/PDF proof", isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
func makePDF(_ labels: [String], name: String, color: CGColor) throws {
    let output = folder.appendingPathComponent(name)
    guard !FileManager.default.fileExists(atPath: output.path) else { return }
    let data = NSMutableData()
    var rect = CGRect(x: 0,y: 0,width: 420,height: 595)
    let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &rect, nil)!
    for (index,label) in labels.enumerated() {
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1,alpha: 1));context.fill(rect)
        context.setFillColor(color);context.fill(CGRect(x: 0,y: 455,width:420,height:140))
        let strings:[(String,CGFloat,CGFloat,CGFloat)] = [("CloakTools",26,32,535),(label,23,32,395),("Native PDF assembly verification",12,32,360),("Page \(index+1) - original text remains selectable",11,32,65)]
        for (text,size,x,y) in strings {
            let attributes:[NSAttributedString.Key:Any] = [NSAttributedString.Key(kCTFontAttributeName as String):CTFontCreateWithName("Helvetica" as CFString,size,nil),NSAttributedString.Key(kCTForegroundColorAttributeName as String):CGColor(gray:y>455 ? 1:0.15,alpha:1)]
            context.textPosition=CGPoint(x:x,y:y)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:attributes)),context)
        }
        context.endPDFPage()
    }
    context.closePDF()
    try (data as Data).write(to:output,options:.withoutOverwriting)
}
try makePDF(["Project overview"],name:"01 Cover.pdf",color:CGColor(red:0.1,green:0.36,blue:0.83,alpha:1))
try makePDF(["Implementation notes","Verification results"],name:"02 Notes.pdf",color:CGColor(red:0.13,green:0.52,blue:0.41,alpha:1))
let image=folder.appendingPathComponent("03 Image.png")
if !FileManager.default.fileExists(atPath:image.path) { try FileManager.default.copyItem(at:URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("assets/icon/Previews/Default-512.png"),to:image) }
print(folder.path)
