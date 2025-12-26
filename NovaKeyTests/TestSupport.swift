//
//  TestSupport.swift
//  NovaKeyTests
//
//  Created by Robert Osborne on 12/26/25.
//

import Foundation
import XCTest

enum TestSupport {

    static func tmpURL(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("novakey-tests-\(UUID().uuidString)-\(name)")
    }

    static func unixNow() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }
}
