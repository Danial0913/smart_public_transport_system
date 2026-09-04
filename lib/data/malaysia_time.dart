class MalaysiaTime {
  MalaysiaTime._();

  static const Duration utcOffset = Duration(hours: 8);
  static const int serviceStartMinutes = 5 * 60;
  static const int serviceEndMinutes = 23 * 60 + 59;

  /// Returns Malaysia wall-clock time even when an emulator is configured
  /// with a different system time zone.
  static DateTime now() {
    final malaysia = DateTime.now().toUtc().add(utcOffset);
    return DateTime(
      malaysia.year,
      malaysia.month,
      malaysia.day,
      malaysia.hour,
      malaysia.minute,
      malaysia.second,
      malaysia.millisecond,
      malaysia.microsecond,
    );
  }

  static bool isWithinServiceHours(DateTime value) {
    final minutes = value.hour * 60 + value.minute;
    return minutes >= serviceStartMinutes && minutes <= serviceEndMinutes;
  }

  static DateTime defaultDeparture() {
    return nextDeparture();
  }

  static DateTime nextDeparture({
    Duration leadTime = const Duration(minutes: 5),
  }) {
    final candidate = now().add(leadTime);
    if (isWithinServiceHours(candidate)) return candidate;
    return _nextServiceStart(candidate);
  }

  static DateTime _nextServiceStart(DateTime value) {
    final beforeOpening = value.hour * 60 + value.minute < serviceStartMinutes;
    final day = beforeOpening ? value : value.add(const Duration(days: 1));
    return DateTime(day.year, day.month, day.day, 5);
  }
}
