//
//  NSArrayExtensions.swift
//  JSONPatch
//
//  Created by Ricardo Abreu on 10/12/2020.
//  Copyright © 2020 Raymond McCrae. All rights reserved.
//

import Foundation

extension NSArray {

    func deepMutableCopy() -> NSMutableArray {
        let result = NSMutableArray(capacity: count)

        for element in self {
            switch element {
            case let array as NSArray:
                result.add(array.deepMutableCopy())
            case let dict as NSDictionary:
                result.add(dict.deepMutableCopy())
            case let str as NSMutableString:
                result.add(str.mutableCopy())
            case let obj as NSObject:
                result.add(obj.copy())
            default:
                result.add(element)
            }
        }

        return result
    }

    func toJSONElementArray() -> [JSONElement] {
        var result = [JSONElement]()
        self.forEach { element in
            if let jsonElement = try? JSONElement(any: element) {
                result.append(jsonElement)
            }
        }
        return result
    }
}
