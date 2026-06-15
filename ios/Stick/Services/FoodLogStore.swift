import Foundation

struct FoodEntry: Identifiable, Codable {
    let id: UUID
    let meal: MealType
    let foodName: String
    let calories: Int?
    let timestamp: Date
}

enum MealType: String, Codable, CaseIterable {
    case breakfast, lunch, dinner
}

@MainActor
final class FoodLogStore: ObservableObject {
    static let shared = FoodLogStore()

    @Published private(set) var todayEntries: [FoodEntry] = []

    private let key = "food.log.v1"
    private let maxDays = 30

    init() { load() }

    /// 根据时间判断餐次
    static func mealType(for date: Date = Date()) -> MealType {
        let hour = Calendar.current.component(.hour, from: date)
        if hour >= 6 && hour < 11 { return .breakfast }
        if hour >= 11 && hour < 14 { return .lunch }
        if hour >= 17 && hour < 21 { return .dinner }
        // 未命中时段：按最近餐次
        if hour < 6 || hour >= 21 { return .dinner }
        return .lunch
    }

    func addEntry(meal: MealType, foodName: String, calories: Int?) {
        let entry = FoodEntry(id: UUID(), meal: meal, foodName: foodName, calories: calories, timestamp: Date())
        todayEntries.append(entry)
        save()
    }

    var todayTotalCalories: Int {
        todayEntries.compactMap { $0.calories }.reduce(0, +)
    }

    // MARK: - 私有

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let all: [String: [FoodEntry]] = try? JSONDecoder().decode([String: [FoodEntry]].self, from: data) else { return }
        let today = dateKey()
        todayEntries = all[today] ?? []
    }

    private func save() {
        var all: [String: [FoodEntry]] = [:]
        if let data = UserDefaults.standard.data(forKey: key),
           let existing: [String: [FoodEntry]] = try? JSONDecoder().decode([String: [FoodEntry]].self, from: data) {
            all = existing
        }
        all[dateKey()] = todayEntries
        if let d = try? JSONEncoder().encode(all) { UserDefaults.standard.set(d, forKey: key) }
    }

    private func dateKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
