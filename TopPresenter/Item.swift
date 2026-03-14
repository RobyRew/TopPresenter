//
//  Item.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
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
