//
//  JSONPatchGenerator.swift
//  JSONPatch
//
//  Created by Raymond Mccrae on 30/11/2018.
//  Copyright © 2018 Raymond McCrae.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

struct JSONPatchGenerator {
    fileprivate enum Operation {
        case add(path: JSONPointer, value: JSONElement)
        case remove(path: JSONPointer, value: JSONElement)
        case replace(path: JSONPointer, old: JSONElement, value: JSONElement)
        case copy(from: JSONPointer, path: JSONPointer, value: JSONElement)
        case move(from: JSONPointer, old: JSONElement, path: JSONPointer, value: JSONElement)
        case test(path: JSONPointer, value: JSONElement)
    }

    private var identifiers = ["id"]
    private var unchanged: [JSONPointer: JSONElement] = [:]
    private var operations: [Operation] = []
    private var patchOperations: [JSONPatch.Operation] {
        return operations.map(JSONPatch.Operation.init)
    }

    static func generatePatch(source: JSONElement, target: JSONElement) throws -> [JSONPatch.Operation] {
        var generator = JSONPatchGenerator()
        try generator.computeUnchanged(pointer: JSONPointer.wholeDocument, a: source, b: target)
        try generator.generateDiffs(pointer: JSONPointer.wholeDocument, source: source, target: target)
        return generator.patchOperations
    }

    private mutating func computeUnchanged(pointer: JSONPointer, a: JSONElement, b: JSONElement) throws {
        guard a != b else {
            unchanged[pointer] = a
            return
        }

        switch (a, b) {
        case let (.object(dictA), .object(dictB)), let
            (.object(dictA), .mutableObject(dictB as NSDictionary)),
             (.mutableObject(let dictA as NSDictionary), .object(let dictB)),
             (.mutableObject(let dictA as NSDictionary), .mutableObject(let dictB as NSDictionary)):
            try computeObjectUnchanged(pointer: pointer, a: dictA, b: dictB)

        case let (.array(arrayA), .array(arrayB)), let
            (.array(arrayA), .mutableArray(arrayB as NSArray)),
             (.mutableArray(let arrayA as NSArray), .array(let arrayB)),
             (.mutableArray(let arrayA as NSArray), .mutableArray(let arrayB as NSArray)):
            try computeArrayUnchanged(pointer: pointer, a: arrayA, b: arrayB)

        default:
            break
        }
    }

    private mutating func computeObjectUnchanged(pointer: JSONPointer,
                                                 a: NSDictionary,
                                                 b: NSDictionary) throws {
        guard let keys = a.allKeys as? [String] else {
            return
        }

        for key in keys {
            guard let valueA = a[key], let valueB = b[key] else {
                continue
            }
            try computeUnchanged(pointer: pointer.appended(withComponent: key),
                                 a: try JSONElement(any: valueA),
                                 b: try JSONElement(any: valueB))
        }
    }

    private mutating func computeArrayUnchanged(pointer: JSONPointer,
                                                a: NSArray,
                                                b: NSArray) throws {
        let count = min(a.count, b.count)
        for index in 0 ..< count {
            try computeUnchanged(pointer: pointer.appended(withIndex: index),
                                 a: try JSONElement(any: a[index]),
                                 b: try JSONElement(any: b[index]))
        }
    }

    private mutating func generateDiffs(pointer: JSONPointer,
                                        source: JSONElement,
                                        target: JSONElement) throws {
        guard source != target else {
            return
        }

        guard JSONElement.equivalentTypes(lhs: source, rhs: target) else {
            replace(path: pointer, old: source, value: target)
            return
        }

        guard source.isContainer else {
            replace(path: pointer, old: source, value: target)
            return
        }

        switch (source, target) {
        case let (.object(dictA), .object(dictB)), let
            (.object(dictA), .mutableObject(dictB as NSDictionary)),
             (.mutableObject(let dictA as NSDictionary), .object(let dictB)),
             (.mutableObject(let dictA as NSDictionary), .mutableObject(let dictB as NSDictionary)):
            try generateObjectDiffs(pointer: pointer, source: dictA, target: dictB)

        case let (.array(arrayA), .array(arrayB)), let
            (.array(arrayA), .mutableArray(arrayB as NSArray)),
             (.mutableArray(let arrayA as NSArray), .array(let arrayB)),
             (.mutableArray(let arrayA as NSArray), .mutableArray(let arrayB as NSArray)):
            try generateArrayDiffs(path: pointer, source: arrayA, target: arrayB)

        default:
            break
        }
    }

