import Async
import MySQL
import XCTest

class MySQLTests: XCTestCase {
    func testSimpleQuery() throws {
        let client = try MySQLConnection.makeTest()
        let results = try client.simpleQuery("SELECT @@version;").wait()
        try XCTAssert(results[0]["@@version"]?.decode(String.self).contains("5.7") == true)
        print(results)
    }

    func testQuery() throws {
        let client = try MySQLConnection.makeTest()
        let results = try client.query("SELECT CONCAT(?, ?) as test;", ["hello", "world"]).wait()
        try XCTAssertEqual(results[0]["test"]?.decode(String.self), "helloworld")
        print(results)
    }

    func testInsert() throws {
        let client = try MySQLConnection.makeTest()
        let dropResults = try client.simpleQuery("DROP TABLE IF EXISTS foos;").wait()
        XCTAssertEqual(dropResults.count, 0)
        let createResults = try client.simpleQuery("CREATE TABLE foos (id INT SIGNED, name VARCHAR(64));").wait()
        XCTAssertEqual(createResults.count, 0)
        let insertResults = try client.query("INSERT INTO foos VALUES (?, ?);", [-1, "vapor"]).wait()
        XCTAssertEqual(insertResults.count, 0)
        let selectResults = try client.query("SELECT * FROM foos WHERE name = ?;", ["vapor"]).wait()
        XCTAssertEqual(selectResults.count, 1)
        print(selectResults)
        try XCTAssertEqual(selectResults[0]["id"]?.decode(Int.self), -1)
        try XCTAssertEqual(selectResults[0]["name"]?.decode(String.self), "vapor")
    }

    func testKitchenSink() throws {
        /// support
        struct KitechSinkColumn {
            let name: String
            let columnType: String
            let data: MySQLDataConvertible
            let match: (MySQLData?, StaticString, UInt) throws -> ()
            init<T>(_ name: String, _ columnType: String, _ value: T) where T: MySQLDataConvertible & Equatable {
                self.name = name
                self.columnType = columnType
                data = value
                self.match = { data, file, line in
                    if let data = data {
                        let t = try T.convertFromMySQLData(data)
                        XCTAssertEqual(t, value, "\(name) \(T.self)", file: file, line: line)
                    } else {
                        XCTFail("Data null", file: file, line: line)
                    }
                }
            }
        }
        let tests: [KitechSinkColumn] = [
            .init("xchar", "CHAR(60)", "hello1"),
            .init("xvarchar", "VARCHAR(61)", "hello2"),
            .init("xtext", "TEXT(62)", "hello3"),
            .init("xbinary", "BINARY(6)", "hello4"),
            .init("xvarbinary", "VARBINARY(66)", "hello5"),
            .init("xbit", "BIT", 1),
            .init("xtinyint", "TINYINT(1)", 5),
            .init("xsmallint", "SMALLINT(1)", 252),
            .init("xmediumint", "MEDIUMINT(1)", 1024),
            .init("xinteger", "INTEGER(1)", 1024293),
            .init("xbigint", "BIGINT(1)", 234234234),
            .init("name", "VARCHAR(10)", "vapor"),
        ]

        let client = try MySQLConnection.makeTest()
        /// create table
        let columns = tests.map { test in
            return "`\(test.name)` \(test.columnType)"
        }.joined(separator: ", ")
        let dropResults = try client.simpleQuery("DROP TABLE IF EXISTS kitchen_sink;").wait()
        XCTAssertEqual(dropResults.count, 0)
        let createResults = try client.simpleQuery("CREATE TABLE kitchen_sink (\(columns));").wait()
        XCTAssertEqual(createResults.count, 0)

        /// insert data
        let placeholders = tests.map { _ in "?" }.joined(separator: ", ")
        let insertResults = try client.query("INSERT INTO kitchen_sink VALUES (\(placeholders));", tests.map { $0.data }).wait()
        XCTAssertEqual(insertResults.count, 0)

        // select data
        let selectResults = try client.query("SELECT * FROM kitchen_sink WHERE name = ?;", ["vapor"]).wait()
        XCTAssertEqual(selectResults.count, 1)
        print(selectResults)

        for test in tests {
            try test.match(selectResults[0][test.name], #file, #line)
        }
    }

    static let allTests = [
        ("testSimpleQuery", testSimpleQuery),
        ("testQuery", testQuery),
        ("testInsert", testInsert),
        ("testKitchenSink", testKitchenSink),
    ]
}

extension MySQLConnection {
    /// Creates a test event loop and psql client.
    static func makeTest() throws -> MySQLConnection {
        let group = MultiThreadedEventLoopGroup(numThreads: 1)
        let client = try MySQLConnection.connect(on: group) { error in
            // for some reason connection refused error is happening?
            if !"\(error)".contains("refused") {
                XCTFail("\(error)")
            }
        }.wait()
        _ = try client.authenticate(username: "foo", database: "test", password: "bar").wait()
        return client
    }
}
