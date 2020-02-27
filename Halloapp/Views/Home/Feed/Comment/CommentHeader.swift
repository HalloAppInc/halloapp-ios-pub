

import SwiftUI

struct CommentHeader: View {
    
    var comment: FeedDataItem
    
    @ObservedObject var contacts: Contacts
    
    
    var body: some View {
      
        VStack(spacing: 0) {

            
            HStack() {

                VStack (spacing: 0) {
                    Button(action: {
                        
                    }) {
                       
                        Image(systemName: "circle.fill")
                            .resizable()

                            .scaledToFit()

                            .clipShape(Circle())
                            .foregroundColor(Color.gray)

                            .frame(width: 30, height: 30, alignment: .center)
                            .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
  
                    }
                    
                    Spacer()
                }
                
                VStack(spacing: 0) {
                    HStack() {
                        
                        Text(self.contacts.getName(phone: comment.username))
                            .font(.system(size: 14, weight: .bold))
                        
                        +
                        
                        Text("   \(comment.text)")
                            .font(.system(size: 15, weight: .regular))
                        
                        Spacer()
                    }
                    HStack() {
                        Text(Utils().timeForm(dateStr: String(comment.timestamp)))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color.secondary)

                        Spacer()
                        
                    }
                    .padding(EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 0))
                    
                }
                
                Spacer()


            }
            
            
            Spacer()
            
            Divider()
                .padding(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
        }
      
        .padding(EdgeInsets(top: 65, leading: 0, bottom: 10, trailing: 0))
    
        
    }
    

}

