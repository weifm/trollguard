import Foundation

/// 归属地查询结果
struct PhoneLocationInfo {
    let prefix: String      // 前 7 位号段
    let province: String
    let city: String
    let zipCode: String
    let areaCode: String
    let carrier: String     // 移动 / 联通 / 电信 / 广电 / XX虚拟运营商

    var display: String { "\(province) \(city) \(carrier)" }
}

/// 中国手机号段归属地库（内嵌 ls0f/phone 的 phone.dat，约 50 万条号段记录）。
/// 二进制格式：<4s 版本串><i 索引区起始偏移> + [号段 int32 | 内容偏移 int32 | 运营商类型 uint8] × N
/// 记录内容为 NUL 结尾的 UTF-8："省份|城市|邮编|区号"
final class PhoneLocation {
    static let shared = PhoneLocation()

    private var buf: [UInt8] = []
    private var firstRecordOffset = 0
    private var recordCount = 0

    /// 省份 → 号段数量（懒加载统计）
    private lazy var provinceStats: [String: Int] = buildProvinceStats()

    /// "省 市" 组合 → 号段数量（懒加载统计）
    private lazy var cityStats: [String: Int] = buildCityStats()

    private init() {
        guard let url = Bundle.main.url(forResource: "phone", withExtension: "dat"),
              let data = try? Data(contentsOf: url) else { return }
        buf = [UInt8](data)
        guard buf.count > 8 else { buf = []; return }
        firstRecordOffset = Int(readInt32LE(at: 4))
        if firstRecordOffset > 8 && firstRecordOffset < buf.count {
            recordCount = (buf.count - firstRecordOffset) / 9
        }
    }

    var isLoaded: Bool { recordCount > 0 }
    var totalSegments: Int { recordCount }
    var provinceCount: Int { isLoaded ? provinceStats.count : 0 }
    /// 省市归属地组合数（对应安卓「按归属地拦截 293 个」的口径）
    var cityPlacesCount: Int { isLoaded ? cityStats.count : 0 }

    // MARK: - 查询

    /// 查询号码归属地（取前 7 位号段匹配）。
    func lookup(_ number: String) -> PhoneLocationInfo? {
        guard recordCount > 0 else { return nil }
        let digits = number.filter { $0.isNumber }
        guard digits.count >= 7 else { return nil }
        let prefix = Int(digits.prefix(7))!
        return lookupPrefix(prefix)
    }

    func lookupPrefix(_ prefix: Int) -> PhoneLocationInfo? {
        var left = 0
        var right = recordCount - 1
        while left <= right {
            let mid = (left + right) / 2
            let idx = firstRecordOffset + mid * 9
            let curPhone = Int(readInt32LE(at: idx))
            if curPhone > prefix {
                right = mid - 1
            } else if curPhone < prefix {
                left = mid + 1
            } else {
                let recOffset = Int(readInt32LE(at: idx + 4))
                let type = buf[idx + 8]
                return parseRecord(prefix: curPhone, offset: recOffset, type: type)
            }
        }
        return nil
    }

    // MARK: - 省份统计（按归属地拦截面板用）

    /// 省份 → 号段数量，按数量降序。
    func provincesByCount() -> [(name: String, count: Int)] {
        return provinceStats.sorted { $0.value > $1.value }
            .map { (name: $0.key, count: $0.value) }
    }

    private func buildCityStats() -> [String: Int] {
        var stats: [String: Int] = [:]
        guard recordCount > 0 else { return stats }
        for i in 0..<recordCount {
            let idx = firstRecordOffset + i * 9
            let recOffset = Int(readInt32LE(at: idx + 4))
            if let content = readRecordContent(offset: recOffset) {
                let parts = content.components(separatedBy: "|")
                if parts.count >= 2, !parts[0].isEmpty {
                    stats["\(parts[0]) \(parts[1])", default: 0] += 1
                }
            }
        }
        return stats
    }

    private func buildProvinceStats() -> [String: Int] {
        var stats: [String: Int] = [:]
        guard recordCount > 0 else { return stats }
        for i in 0..<recordCount {
            let idx = firstRecordOffset + i * 9
            let recOffset = Int(readInt32LE(at: idx + 4))
            if let content = readRecordContent(offset: recOffset) {
                let parts = content.components(separatedBy: "|")
                if let province = parts.first, !province.isEmpty {
                    stats[province, default: 0] += 1
                }
            }
        }
        return stats
    }

    // MARK: - 二进制解析

    private func readInt32LE(at offset: Int) -> Int32 {
        let b0 = Int32(buf[offset])
        let b1 = Int32(buf[offset + 1]) << 8
        let b2 = Int32(buf[offset + 2]) << 16
        let b3 = Int32(buf[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }

    private func readRecordContent(offset: Int) -> String? {
        guard offset > 0 && offset < buf.count else { return nil }
        var end = offset
        while end < buf.count && buf[end] != 0 { end += 1 }
        let bytes = Array(buf[offset..<end])
        return String(bytes: bytes, encoding: .utf8)
    }

    private func parseRecord(prefix: Int, offset: Int, type: UInt8) -> PhoneLocationInfo? {
        guard let content = readRecordContent(offset: offset) else { return nil }
        let parts = content.components(separatedBy: "|")
        guard parts.count >= 4 else { return nil }
        return PhoneLocationInfo(
            prefix: String(prefix),
            province: parts[0],
            city: parts[1],
            zipCode: parts[2],
            areaCode: parts[3],
            carrier: Self.carrierName(type)
        )
    }

    private static func carrierName(_ type: UInt8) -> String {
        switch type {
        case 1: return "移动"
        case 2: return "联通"
        case 3: return "电信"
        case 4: return "电信虚拟运营商"
        case 5: return "联通虚拟运营商"
        case 6: return "移动虚拟运营商"
        case 7: return "广电"
        case 8: return "广电虚拟运营商"
        default: return "未知"
        }
    }
}
