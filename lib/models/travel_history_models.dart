class CompletedJourney {
  const CompletedJourney({
    required this.id,
    required this.origin,
    required this.destination,
    required this.routeSummary,
    required this.completedAt,
    required this.durationMinutes,
    required this.fare,
    required this.walkingMetres,
    required this.legs,
  });

  final String id;
  final String origin;
  final String destination;
  final String routeSummary;
  final DateTime completedAt;
  final int durationMinutes;
  final double fare;
  final int walkingMetres;
  final List<CompletedJourneyLeg> legs;
}

class CompletedJourneyLeg {
  const CompletedJourneyLeg({
    required this.routeNumber,
    required this.mode,
    required this.fromStopName,
    required this.toStopName,
  });

  final String routeNumber;
  final String mode;
  final String fromStopName;
  final String toStopName;
}