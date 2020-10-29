//
//  ProfileEditView.swift
//  HalloApp
//
//  Created by Alan Luo on 5/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import SwiftUI

private struct ProfilePictureView: UIViewRepresentable {

    typealias UIViewType = AvatarView

    private let userId: UserID

    init(userId: UserID) {
        self.userId = userId
    }

    func makeUIView(context: Context) -> AvatarView {
        let avatarView = AvatarView()
        avatarView.configure(with: self.userId, using: MainAppContext.shared.avatarStore)
        return avatarView
    }

    func updateUIView(_ uiView: AvatarView, context: Context) { }
}

struct ProfileEditView: View {
    var dismiss: (() -> ())?
    
    @State private var profileImageInput: UIImage?
    @State private var profileName = MainAppContext.shared.userData.name
    @State private var showingImageMenu = false
    @State private var showingImagePicker = false
    @State private var showingImageDeleteConfirm = false
    @State private var userHasAvatar = !MainAppContext.shared.avatarStore.userAvatar(forUserId: MainAppContext.shared.userData.userId).isEmpty

    init(dismiss: (() -> ())? = nil) {
        self.dismiss = dismiss

        UITableView.appearance(whenContainedInInstancesOf: [ UIHostingController<ProfileEditView>.self ]).backgroundColor = .feedBackground
    }

    var body: some View {
        VStack {
            List {
                Section(header: Text("Your Photo")) {
                    Button(action: {
                        if !self.userHasAvatar {
                            self.showingImagePicker = true
                        } else {
                            self.showingImageMenu = true
                        }
                    }) {
                        ProfilePictureView(userId: MainAppContext.shared.userData.userId)
                            .frame(width: 60, height: 60)
                    }
                    .actionSheet(isPresented: self.$showingImageMenu) {
                        ActionSheet(title: Text("Edit Your Photo"), message: nil, buttons: [
                            .default(Text("Take or Choose Photo"), action: {
                                self.showingImagePicker = true
                            }),
                            .destructive(Text("Delete Photo"), action: {
                                self.showingImageDeleteConfirm = true
                            }),
                            .cancel()
                        ])
                    }
                    .sheet(isPresented: self.$showingImagePicker, onDismiss: uploadImage) {
                        ImagePickerNew(image: self.$profileImageInput)
                    }
                }

                Section(header: Text("Your Name")) {
                    HStack {
                        WrappedTextField(placeholder: "Your Name", text: $profileName, limit: 25)

                        Text("\(profileName.count)/25")
                            .foregroundColor(.gray)
                    }
                }

                Section(header: Text("Your Phone Number")) {
                    HStack {
                        Text(MainAppContext.shared.userData.formattedPhoneNumber)
                            .foregroundColor(.gray)
                    }
                }
            }
            .listStyle(GroupedListStyle())
            .actionSheet(isPresented: self.$showingImageDeleteConfirm) {
                ActionSheet(title: Text("Delete Your Photo"), message: nil, buttons: [
                    .destructive(Text("Confirm"), action: {
                        DDLogInfo("ProfileEditView/Done will remove user avatar")

                        self.userHasAvatar = false

                        MainAppContext.shared.avatarStore.save(avatarId: "", forUserId: MainAppContext.shared.userData.userId)

                        MainAppContext.shared.service.sendCurrentAvatarIfPossible()
                    }),
                    .cancel({
                        self.showingImageMenu = true
                    })
                ])
            }
        }
        .navigationBarTitle("Edit Profile", displayMode: .inline)
        .navigationBarItems(trailing:
            Button(action: {
                if (self.profileName != MainAppContext.shared.userData.name) {
                    DDLogInfo("ProfileEditView/Done will change user name")

                    MainAppContext.shared.userData.name = self.profileName
                    MainAppContext.shared.userData.save()

                    MainAppContext.shared.service.sendCurrentUserNameIfPossible()
                }
                if self.dismiss != nil {
                    self.dismiss!()
                }
            }) {
                Text("Done")
                    .fontWeight(.medium)
            }
            .disabled(profileName.isEmpty)
        )
    }
    
    func uploadImage() {
        guard let profileImageInput = profileImageInput else { return }
        
        guard let resizedImage = profileImageInput.fastResized(to: CGSize(width: AvatarStore.avatarSize, height: AvatarStore.avatarSize)) else {
            DDLogError("ProfileEditView/resizeImage error resize failed")
            
            return
        }

        userHasAvatar = true
        
        DDLogInfo("ProfileEditView/Done will change user avatar")
        
        MainAppContext.shared.avatarStore.save(image:resizedImage, forUserId: MainAppContext.shared.userData.userId, avatarId: "self")
        
        MainAppContext.shared.service.sendCurrentAvatarIfPossible()
    }
}

fileprivate struct ImagePickerNew: UIViewControllerRepresentable {
    typealias UIViewControllerType = UINavigationController

    @Environment(\.presentationMode) var presentationMode
    @Binding var image: UIImage?

    func makeUIViewController(context: Context) -> UINavigationController {
        let picker = MediaPickerViewController(filter: .image, multiselect: false, camera: true) { controller, media, cancel in
            if cancel || media.count == 0 {
                self.presentationMode.wrappedValue.dismiss()
            } else {
                let edit = MediaEditViewController(cropToCircle: true, mediaToEdit: media, selected: 0) { controller, media, index, cancel in
                    controller.dismiss(animated: true)

                    if !cancel && media.count > 0 {
                        self.image = media[0].image
                        self.presentationMode.wrappedValue.dismiss()
                    }
                }

                edit.modalPresentationStyle = .fullScreen
                controller.present(edit, animated: true)
            }
        }

        return UINavigationController(rootViewController: picker)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
    }
}

fileprivate struct WrappedTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let limit: Int
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.autocapitalizationType = .words
        textField.autocorrectionType = .no
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.returnKeyType = .done
        textField.text = text
        textField.textContentType = .name
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        // Set uiView.text to $text here will cause unexpected behavior
        // for some input modes (such as voice dictation, Chinese, Japanese, etc.)
    }
    
    func makeCoordinator() -> TextFieldCoordinator {
        return TextFieldCoordinator(text: $text, limit: limit)
    }
    
    class TextFieldCoordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        let limit: Int
        
        init(text: Binding<String>, limit: Int) {
            self._text = text
            self.limit = limit
        }
        
        func textFieldDidChangeSelection(_ textField: UITextField) {
            self.text = textField.text ?? ""
        }
        
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let currentText = textField.text ?? ""
            guard let stringRange = Range(range, in: currentText) else { return false }
            let updatedText = currentText.replacingCharacters(in: stringRange, with: string)
            return updatedText.count <= limit
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            let currentText = textField.text ?? ""
            if currentText.isEmpty {
                return false
            } else {
                textField.resignFirstResponder()
                return true
            }
        }
    }
}

struct ProfileEditView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileEditView()
    }
}
