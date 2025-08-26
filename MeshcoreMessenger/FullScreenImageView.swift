import SwiftUI

struct FullScreenImageView: View {
  @Binding var isPresented: Bool
  let imageData: Data

  var body: some View {
    ZStack {
      Color.black.edgesIgnoringSafeArea(.all)

      if let uiImage = UIImage(data: imageData) {
        Image(uiImage: uiImage)
          .resizable()
          .scaledToFit()
      }

      VStack {
        HStack {
          Spacer()
          Button(action: {
            self.isPresented = false
          }) {
            Image(systemName: "xmark.circle.fill")
              .font(.largeTitle)
              .foregroundColor(.white)
              .padding()
          }
        }
        Spacer()
      }
    }
  }
}
