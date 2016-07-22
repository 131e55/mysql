#if os(Linux)
    import CMySQLLinux
#else
    import CMySQLMac
#endif

extension Bind {
    /**
        Parses a MySQL Value object from
        an output binding.
    */
    public var value: Value? {
        guard let buffer = cBind.buffer else {
            return nil
        }

        let value: Value?

        func cast<T>(_ buffer: UnsafeMutablePointer<Void>, _ type: T.Type) -> UnsafeMutablePointer<T> {
            return UnsafeMutablePointer<T>(buffer)
        }

        func unwrap<T>(_ buffer: UnsafeMutablePointer<Void>, _ type: T.Type) -> T {
            return UnsafeMutablePointer<T>(buffer).pointee
        }

        let isNull = cBind.is_null.pointee

        if isNull == 1 {
            value = nil
        } else {
            switch variant {
            case MYSQL_TYPE_STRING,
                 MYSQL_TYPE_VAR_STRING,
                 MYSQL_TYPE_BLOB,
                 MYSQL_TYPE_DECIMAL,
                 MYSQL_TYPE_NEWDECIMAL,
                 MYSQL_TYPE_ENUM,
                 MYSQL_TYPE_SET:
                let buffer = UnsafeMutableBufferPointer(
                    start: cast(buffer, UInt8.self),
                    count: Int(cBind.length.pointee) / sizeof(UInt8.self)
                )
                value = .string(buffer.string)
            case MYSQL_TYPE_LONG:
                if cBind.is_unsigned == 1 {
                    let uint = unwrap(buffer, UInt32.self)
                    value = .uint(UInt(uint))
                } else {
                    let int = unwrap(buffer, Int32.self)
                    value = .int(Int(int))
                }
            case MYSQL_TYPE_LONGLONG:
                if cBind.is_unsigned == 1 {
                    let uint = unwrap(buffer, UInt64.self)
                    value = .uint(UInt(uint))
                } else {
                    let int = unwrap(buffer, Int64.self)
                    value = .int(Int(int))
                }
            case MYSQL_TYPE_DOUBLE:
                let double = unwrap(buffer, Double.self)
                value = .double(double)
            default:
                value = .null
            }
        }
        
        return value
    }
}

extension Sequence where Iterator.Element == UInt8 {
    var string: String {
        var utf = UTF8()
        var gen = makeIterator()
        var str = String()
        while true {
            switch utf.decode(&gen) {
            case .emptyInput:
                return str
            case .error:
                break
            case .scalarValue(let unicodeScalar):
                str.append(unicodeScalar)
            }
        }
    }
}
