import StoreKit

func loadProducts() async throws -> [Product] {
    try await Product.products(for: ["pro"])
}
