#!/usr/bin/env python3
"""Execute actual checklist scope/signature Swift methods with lightweight model/UI stand-ins.

This portable regression check does not build the UIKit app or replace hosted tests.
Run: python3 Scripts/test-checklist-batch-policy.py [path-to-swift]
"""
from pathlib import Path
import subprocess, os, sys, shutil, tempfile
root=Path(__file__).resolve().parents[1]
swift=sys.argv[1] if len(sys.argv)>1 else shutil.which('swift')
if not swift:
    sys.exit('Swift is required; pass the path to swift as the first argument.')
vc=(root/'RentnKing/Modules/TABBAR/Home Model/Order Model/Check List/CheckListViewController.swift').read_text()
uvc=(root/'RentnKing/Modules/TABBAR/Home Model/Order Model/Check List/CheckListUpdateViewController.swift').read_text()
def extract(src, marker):
    start=src.index(marker); brace=src.index('{',start); depth=1; end=brace+1
    while depth:
        depth += (src[end]=='{')-(src[end]=='}'); end+=1
    return src[start:end]
code='''import Foundation
struct Question { var type = "choice"; var startHours: Float = 0; var endHours: Float = 0; var startCleaning = ""; var endCleaning = ""; var selectFuleDelivery = ""; var selectFuleReturn = ""; var deliverAnswer: String?; var returnAnswer: String? }
struct ProductModel { var unique_id: String?; var is_delivered: Bool?; var is_returned: Bool?; var start_hours: Float = 0; var end_hours: Float = 0; var fuel_initial_reading = ""; var fuel_final_reading = ""; var startCleaning: Int?; var endCleaning: Int?; var arrQuestions: [Question] = [] }
struct OrdersModel { var arrProduct: [ProductModel] = [] }
struct UIImage: Equatable { var value = 0; var hasValidData: Bool { value > 0 } }
class NoteModel { var deliveryInputEntered = false; var returnInputEntered = false; var dNote = ""; var rNote = ""; var dSignature: UIImage?; var rSignature: UIImage?; var dSignatureUrl = ""; var rSignatureUrl = "" }
class EPSignatureViewController {}
struct AppUtility { static func PortraitMode() {} }
struct Context { var isCompleted: Bool }
class Entry { var checklistContexts: [String: Context] = [:]; var isDeliveryType = true
'''
for marker in ['func removeBlankProducts(', 'func checkQuestionsIsBlank(', 'func hasChecklistWork(', 'struct BlockedLine:', 'static func submitScope(']: code+=extract(vc,marker)+'\n'
code+='}\nextension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }\nclass Preview { var isDeliveryType = true; var isCombineChecklist = false; var arrOtherData: [NoteModel] = []; func renderFinalizationState() {} ; var tblView = Table()\n'
for marker in ['func hasSignature(', 'func hasCustomerSignature(', 'func epSignature(_: EPSignatureViewController, didSign']: code+=extract(uvc,marker)+'\n'
code+='''}
struct Table { func reloadData() {} }
var failures=0
func check(_ ok: Bool, _ message: String) { if !ok { failures+=1; print("FAIL: "+message) } else { print("PASS: "+message) } }
let entry=Entry()
for combine in [false,true] {
 let blank=Entry.BlockedLine(uniqueId:"C",hasMachine:true,isBlank:true)
 let partial=Entry.BlockedLine(uniqueId:"B",hasMachine:false,isBlank:false)
 let scope=Entry.submitScope(needingConnection:[blank,partial],combine:combine)
 check(scope.leftOut == ["C"] && scope.blocking == ["B"],"offline scope ignores untouched C, protects partial B; combine=\\(combine)")
}
for delivery in [false,true] {
 entry.isDeliveryType=delivery
 for count in 0...3 {
  var order: OrdersModel? = OrdersModel(arrProduct:(0..<3).map { i in ProductModel(unique_id:"P\\(i)",arrQuestions:[Question(deliverAnswer:delivery && i<count ? "Yes":nil,returnAnswer:!delivery && i<count ? "Yes":nil)]) })
  var other=(0..<3).map { _ in NoteModel() }
  entry.removeBlankProducts(objOrderData:&order,arrOtherData:&other)
  check(order?.arrProduct.count == count && other.count == count,"scope preserves aligned \\(count)-of-3; delivery=\\(delivery)")
 }
}
entry.isDeliveryType=true
var prefilled=ProductModel(unique_id:"DEFAULT",arrQuestions:[Question(type:"text",startHours:100),Question(type:"fuel",selectFuleDelivery:"8")])
prefilled.start_hours=100; prefilled.fuel_initial_reading="8"
let draftNote=NoteModel()
check(!entry.hasChecklistWork(product:prefilled,other:draftNote),"prefilled hours/fuel do not enroll untouched equipment")
draftNote.deliveryInputEntered=true
check(entry.hasChecklistWork(product:prefilled,other:draftNote),"explicit edits to defaults enroll equipment")
draftNote.deliveryInputEntered=false; draftNote.rNote="opposite leg only"
check(!entry.hasChecklistWork(product:prefilled,other:draftNote),"opposite-leg notes never enroll this checklist")
draftNote.dNote="partial delivery note"
check(entry.hasChecklistWork(product:prefilled,other:draftNote),"notes-only partial work stays in scope")
entry.checklistContexts["DEFAULT"]=Context(isCompleted:true)
check(!entry.hasChecklistWork(product:prefilled,other:draftNote),"completed checklist execution is excluded")
for delivery in [false,true] {
 for combine in [false,true] {
  let p=Preview(); p.isDeliveryType=delivery; p.isCombineChecklist=combine; p.arrOtherData=(0..<3).map { _ in NoteModel() }
  p.epSignature(EPSignatureViewController(),didSign:UIImage(value:1),boundingRect:.zero,strIndex:1)
  check(p.arrOtherData.enumerated().allSatisfy { i,n in (delivery ? n.dSignature:n.rSignature) == ((combine || i==1) ? UIImage(value:1):nil) },"signature targets only selected checklist in individual mode; delivery=\\(delivery), combine=\\(combine)")
  if !combine { check(!p.hasCustomerSignature(),"unsigned siblings block batch Submit; delivery=\\(delivery)") }
 }
 let p=Preview(); p.isDeliveryType=delivery; p.arrOtherData=(0..<3).map { _ in NoteModel() }
 if delivery { p.arrOtherData[2].dSignature=UIImage(value:2) } else { p.arrOtherData[2].rSignature=UIImage(value:2) }
 check(!p.hasCustomerSignature(),"last signature cannot satisfy other unsigned checklists; delivery=\\(delivery)")
}
exit(failures==0 ? 0:1)
'''
temporary=tempfile.TemporaryDirectory(prefix='kabba-checklist-policy-')
p=Path(temporary.name)/'main.swift'; p.write_text(code)
env=os.environ
res=subprocess.run([swift,str(p)],env=env)
temporary.cleanup()
sys.exit(res.returncode)
