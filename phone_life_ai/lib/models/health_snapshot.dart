class HealthSnapshot {
  const HealthSnapshot({
    required this.sleepScore,
    required this.stressScore,
    required this.energyScore,
    required this.sleepHoursEstimate,
    required this.nightScreenMinutes,
    required this.appSwitchCount24h,
    required this.uniqueApps24h,
    required this.foodDeliveryOpens24h,
    required this.stepsToday,
    required this.movementVariance,
    required this.batteryChargingNow,
    required this.rawNote,
  });

  final int sleepScore;
  final int stressScore;
  final int energyScore;
  final double sleepHoursEstimate;
  final int nightScreenMinutes;
  final int appSwitchCount24h;
  final int uniqueApps24h;
  final int foodDeliveryOpens24h;
  final int stepsToday;
  final double movementVariance;
  final bool batteryChargingNow;
  final String rawNote;

  Map<String, dynamic> toJson() => {
        'sleepScore': sleepScore,
        'stressScore': stressScore,
        'energyScore': energyScore,
        'sleepHoursEstimate': sleepHoursEstimate,
        'nightScreenMinutes': nightScreenMinutes,
        'appSwitchCount24h': appSwitchCount24h,
        'uniqueApps24h': uniqueApps24h,
        'foodDeliveryOpens24h': foodDeliveryOpens24h,
        'stepsToday': stepsToday,
        'movementVariance': movementVariance,
        'batteryChargingNow': batteryChargingNow,
        'rawNote': rawNote,
      };
}
