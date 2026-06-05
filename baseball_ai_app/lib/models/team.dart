class Team {
  final String id;
  final String name;
  final double winRate;
  final List<String> recent5;
  final double avgScore;
  final double avgConcede;
  final double homeWinRate;
  final double awayWinRate;

  Team({
    required this.id,
    required this.name,
    required this.winRate,
    required this.recent5,
    required this.avgScore,
    required this.avgConcede,
    required this.homeWinRate,
    required this.awayWinRate,
  });

  factory Team.fromJson(Map<String, dynamic> json) {
    return Team(
      id: json['id'] as String,
      name: json['name'] as String,
      winRate: (json['win_rate'] as num).toDouble(),
      recent5: List<String>.from(json['recent_5'] as List),
      avgScore: (json['avg_score'] as num).toDouble(),
      avgConcede: (json['avg_concede'] as num).toDouble(),
      homeWinRate: (json['home_win_rate'] as num).toDouble(),
      awayWinRate: (json['away_win_rate'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'win_rate': winRate,
        'recent_5': recent5,
        'avg_score': avgScore,
        'avg_concede': avgConcede,
        'home_win_rate': homeWinRate,
        'away_win_rate': awayWinRate,
      };

  double get recent5WinRate {
    if (recent5.isEmpty) return winRate;
    final wins = recent5.where((r) => r == 'W').length;
    return wins / recent5.length;
  }
}
