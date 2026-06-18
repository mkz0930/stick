//
//  StickTests.swift
//  Stick
//
//  占位测试 target。后续按 ios-dev Rule 11 AAA 模式扩充。
//

import XCTest
@testable import Stick

final class StickTests: XCTestCase {

    /// 占位烟测：保证测试 target 能编译 + 运行。
    /// 一旦后续添加真实测试，请删除本用例。
    func test_placeholder_onePlusOne_equalsTwo() {
        // Arrange
        let a = 1
        let b = 1

        // Act
        let result = a + b

        // Assert
        XCTAssertEqual(result, 2)
    }
}
