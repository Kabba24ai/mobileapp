//
//  NoteList.swift
//  RentnKing
//
//  Created by Jigar Khatri on 11/08/25.
//

import UIKit


// MARK: - Model
//struct NoteItem {
//    let title: String
//    let createdAt: Date
//    let author: String
//}

// MARK: - Row View
final class NoteRowView: UIView {
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    private let bulletView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .label
        v.layer.cornerRadius = 3.5
        return v
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15, weight: .semibold)
        l.numberOfLines = 2
        return l
    }()

    private let metaLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12, weight: .regular)
        l.textColor = .secondaryLabel
        l.numberOfLines = 1
        return l
    }()

    private let editButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(named: "icon_edit"), for: .normal)
        b.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        NSLayoutConstraint.activate([
            b.widthAnchor.constraint(equalToConstant: 30),
            b.heightAnchor.constraint(equalToConstant: 30)
        ])
        return b
    }()

    private let deleteButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "trash"), for: .normal)
        b.tintColor = .secondary
        b.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        NSLayoutConstraint.activate([
            b.widthAnchor.constraint(equalToConstant: 30),
            b.heightAnchor.constraint(equalToConstant: 30   )
        ])
        return b
    }()

    private let hStack = UIStackView()
    private let textVStack = UIStackView()
    private let buttonStack = UIStackView()
    private let divider = UIView()


    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(bulletView)
        NSLayoutConstraint.activate([
            bulletView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bulletView.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            bulletView.widthAnchor.constraint(equalToConstant: 7),
            bulletView.heightAnchor.constraint(equalToConstant: 7)
        ])
        
        textVStack.axis = .vertical
        textVStack.spacing = 4
        textVStack.addArrangedSubview(titleLabel)
        textVStack.addArrangedSubview(metaLabel)
        
        buttonImageColor(btnImage: editButton, imageName: "icon_edit", colorHex: .secondary)
        buttonStack.axis = .horizontal
        buttonStack.alignment = .top
        buttonStack.spacing = 6
        buttonStack.addArrangedSubview(editButton)
        buttonStack.addArrangedSubview(deleteButton)
        
        hStack.axis = .horizontal
        hStack.alignment = .top
        hStack.spacing = 12
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.addArrangedSubview(textVStack)
        hStack.addArrangedSubview(UIView())
        hStack.addArrangedSubview(buttonStack)
        
        addSubview(hStack)
        NSLayoutConstraint.activate([
            hStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            hStack.leadingAnchor.constraint(equalTo: bulletView.trailingAnchor, constant: 8),
            hStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])
        
        divider.backgroundColor = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)
        NSLayoutConstraint.activate([
            divider.topAnchor.constraint(equalTo: textVStack.bottomAnchor, constant: 12),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
        
        editButton.addTarget(self, action: #selector(tapEdit), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(tapDelete), for: .touchUpInside)
    }

    func configure(with item: OrderNoteModel) {
        titleLabel.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: item.note ?? "")
        metaLabel.configureLable(textColor: .lightGray, fontName: GlobalMainConstants.APP_FONT_Roboto_Light, fontSize: 12.0, text: "Created \(item.created_at ?? "") by \(item.created_by ?? "")")
        metaLabel.numberOfLines = 2
    }

    @objc private func tapEdit() { onEdit?() }
    @objc private func tapDelete() { onDelete?() }
}
