import SwiftUI

struct ProductThumb: View {
    let product: Product
    var size: CGFloat = 48
    var radius: CGFloat? = nil

    var body: some View {
        ZStack {
            if let data = product.photoData, let ui = UIImage(data: data) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else if let name = product.imageName, UIImage(named: name) != nil {
                Image(name).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color.gainSoft, Color.chip], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(String(product.name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.gain)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: radius ?? size * 0.28, style: .continuous))
    }
}

/// Full-width photo area used in product grid cards.
struct ProductPhoto: View {
    let product: Product
    var body: some View {
        Color.chip
            .overlay {
                if let data = product.photoData, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFill().allowsHitTesting(false)
                } else if let name = product.imageName, UIImage(named: name) != nil {
                    Image(name).resizable().scaledToFill().allowsHitTesting(false)
                } else {
                    ZStack {
                        LinearGradient(colors: [Color.gainSoft, Color.chip], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "shippingbox").font(.system(size: 34)).foregroundStyle(Color.gain.opacity(0.6))
                    }
                }
            }
            .clipped()
    }
}

struct ClientAvatar: View {
    let client: Client?
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            if let name = client?.imageName, UIImage(named: name) != nil {
                Image(name).resizable().scaledToFill()
            } else if let client {
                Color.gainSoft
                Text(client.initials).font(.system(size: size * 0.36, weight: .bold, design: .rounded)).foregroundStyle(Color.gain)
            } else {
                Color.gainSoft
                Image(systemName: "person").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(Color.gain)
            }
        }
        .frame(width: size, height: size)
        .clipShape(client?.imageName != nil ? AnyShape(Circle()) : AnyShape(.rect(cornerRadius: size * 0.3, style: .continuous)))
    }
}
