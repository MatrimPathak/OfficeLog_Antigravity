final List<DateTime> hardcodedHolidays2024 = [
  DateTime(2024, 1, 1), // New Year's Day
  DateTime(2024, 1, 26), // Republic Day (India example)
  DateTime(2024, 8, 15), // Independence Day
  DateTime(2024, 10, 2), // Gandhi Jayanti
  DateTime(2024, 12, 25), // Christmas
  // Add more as needed
];

// Helper to get holidays for a specific month
List<DateTime> getHolidaysForMonth(DateTime month) {
  return hardcodedHolidays2024.where((date) {
    return date.year == month.year && date.month == month.month;
  }).toList();
}
