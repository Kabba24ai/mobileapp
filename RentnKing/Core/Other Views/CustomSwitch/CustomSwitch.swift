//
//  Untitled.swift
//  RentnKing
//
//  Created by Jigar Khatri on 11/03/26.
//

import UIKit

final class CustomSwitch: UIControl {
    
    // MARK: - Public Properties
    var isOn: Bool = false {
        didSet {
            updateUI(animated: true)
            sendActions(for: .valueChanged)
        }
    }
    
    var onTintColor: UIColor = .systemGreen {
        didSet { updateColors() }
    }
    
    var offTintColor: UIColor = UIColor.systemGray4 {
        didSet { updateColors() }
    }
    
    var thumbTintColor: UIColor = .white {
        didSet { thumbView.backgroundColor = thumbTintColor }
    }
    
    // MARK: - Private Views
    private let trackView = UIView()
    private let thumbView = UIView()
    
    private var thumbLeadingConstraint: NSLayoutConstraint!
    private var thumbTrailingConstraint: NSLayoutConstraint!
    
    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupGesture()
        updateUI(animated: false)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupGesture()
        updateUI(animated: false)
    }
    
    // MARK: - Setup
    private func setupUI() {
        backgroundColor = .clear
        
        trackView.translatesAutoresizingMaskIntoConstraints = false
        trackView.backgroundColor = offTintColor
        addSubview(trackView)
        
        thumbView.translatesAutoresizingMaskIntoConstraints = false
        thumbView.backgroundColor = thumbTintColor
        addSubview(thumbView)
        
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            widthAnchor.constraint(equalToConstant: 56),
            
            trackView.topAnchor.constraint(equalTo: topAnchor),
            trackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            trackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            trackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            thumbView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbView.widthAnchor.constraint(equalToConstant: 28),
            thumbView.heightAnchor.constraint(equalToConstant: 28)
        ])
        
        thumbLeadingConstraint = thumbView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2)
        thumbTrailingConstraint = thumbView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2)
        
        thumbLeadingConstraint.isActive = true
        
        layer.masksToBounds = false
        trackView.layer.masksToBounds = true
        thumbView.layer.masksToBounds = true
        
        thumbView.layer.shadowColor = UIColor.black.cgColor
        thumbView.layer.shadowOpacity = 0.15
        thumbView.layer.shadowOffset = CGSize(width: 0, height: 1)
        thumbView.layer.shadowRadius = 2
    }
    
    private func setupGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleState))
        addGestureRecognizer(tap)
    }
    
    // MARK: - Layout
    override func layoutSubviews() {
        super.layoutSubviews()
        trackView.layer.cornerRadius = bounds.height / 2
        thumbView.layer.cornerRadius = 14
    }
    
    // MARK: - Actions
    @objc private func toggleState() {
        isOn.toggle()
    }
    
    func setOn(_ on: Bool, animated: Bool) {
        isOn = on
        updateUI(animated: animated)
    }
    
    // MARK: - UI Update
    private func updateUI(animated: Bool) {
        thumbLeadingConstraint.isActive = !isOn
        thumbTrailingConstraint.isActive = isOn
        
        let changes = {
            self.trackView.backgroundColor = self.isOn ? self.onTintColor : self.offTintColor
            self.layoutIfNeeded()
        }
        
        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut]) {
                changes()
            }
        } else {
            changes()
        }
    }
    
    private func updateColors() {
        trackView.backgroundColor = isOn ? onTintColor : offTintColor
        thumbView.backgroundColor = thumbTintColor
    }
}



final class CustomSegmentedControl: UIView {

    enum Segment: Int {
        case today = 0
        case tomorrow
        case all
    }

    var selectedSegment: Segment = .today {
        didSet {
            updateSelection()
            valueChanged?(selectedSegment)
        }
    }

    var valueChanged: ((Segment) -> Void)?

    private let stackView = UIStackView()
    private let todayButton = UIButton(type: .system)
    private let tomorrowButton = UIButton(type: .system)
    private let allButton = UIButton(type: .system)

    private lazy var buttons: [UIButton] = [
        todayButton, tomorrowButton, allButton
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupButtons()
        updateSelection()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        setupButtons()
        updateSelection()
    }

    private func setupView() {
        backgroundColor = .clear

        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.distribution = .fillEqually
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    private func setupButtons() {
        configureButton(todayButton, title: "Today", tag: Segment.today.rawValue)
        configureButton(tomorrowButton, title: "Tomorrow", tag: Segment.tomorrow.rawValue)
        configureButton(allButton, title: "All", tag: Segment.all.rawValue)

        buttons.forEach { stackView.addArrangedSubview($0) }
    }

    private func configureButton(_ button: UIButton, title: String, tag: Int) {
        button.setTitle(title, for: .normal)
        button.tag = tag
        button.layer.cornerRadius = 10
        button.layer.borderWidth = 1
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        button.addTarget(self, action: #selector(segmentTapped(_:)), for: .touchUpInside)
    }

    @objc private func segmentTapped(_ sender: UIButton) {
        guard let segment = Segment(rawValue: sender.tag) else { return }
        selectedSegment = segment
    }

    private func updateSelection() {

        for button in buttons {
            let isSelected = button.tag == selectedSegment.rawValue

            button.backgroundColor = isSelected ? .secondary : UIColor.clear
            button.setTitleColor(isSelected ? .black : .secondary, for: .normal)
            button.layer.borderColor = UIColor.secondary.cgColor
        }
    }
}
