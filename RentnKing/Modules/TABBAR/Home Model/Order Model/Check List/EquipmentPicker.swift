//
//  EquipmentPicker.swift
//  RentnKing
//
//  Created by Jigar Khatri on 12/09/25.
//

import Foundation

import UIKit

//final class EquipmentPickerVC: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate {
//    let data = [
//          ("Section: Cutting", ["Brush cutting"]),
//          ("Section: Boom", ["Boom - Skid", "Boom-2"])
//      ]
//    
//    var pickerData: [String] = []
//
//    // 1) Your data
//    private let items = ["Brush cutting  ||  ATMQ-1234",
//                         "Boom - Skid    ||  ATT-GR-2",
//                         "Boom-2         ||  BTC-GR-5"]
//
//    // 2) UI
//    private let pickButton = UIButton(type: .system)
//    private let hiddenField = UITextField(frame: .zero)     // host for inputView/accessory
//    private let picker = UIPickerView()
//
//    private var selectedIndex: Int = 0 {
//        didSet { pickButton.setTitle(items[selectedIndex], for: .normal) }
//    }
//
//    override func viewDidLoad() {
//        super.viewDidLoad()
//        view.backgroundColor = .systemBackground
//        setupButton()
//        setupPickerHost()
//    }
//
//    private func setupButton() {
//        pickButton.translatesAutoresizingMaskIntoConstraints = false
//        pickButton.titleLabel?.numberOfLines = 1
//        pickButton.titleLabel?.adjustsFontSizeToFitWidth = true
//        pickButton.setTitle("Select Equipment ID", for: .normal)
//        pickButton.addTarget(self, action: #selector(openPicker), for: .touchUpInside)
//        view.addSubview(pickButton)
//
//        NSLayoutConstraint.activate([
//            pickButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
//            pickButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
//            pickButton.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
//            pickButton.heightAnchor.constraint(equalToConstant: 44)
//        ])
//    }
//
//    private func setupPickerHost() {
//        // Flatten data
//        for (section, items) in data {
//            pickerData.append(section)
//            pickerData.append(contentsOf: items)
//        }
//        
//        // Picker
//        picker.dataSource = self
//        picker.delegate = self
//
//        // Hidden text field as first responder host
//        hiddenField.translatesAutoresizingMaskIntoConstraints = false
//        hiddenField.isHidden = true
//        view.addSubview(hiddenField)
//
//        // Input view & accessory (toolbar)
//        hiddenField.inputView = picker
//        hiddenField.inputAccessoryView = makeToolbar()
//    }
//
//    private func makeToolbar() -> UIToolbar {
//        let bar = UIToolbar()
//        bar.sizeToFit()
//
//        let cancel = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))
//        let flex   = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
//        let title  = UIBarButtonItem(title: "Select Equipment ID", style: .plain, target: nil, action: nil)
//        title.isEnabled = false
//        let done   = UIBarButtonItem(title: "Select", style: .done, target: self, action: #selector(doneTapped))
//
//        bar.items = [cancel, flex, title, flex, done]
//        return bar
//    }
//
//    // MARK: - Actions
//    @objc  func openPicker() {
//        // Preselect current value when reopening
//        picker.selectRow(selectedIndex, inComponent: 0, animated: false)
//        hiddenField.becomeFirstResponder()  // shows picker + toolbar
//    }
//
//    @objc private func cancelTapped() {
//        hiddenField.resignFirstResponder()  // dismiss without applying
//    }
//
//    @objc private func doneTapped() {
//        selectedIndex = picker.selectedRow(inComponent: 0)
//        hiddenField.resignFirstResponder()  // apply & dismiss
//    }
//
//    // MARK: - UIPickerViewDataSource/Delegate
//    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
//
////    func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
////        // Styled cell similar to your screenshot
////        let label = (view as? UILabel) ?? UILabel()
////        label.textAlignment = .center
////        label.font = UIFont.preferredFont(forTextStyle: .body)
////        label.textColor = .label
////        label.text = items[row]
////        return label
////    }
//
//    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { 44 }
//    
//    
//    
//    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
//        return pickerData.count
//    }
//    
//       func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
//           let text = pickerData[row]
//           
//           // If it's a "section" row
//           if text.hasPrefix("Section:") {
//               return NSAttributedString(string: text.replacingOccurrences(of: "Section:", with: ""), attributes: [
//                   .font: UIFont.boldSystemFont(ofSize: 16),
//                   .foregroundColor: UIColor.gray
//                    
//               ])
//           }
//           
//           return NSAttributedString(string: text, attributes: [
//               .font: UIFont.systemFont(ofSize: 16),
//               .foregroundColor: UIColor.redText
//           ])
//       }
//       
//       // Prevent selecting section rows
//       func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
//           if pickerData[row].hasPrefix("Section:") {
//               // Jump to next selectable row
//               pickerView.selectRow(row + 1, inComponent: component, animated: true)
//           }
//       }
//}