    private mutating func generateObjectDiffs(pointer: JSONPointer,
                                              source: NSDictionary,
                                              target: NSDictionary) throws {
        guard
            let sourceKeys = source.allKeys as? [String],
            let targetKeys = target.allKeys as? [String] else {
            return
        }
        let sourceKeySet = Set(sourceKeys)
        let targetKeySet = Set(targetKeys)

        for key in sourceKeySet.subtracting(targetKeySet) {
            guard let value = source[key] else { continue }
            remove(path: pointer.appended(withComponent: key),
                   value: try JSONElement(any: value))
        }

        for key in targetKeySet.subtracting(sourceKeySet) {
            guard let value = target[key] else { continue }
            add(path: pointer.appended(withComponent: key),
                value: try JSONElement(any: value))
        }

        for key in sourceKeySet.intersection(targetKeySet) {
            guard let sourceValue = source[key], let targetValue = target[key] else {
                continue
            }
            try generateDiffs(pointer: pointer.appended(withComponent: key),
                              source: try JSONElement(any: sourceValue),
                              target: try JSONElement(any: targetValue))
        }
    }

    private mutating func generateArrayDiffs(path: JSONPointer,
                                             source s: NSArray,
                                             target t: NSArray) throws {
        let source = s.toJSONElementArray()
        let target = t.toJSONElementArray()
        let lcs = source.longestCommonSubsequence(target)

        var srcIdx = 0
        var targetIdx = 0
        var lcsIdx = 0
        let srcSize = source.count
        let targetSize = target.count
        let lcsSize = lcs.count

        var pos = 0
        while lcsIdx < lcsSize {
            let lcsNode = lcs[lcsIdx]
            let srcNode = source[srcIdx]
            let targetNode = target[targetIdx]

            if lcsNode == srcNode && lcsNode == targetNode {
                srcIdx += 1
                targetIdx += 1
                lcsIdx += 1
                pos += 1
            } else {
                if lcsNode == srcNode {
                    let currPath = path.appended(withIndex: pos)
                    operations.append(.add(path: currPath, value: targetNode))
                    pos += 1
                    targetIdx += 1
                } else if lcsNode == targetNode {
                    let currPath = path.appended(withIndex: pos)
                    addArrayItemTest(path: currPath, node: srcNode)
                    operations.append(.remove(path: currPath, value: srcNode))
                    srcIdx += 1
                } else {
                    let currPath = path.appended(withIndex: pos)
                    addArrayItemTest(path: currPath, node: srcNode)
                    try generateDiffs(pointer: currPath, source: srcNode, target: targetNode)
                    srcIdx += 1
                    targetIdx += 1
                    pos += 1
                }
            }
        }

        while srcIdx < srcSize && targetIdx < targetSize {
            let srcNode = source[srcIdx]
            let targetNode = target[targetIdx]
            let currPath = path.appended(withIndex: pos)
            addArrayItemTest(path: currPath, node: srcNode)
            try generateDiffs(pointer: currPath, source: srcNode, target: targetNode)
            srcIdx += 1
            targetIdx += 1
            pos += 1
        }

        pos = addRemaining(path, target, &pos, &targetIdx, targetSize)
        removeRemaining(path, pos, &srcIdx, srcSize, source)
    }

