class Game {
  final String date;
  final String homeTeamId;
  final String awayTeamId;
  final String status; // "upcoming" | "finished"
  final int? homeScore;
  final int? awayScore;

  Game({
    required this.date,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.status,
    this.homeScore,
    this.awayScore,
  });

  factory Game.fromJson(Map<String, dynamic> json) {
    return Game(
      date: json['date'] as String,
      homeTeamId: json['home'] as String,
      awayTeamId: json['away'] as String,
      status: json['status'] as String,
      homeScore: json['home_score'] as int?,
      awayScore: json['away_score'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'home': homeTeamId,
        'away': awayTeamId,
        'status': status,
        'home_score': homeScore,
        'away_score': awayScore,
      };

  bool get isUpcoming => status == 'upcoming';
  bool get isFinished => status == 'finished';
}
