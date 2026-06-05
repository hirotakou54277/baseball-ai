import 'dart:math';
import '../models/team.dart';
import '../models/game.dart';
import '../models/prediction.dart';
import 'database_service.dart';

class PredictionService {
  static Prediction predict(Game game, Team home, Team away) {
    // 重み付きスコア計算
    final homeScore = _calcScore(home, away, isHome: true);
    final awayScore = _calcScore(away, home, isHome: false);

    // ソフトマックスで確率変換
    final expHome = exp(homeScore * 3);
    final expAway = exp(awayScore * 3);
    final total = expHome + expAway;
    final homeProb = expHome / total;
    final awayProb = expAway / total;

    final winnerIsHome = homeProb >= awayProb;
    final reason = _buildReason(home, away, homeProb, awayProb);

    return Prediction(
      game: game,
      homeTeam: home,
      awayTeam: away,
      winnerTeamId: winnerIsHome ? home.id : away.id,
      homeWinProbability: homeProb,
      awayWinProbability: awayProb,
      reason: reason,
      predictedAt: DateTime.now(),
    );
  }

  static double _calcScore(Team team, Team opponent, {required bool isHome}) {
    double score = 0;

    // 1. 勝率（ホーム/アウェイ補正）
    final winRate = isHome ? team.homeWinRate : team.awayWinRate;
    score += winRate * 0.35;

    // 2. 直近5試合の調子
    score += team.recent5WinRate * 0.25;

    // 3. 攻撃力 vs 相手防御力
    final attackScore = team.avgScore / max(opponent.avgConcede, 0.1);
    score += min(attackScore / 3.0, 1.0) * 0.25;

    // 4. 全体勝率
    score += team.winRate * 0.15;

    return score;
  }

  static String _buildReason(
      Team home, Team away, double homeProb, double awayProb) {
    final parts = <String>[];

    // 勝率比較
    if (home.homeWinRate > away.awayWinRate) {
      parts.add(
          '${home.name}のホーム勝率(${(home.homeWinRate * 100).toStringAsFixed(0)}%)が'
          '${away.name}のアウェイ勝率(${(away.awayWinRate * 100).toStringAsFixed(0)}%)を上回る');
    } else {
      parts.add(
          '${away.name}のアウェイ勝率(${(away.awayWinRate * 100).toStringAsFixed(0)}%)が'
          '${home.name}のホーム勝率(${(home.homeWinRate * 100).toStringAsFixed(0)}%)を上回る');
    }

    // 直近5試合
    final homeRecent = home.recent5WinRate;
    final awayRecent = away.recent5WinRate;
    if (homeRecent > awayRecent) {
      parts.add('${home.name}は直近5試合で${home.recent5.where((r) => r == "W").length}勝と好調');
    } else if (awayRecent > homeRecent) {
      parts.add('${away.name}は直近5試合で${away.recent5.where((r) => r == "W").length}勝と好調');
    }

    // 攻守バランス
    if (home.avgScore > away.avgConcede) {
      parts.add('${home.name}の平均得点(${home.avgScore.toStringAsFixed(1)})が'
          '${away.name}の平均失点(${away.avgConcede.toStringAsFixed(1)})を超える');
    }

    return parts.join('。\n');
  }

  static Future<void> savePrediction(Prediction p) async {
    final history = PredictionHistory(
      gameDate: p.game.date,
      homeTeamId: p.homeTeam.id,
      homeTeamName: p.homeTeam.name,
      awayTeamId: p.awayTeam.id,
      awayTeamName: p.awayTeam.name,
      predictedWinnerId: p.winnerTeamId,
      winProbability: p.winnerProbability,
    );
    await DatabaseService.savePredictionHistory(history);
  }

  static Future<List<PredictionHistory>> getHistory() =>
      DatabaseService.getPredictionHistory();
}
