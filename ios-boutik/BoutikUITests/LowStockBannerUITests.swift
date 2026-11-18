import XCTest

/// Sells the last unit of a product and checks that Vendre shows the low-stock
/// banner, and that the banner opens that product's detail page.
final class LowStockBannerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSellingLastUnitShowsBannerThatOpensProductDetail() throws {
        let app = XCUIApplication()
        // In-memory fixture: "Savon test", 1 paquet left, alert at 0. Real data is untouched.
        app.launchArguments = ["-uiTestLowStock"]
        app.launch()

        let sellTab = app.tabBars.buttons["Vendre"]
        XCTAssertTrue(sellTab.waitForExistence(timeout: 10), "Onglet Vendre introuvable")
        sellTab.tap()

        let banner = app.buttons["lowStockBanner.open"]
        XCTAssertFalse(banner.exists, "La bannière ne doit pas être visible avant la vente")

        // Add the product, pay in cash, validate.
        let product = app.buttons["sellProduct.Savon test"]
        XCTAssertTrue(product.waitForExistence(timeout: 5))
        product.tap()

        let pay = app.buttons["cartBar.pay"]
        XCTAssertTrue(pay.waitForExistence(timeout: 5))
        pay.tap()

        let validate = app.buttons["payment.validate"]
        XCTAssertTrue(validate.waitForExistence(timeout: 5))
        validate.tap()

        let newSale = app.buttons["sale.newSale"]
        XCTAssertTrue(newSale.waitForExistence(timeout: 5), "L'écran de vente réussie n'est pas apparu")
        newSale.tap()

        // Back in Vendre: the banner names the product that just ran out.
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "La bannière de stock bas n'est pas apparue")
        XCTAssertTrue(banner.label.contains("Savon test"), "Libellé inattendu : \(banner.label)")
        XCTAssertTrue(banner.label.contains("Épuisé"), "Libellé inattendu : \(banner.label)")

        // The banner links to the right product page.
        banner.tap()
        let detailName = app.staticTexts["productDetail.name"]
        XCTAssertTrue(detailName.waitForExistence(timeout: 5), "La fiche produit ne s'est pas ouverte")
        XCTAssertEqual(detailName.label, "Savon test")
        XCTAssertTrue(app.navigationBars["Savon test"].exists, "Titre de la fiche inattendu")
        XCTAssertFalse(banner.exists, "La bannière doit disparaître après ouverture")
    }
}
