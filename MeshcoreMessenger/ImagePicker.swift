//
//  ImagePicker.swift (compatible iOS 15)
//  MeshcoreMessenger
//

import SwiftUI
import UIKit

struct ImagePicker: UIViewControllerRepresentable {
  @Binding var selectedImageData: Data?
  @Environment(\.presentationMode) private var presentationMode

  class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    let parent: ImagePicker

    init(_ parent: ImagePicker) {
      self.parent = parent
    }

    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      if let uiImage = info[.originalImage] as? UIImage {
        // We compress the image here before passing its data back
        parent.selectedImageData = uiImage.jpegData(compressionQuality: 0.5)
      }
      parent.presentationMode.wrappedValue.dismiss()
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>)
    -> UIImagePickerController
  {
    let picker = UIImagePickerController()
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
}
