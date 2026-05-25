import Foundation

struct UserProfile: Codable {
    var name: String
    var age: Int
    var heightCm: Double
    var weightKg: Double
    var weeklyGoalDays: Int
    var dailyCalorieGoal: Int
    var fitnessLevel: Difficulty

    init(
        name: String = "Athlete",
        age: Int = 25,
        heightCm: Double = 170,
        weightKg: Double = 70,
        weeklyGoalDays: Int = 4,
        dailyCalorieGoal: Int = 500,
        fitnessLevel: Difficulty = .beginner
    ) {
        self.name = name
        self.age = age
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.weeklyGoalDays = weeklyGoalDays
        self.dailyCalorieGoal = dailyCalorieGoal
        self.fitnessLevel = fitnessLevel
    }

    var bmi: Double {
        let heightM = heightCm / 100
        return weightKg / (heightM * heightM)
    }

    var bmiCategory: String {
        switch bmi {
        case ..<18.5: return "Underweight"
        case 18.5..<25: return "Healthy"
        case 25..<30: return "Overweight"
        default: return "Obese"
        }
    }
}
