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
import YPImagePicker

struct ProfileEditView: View {
    var dismiss: (() -> ())?
    
    @ObservedObject private var name = TextWithLengthLimit(limit: 25, text: MainAppContext.shared.userData.name)
    
    @State private var profileImage: UIImage? = MainAppContext.shared.userData.avatar?.image
    @State private var profileImageInput: UIImage?
    @State private var showingImagePicker = false
    
    var body: some View {
        NavigationView {
            VStack {
                List {
                    Section(header: Text("Your Photo")) {
                        Button(action: {
                            self.showingImagePicker = true
                        }, label: {
                            if self.profileImage != nil {
                                Image(uiImage: profileImage!)
                                    .renderingMode(.original)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 70, height: 70)
                                    .cornerRadius(35)
                            } else {
                                Image(systemName: "person.crop.circle")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 70, height: 70)
                                    .foregroundColor(.gray)
                            }
                        }).sheet(isPresented: self.$showingImagePicker, onDismiss: uploadImage) {
                            ImagePicker(image: self.$profileImageInput)
                        }
                    }
                    
                    Section(header: Text("Your Name")) {
                        HStack {
                            TextField("Enter your name", text: $name.text)
                            
                            Text("\(name.text.count)/25")
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Section(header: Text("Your Phone Number")) {
                        HStack {
                            Text(MainAppContext.shared.userData.formattedPhoneNumber)
                                .foregroundColor(.gray)
                        }
                    }
                }.listStyle(GroupedListStyle())
            }.navigationBarTitle("Edit Profile", displayMode: .inline)
            .navigationBarItems(leading:
                HStack {
                    Button(action: {
                        if self.dismiss != nil {
                            self.dismiss!()
                        }
                    }) {
                        Text("Cancel")
                            .foregroundColor(Color("Tint"))
                    }
                }, trailing:
                HStack {
                    Button(action: {
                        if (self.name.text != MainAppContext.shared.userData.name) {
                            DDLogInfo("ProfileEditView/Done will change user name")
                            
                            MainAppContext.shared.userData.name = self.name.text
                            MainAppContext.shared.userData.save()
                            
                            MainAppContext.shared.xmppController.sendCurrentUserNameIfPossible()
                        }
                        
                        if self.dismiss != nil {
                            self.dismiss!()
                        }
                    }) {
                        Text("Done")
                            .fontWeight(.medium)
                            .foregroundColor(name.text == "" ? .gray : Color("Tint"))
                    }.disabled(name.text == "")
                    
                }
            )
        }
    }
    
    func uploadImage() {
        guard let profileImageInput = profileImageInput else { return }
        
        guard let resizedImage = profileImageInput.resized(to: CGSize(width: AvatarStore.avatarSize, height: AvatarStore.avatarSize)) else {
            DDLogError("ProfileEditView/resizeImage error resize failed")
            
            return
        }

        profileImage = resizedImage
        
        DDLogInfo("ProfileEditView/Done will change user avatar")
        
        AvatarStore.shared.save(image:resizedImage, forUserId: MainAppContext.shared.userData.userId, avatarId: "self")
        
        MainAppContext.shared.userData.reloadAvatar()
        
        MainAppContext.shared.xmppController.sendCurrentAvatarIfPossible()
    }
}

fileprivate class TextWithLengthLimit: ObservableObject {
    let limit: Int
    
    @Published var text: String {
        didSet {
            if text.count > limit {
                text = oldValue
            }
        }
    }
    
    init(limit: Int, text: String) {
        self.limit = limit
        self.text = text
    }
}

fileprivate struct ImagePicker: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode
    @Binding var image: UIImage?
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>) -> YPImagePicker {
        var config = YPImagePickerConfiguration()
        
        // General
        config.showsPhotoFilters = false
        config.shouldSaveNewPicturesToAlbum = false
        config.startOnScreen = .library
        config.usesFrontCamera = true
        
        
        // Library
        config.library.onlySquare = true
        
        
        let picker = YPImagePicker(configuration: config)
        
        picker.didFinishPicking { items, cancelled in
            guard !cancelled else {
                self.presentationMode.wrappedValue.dismiss()
                return
            }
            
            if let photo = items.singlePhoto {
                self.image = photo.image
            }
            
            self.presentationMode.wrappedValue.dismiss()
        }
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: YPImagePicker, context: Context) {
        
    }
}

struct ProfileEditView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileEditView()
    }
}
