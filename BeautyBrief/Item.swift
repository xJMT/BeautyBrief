//
//  Item.swift
//  BeautyBrief
//
//  Created by Jason Trifan on 21/5/2026.
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
