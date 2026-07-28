import SwiftUI
import PhotosUI
import UIKit

/// カメラ。写真権限を拒否していても記録は続けられる。
struct CameraPicker: UIViewControllerRepresentable {
    var onPicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onPicked(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// 記録画面の写真枠。タップでカメラ／ライブラリを選ぶ。
struct PhotoInputTile: View {
    @Bindable var draft: ServingDraft
    @State private var showingCamera = false
    @State private var libraryItem: PhotosPickerItem?

    private var currentImage: UIImage? {
        if let newPhoto = draft.newPhoto { return newPhoto }
        if draft.removePhoto { return nil }
        return PhotoStore.shared.load(draft.existingPhotoID)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.secondary.opacity(0.08))
                if let image = currentImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "camera")
                            .font(.title2)
                        Text("写真（任意）")
                            .font(.caption)
                    }
                    .foregroundStyle(Theme.secondary.opacity(0.7))
                }
            }
            .frame(width: 112, height: 112)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )

            HStack(spacing: 8) {
                Button {
                    showingCamera = true
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "camera")
                        Text("撮る")
                    }
                    .font(.caption2.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
                }
                .buttonStyle(.bordered)

                PhotosPicker(selection: $libraryItem, matching: .images, photoLibrary: .shared()) {
                    VStack(spacing: 2) {
                        Image(systemName: "photo")
                        Text("選ぶ")
                    }
                    .font(.caption2.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
                }
                .buttonStyle(.bordered)
            }
            .frame(width: 112)

            if currentImage != nil {
                Button(role: .destructive) {
                    draft.newPhoto = nil
                    draft.removePhoto = true
                } label: {
                    Text("写真を外す").font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.primary)
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in
                draft.newPhoto = image
                draft.removePhoto = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: libraryItem) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        draft.newPhoto = image
                        draft.removePhoto = false
                    }
                }
            }
        }
    }
}
