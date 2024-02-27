//
//  Checkout.swift
//  RentnKing
//
//  Created by Jigar Khatri on 16/01/24.
//

import Foundation

struct Cart {
    var product: ProductModel
}

class Checkout: NSObject {
    
    static let shared: Checkout = Checkout()
    
    var cart: [Cart] = []

    var products: [ProductModel] = []{
        didSet{
            cart = []
            itemPrice = 0

            for product in products{
                
                if product.id != 0{
                    if let index = cart.firstIndex(where: { $0.product.id == product.id }){
                        cart[index].product = product
                    }
                    else{
                        let uniqueCart = Cart(product: product)
                        cart.append(uniqueCart)
                    }
                }
            }
            
            //GET OPRION PRICE
            var price: Double = 0.0
            var taxePrice: Double = 0.0
            for cartItem in cart{
                
                //GET PRICE
                let itemPrice = (cartItem.product.price ?? 0) * Float(cartItem.product.qty)
                
                //GET OPTIONS PRICES
                var optionsPrice : Double = 0.0
                for arrOptios in cartItem.product.options{
                    for valude in arrOptios.values{
                        if valude.type == true{
                            optionsPrice = optionsPrice + Double((valude.price ?? 0.0))
                        }
                    }
                }
                
                //ITEM PRICE
                price = Double(itemPrice) + (optionsPrice * Double(cartItem.product.qty))
                
                //GET TAXE PRICE
                var taxePercentage: Double = 0.0
                for objTaxe in cartItem.product.arrTaxes{
                    taxePercentage = taxePercentage + Double((objTaxe.percentage ?? 0.0))
                }
                taxePrice = taxePrice + (((price) * taxePercentage)/100)
            }

            itemPrice = itemPrice + price
            taxCharge = taxePrice

            
            //GET TAXES PERCENTAGE
//            var taxePercentage: Double = 0.0
//            for cartItem in cart{
//                for objTaxe in cartItem.product.arrTaxes{
//                    taxePercentage = taxePercentage + Double((objTaxe.percentage ?? 0.0))
//                }
//            }
//            tax = taxePercentage / Double(cart.count)
        }
    }
    
    var itemPrice = 0.0{
        didSet{
//            taxCharge = ((itemPrice) * tax)/100
            total = itemPrice + taxCharge + customeAmount
        }
    }
    
//    var tax = 0.0{
//        didSet{
//            taxCharge = ((itemPrice) * tax)/100
//            total = itemPrice + taxCharge
//        }
//    }
    
    var taxCharge = 0.0{
        didSet{
//            taxCharge = ((itemPrice) * tax)/100
            total = itemPrice + taxCharge + customeAmount
        }
    }
    
    var customeAmount = 0.0{
        didSet{
//            taxCharge = ((itemPrice) * tax)/100
            total = itemPrice + taxCharge + customeAmount
        }
    }
    
    var total = 0.0{
        didSet{
            var Pay = total
            if Pay < 0.0{
                Pay = 0.0
            }
            priceToPay = Pay
        }
    }
    
    var priceToPay = 0.0{
        didSet{
            NotificationCenter.default.post(name: .cartUpdated, object: nil)
        }
    }
    
    func addProductToCart(product: ProductModel, completionHandle: (Bool, ProductModel)->Void){
        
        if let index = Checkout.shared.products.firstIndex(where: { $0.id == product.id }){
            Checkout.shared.products.remove(at: index)
            Checkout.shared.products.insert(product, at: index)
        }
        else{
            products.append(product)
        }
        completionHandle(true, product)

    }
    
    func removeProductFromCart(product: ProductModel){
        
        if let index:Int = products.lastIndex(where: {$0.id == product.id}) {
            products.remove(at: index)
        }
    }
}

