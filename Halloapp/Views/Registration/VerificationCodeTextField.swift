//
//  VerificationCodeTextField.swift
//  HalloApp
//
//  Created by Vaishvi Patel on 5/27/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit

public class VerificationCodeTextField: UITextField {
    
    private var codeLabels: [UILabel] = []
    
    private lazy var stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.spacing = 8
        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fillEqually
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.isUserInteractionEnabled = false
        return stackView
    }()
    
    public override init(frame: CGRect){
        super.init(frame: frame)
        commonInit()
    }
    
    required public init?(coder: NSCoder){
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit(){
        translatesAutoresizingMaskIntoConstraints = false
        font = .systemFont(forTextStyle: .title3, weight: .regular, maximumPointSize: 28)
        heightAnchor.constraint(equalToConstant: 52).isActive = true
        textContentType = .oneTimeCode
        keyboardType = .numberPad
        backgroundColor = .clear
        textColor = .clear
        addTarget(self, action: #selector(textFieldChanged), for: .editingChanged)
        
        createStackView()
        addSubview(stackView)
        let constraints = [
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ]
        NSLayoutConstraint.activate(constraints)
    }
    
    private func createStackView() {
        for _ in 1...6 {
            makeDigitLabel()
        }

        beginAnimation(indx: 0)
    }

    private func makeDigitLabel() {
        let label = UILabel()
        label.backgroundColor = .textFieldBackground
        label.layer.cornerRadius = 5
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.layer.masksToBounds = true
        label.font = .systemFont(forTextStyle: .body)
        label.adjustsFontSizeToFitWidth = true
        label.text = ""

        let shadow = ShadowView()
        shadow.layer.cornerRadius = label.layer.cornerRadius
        shadow.layer.shadowColor = UIColor.black.withAlphaComponent(0.15).cgColor
        shadow.layer.shadowOffset = CGSize(width: 0, height: 1)
        shadow.layer.shadowRadius = 0.75
        shadow.layer.shadowOpacity = 1

        shadow.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: shadow.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: shadow.trailingAnchor),
            label.topAnchor.constraint(equalTo: shadow.topAnchor),
            label.bottomAnchor.constraint(equalTo: shadow.bottomAnchor),
        ])

        stackView.addArrangedSubview(shadow)
        codeLabels.append(label)
    }
    
    @objc
    private func textFieldChanged(_ sender: Any){
        let verificationCode = (self.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard verificationCode.count <= 6 else {
            return
        }
        for indx in 0 ..< 6 {
            if(indx < verificationCode.count){
                let codeIndx = verificationCode.index(verificationCode.startIndex, offsetBy: indx)
                codeLabels[indx].text = String(verificationCode[codeIndx])
                removeAnimation(indx: indx)
            }else if(indx == verificationCode.count){
                codeLabels[indx].text = ""
                beginAnimation(indx: indx)
            }else{
                codeLabels[indx].text = ""
                removeAnimation(indx: indx)
            }
        }
    }
    
    public override func caretRect(for position: UITextPosition) -> CGRect {
        let indx = text?.count ?? 0
        guard indx < stackView.arrangedSubviews.count else {
            return .zero
        }

        let viewFrame = self.stackView.arrangedSubviews[indx].frame
        let caretHeight = self.font?.pointSize ?? ceil(frame.height * 0.6)
        return CGRect(x: viewFrame.midX - 1, y: ceil((self.frame.height - caretHeight) / 2), width: 2, height: caretHeight)
    }
    
    private func beginAnimation(indx: Int){
        let view = self.stackView.arrangedSubviews[indx]
        let animation = UIViewPropertyAnimator(duration: 0.5, dampingRatio: 1, animations: {
            view.layer.transform = CATransform3DMakeScale(1.1, 1.1, 1.1)
            view.layer.shadowRadius = 4
        })

        animation.startAnimation()
    }
    
    private func removeAnimation(indx: Int){
        let view = self.stackView.arrangedSubviews[indx]
        let animation = UIViewPropertyAnimator(duration: 0.5, dampingRatio: 1, animations: {
            view.layer.transform = CATransform3DMakeScale(1, 1, 1)
            view.layer.shadowRadius = 1
        })
        animation.startAnimation()
    }
}
