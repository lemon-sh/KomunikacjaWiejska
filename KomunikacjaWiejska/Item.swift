//
//  Item.swift
//  KomunikacjaWiejska
//
//  Created by Lemon on 2026-11-05.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
