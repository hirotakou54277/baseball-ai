import 'team.dart';
import 'game.dart';

class Prediction {
  final Game game;
  final Team homeTeam;
  final Team awayTeam;
  final String winnerTeamId;
  final double homeWinProbability;
  final double awayWinProbability;
  final String reason;
  final DateTime predictedAt;

  Prediction({
    required this.game,
    required this.homeTeam,
    required this.awayTeam,
    required this.winnerTeamId,
    required this.homeWinProbability,
    required this.awayWinProbability,
    required this.reason,
    required this.predictedAt,
  });

  Team get winnerTeam =>
      winnerTeamId == homeTeam.id ? homeTeam : awayTeam;
  Team get loserTeam =>
      winnerTeamId == homeTeam.id ? awayTeam : homeTeam;
  double get winnerProbability => winnerTeamId == homeTeam.id
      ? homeWinProbability
      : awayWinProbability;
}

class PredictionHistory {
  final String gameDate;
  final String homeTeamId;
  final String homeTeamName;
  final String awayTeamId;
  final String awayTeamName;
  final String predictedWinnerId;
  final double winProbability;
  final int? actualHomeScore;
  final int? actualAwayScore;
  final bool? isCorrect;

  PredictionHistory({
    required this.gameDate,
    required this.homeTeamId,
    required this.homeTeamName,
    required this.awayTeamId,
    required this.awayTeamName,
    required this.predictedWinnerId,
    required this.winProbability,
    this.actualHomeScore,
    this.actualAwayScore,
    this.isCorrect,
  });

  factory PredictionHistory.fromMap(Map<String, dynamic> map) {
    return PredictionHistory(
      gameDate: map['game_date'] as String,
      homeTeamId: map['home_team_id'] as String,
      homeTeamName: map['home_team_name'] as String,
      awayTeamId: map['away_team_id'] as String,
      awayTeamName: map['away_team_name'] as String,
      predictedWinnerId: map['predicted_winner_id'] as String,
      winProbability: (map['win_probability'] as num).toDouble(),
      actualHomeScore: map['actual_home_score'] as int?,
      actualAwayScore: map['actual_away_score'] as int?,
      isCorrect: map['is_correct'] == null
          ? null
          : (map['is_correct'] as int) == 1,
    );
  }

  Map<String, dynamic> toMap() => {
        'game_date': gameDate,
        'home_team_id': homeTeamId,
        'home_team_name': homeTeamName,
        'away_team_id': awayTeamId,
        'away_team_name': awayTeamName,
        'predicted_winner_id': predictedWinnerId,
        'win_probability': winProbability,
        'actual_home_score': actualHomeScore,
        'actual_away_score': actualAwayScore,
        'is_correct': isCorrect == null ? null : (isCorrect! ? 1 : 0),
      };
}