    private mutating func addArrayItemTest(path: JSONPointer, node: JSONElement) {
        if node.isContainer {
            if let field = getIdentifierField(node), let value = node.get(fieldName: field) {
                operations.append(.test(path: path.appended(withComponent: field), value: value))
            }
        } else {
            operations.append(.test(path: path, value: node))
        }
    }

    private func getIdentifierField(_ node: JSONElement) -> String? {
        return identifiers.first(where: { node.get(fieldName: $0) != nil })
    }

    private mutating func removeRemaining(_ path: JSONPointer, _ pos: Int, _ srcIdx: inout Int, _ srcSize: Int, _ source: [JSONElement]) {
        while srcIdx < srcSize {
            let value = source[srcIdx]
            let currPath = path.appended(withIndex: pos)
            addArrayItemTest(path: currPath, node: value)
            operations.append(.remove(path: currPath, value: value))
            srcIdx += 1
        }
    }

    private mutating func addRemaining(_ path: JSONPointer, _ target: [JSONElement], _ pos: inout Int, _ targetIdx: inout Int, _ targetSize: Int) -> Int {
        while targetIdx < targetSize {
            let jsonNode = target[targetIdx]
            let currPath = path.appended(withIndex: pos)
            try? operations.append(.add(path: currPath, value: jsonNode.copy()))
            pos += 1
            targetIdx += 1
        }
        return pos
    }

    private mutating func replace(path: JSONPointer, old: JSONElement, value: JSONElement) {
        operations.append(.replace(path: path, old: old, value: value))
    }

    private mutating func remove(path: JSONPointer, value: JSONElement) {
        operations.append(.remove(path: path, value: value))
    }

    private mutating func add(path: JSONPointer, value: JSONElement) {
        if let oldPath = findUnchangedValue(value: value) {
            operations.append(.copy(from: oldPath, path: path, value: value))
        } else {
            operations.append(.add(path: path, value: value))
        }
    }

    private func findUnchangedValue(value: JSONElement) -> JSONPointer? {
        for (pointer, old) in unchanged where value == old {
            return pointer
        }
        return nil
    }

    private func findPreviouslyRemoved(value: JSONElement) -> Int? {
        return operations.firstIndex { (op) -> Bool in
            guard case let .remove(_, old) = op else {
                return false
            }
            return value == old
        }
    }
}

extension JSONPatch.Operation {
    fileprivate init(_ value: JSONPatchGenerator.Operation) {
        switch value {
        case let .add(path, value):
            self = .add(path: path, value: value)
        case let .remove(path, _):
            self = .remove(path: path)
        case let .copy(from, path, _):
            self = .copy(from: from, path: path)
        case let .replace(path, _, value):
            self = .replace(path: path, value: value)
        case let .move(from, _, path, _):
            self = .move(from: from, path: path)
        case let .test(path: path, value: value):
            self = .test(path: path, value: value)
        }
    }
}

extension JSONPatch {
    /// Initializes a JSONPatch instance with all json-patch operations required to transform the source
    /// json document into the target json document.
    ///
    /// - Parameters:
    ///   - source: The source json document.
    ///   - target: The target json document.
    public convenience init(source: JSONElement, target: JSONElement) throws {
        self.init(operations: try JSONPatchGenerator.generatePatch(source: source, target: target))
    }

    /// Initialize a JSONPatch instance with all json-patch operations required to transform the source
    /// json document into the target json document.
    ///
    /// - Parameters:
    ///   - source: The source json document as data.
    ///   - target: The target json document as data.
    ///   - options: The JSONSerialization options for reading the source and target data.
    public convenience init(source: Data, target: Data, options: JSONSerialization.ReadingOptions = []) throws {
        let sourceJson = try JSONSerialization.jsonElement(with: source, options: options)
        let targetJson = try JSONSerialization.jsonElement(with: target, options: options)
        try self.init(source: sourceJson, target: targetJson)
    }
}
