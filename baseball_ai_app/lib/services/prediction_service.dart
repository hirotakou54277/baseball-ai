import 'dart:math';
import '../models/team.dart';
import '../models/game.dart';
import '../models/prediction.dart';
import 'database_service.dart';

// チームの動的成績（過去N試合から計算）
class _DynamicStats {
  final int games;
  final int wins;
  final double avgScore;
  final double avgConcede;
  final List<String> recent5;

  _DynamicStats({
    required this.games,
    required this.wins,
    required this.avgScore,
    required this.avgConcede,
    required this.recent5,
  });

  double get winRate => games > 0 ? wins / games : 0.5;
}

class PredictionService {
  // 過去30日間の実績からチームの動的成績を計算
  static Future<Map<String, _DynamicStats>> _calcDynamicStats() async {
    final now = DateTime.now();
    final oneMonthAgo = now.subtract(const Duration(days: 90)); // 3ヶ月
    final fromDate =
        '${oneMonthAgo.year}-${oneMonthAgo.month.toString().padLeft(2, '0')}-${oneMonthAgo.day.toString().padLeft(2, '0')}';
    final toDate =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // 過去30日間の終了試合を取得
    final allGames = await DatabaseService.getGamesInRange(fromDate, toDate);
    final finished =
        allGames.where((g) => g.isFinished).toList();

    final stats = <String, Map<String, dynamic>>{};

    for (final g in finished) {
      final hs = g.homeScore!;
      final as_ = g.awayScore!;

      // ホームチーム
      stats.putIfAbsent(g.homeTeamId, () => {
            'wins': 0,
            'games': 0,
            'scored': 0.0,
            'conceded': 0.0,
            'results': <String>[],
          });
      stats[g.homeTeamId]!['games'] = (stats[g.homeTeamId]!['games'] as int) + 1;
      stats[g.homeTeamId]!['scored'] =
          (stats[g.homeTeamId]!['scored'] as double) + hs;
      stats[g.homeTeamId]!['conceded'] =
          (stats[g.homeTeamId]!['conceded'] as double) + as_;
      if (hs > as_) {
        stats[g.homeTeamId]!['wins'] =
            (stats[g.homeTeamId]!['wins'] as int) + 1;
        (stats[g.homeTeamId]!['results'] as List<String>).add('W');
      } else {
        (stats[g.homeTeamId]!['results'] as List<String>).add('L');
      }

      // アウェイチーム
      stats.putIfAbsent(g.awayTeamId, () => {
            'wins': 0,
            'games': 0,
            'scored': 0.0,
            'conceded': 0.0,
            'results': <String>[],
          });
      stats[g.awayTeamId]!['games'] =
          (stats[g.awayTeamId]!['games'] as int) + 1;
      stats[g.awayTeamId]!['scored'] =
          (stats[g.awayTeamId]!['scored'] as double) + as_;
      stats[g.awayTeamId]!['conceded'] =
          (stats[g.awayTeamId]!['conceded'] as double) + hs;
      if (as_ > hs) {
        stats[g.awayTeamId]!['wins'] =
            (stats[g.awayTeamId]!['wins'] as int) + 1;
        (stats[g.awayTeamId]!['results'] as List<String>).add('W');
      } else {
        (stats[g.awayTeamId]!['results'] as List<String>).add('L');
      }
    }

    final result = <String, _DynamicStats>{};
    for (final entry in stats.entries) {
      final d = entry.value;
      final games = d['games'] as int;
      final results = d['results'] as List<String>;
      result[entry.key] = _DynamicStats(
        games: games,
        wins: d['wins'] as int,
        avgScore:
            games > 0 ? (d['scored'] as double) / games : 3.5,
        avgConcede:
            games > 0 ? (d['conceded'] as double) / games : 3.5,
        recent5: results.reversed.take(5).toList(),
      );
    }
    return result;
  }

  // 非同期版（過去データ使用）
  static Future<Prediction> predictAsync(
      Game game, Team home, Team away) async {
    final dynStats = await _calcDynamicStats();
    return _buildPrediction(game, home, away, dynStats);
  }

  // 同期版（フォールバック）
  static Prediction predict(Game game, Team home, Team away) {
    return _buildPrediction(game, home, away, {});
  }

  static Prediction _buildPrediction(
      Game game, Team home, Team away,
      Map<String, _DynamicStats> dynStats) {
    final homeDyn = dynStats[home.id];
    final awayDyn = dynStats[away.id];

    // 過去30日データがある場合は重み付け（70%動的 + 30%シーズン通算）
    final homeWinRate30 = homeDyn != null && homeDyn.games >= 3
        ? homeDyn.winRate * 0.7 + home.winRate * 0.3
        : home.winRate;
    final awayWinRate30 = awayDyn != null && awayDyn.games >= 3
        ? awayDyn.winRate * 0.7 + away.winRate * 0.3
        : away.winRate;

    final homeAvgScore30 = homeDyn != null && homeDyn.games >= 3
        ? homeDyn.avgScore * 0.7 + home.avgScore * 0.3
        : home.avgScore;
    final awayAvgScore30 = awayDyn != null && awayDyn.games >= 3
        ? awayDyn.avgScore * 0.7 + away.avgScore * 0.3
        : away.avgScore;
    final homeAvgConcede30 = homeDyn != null && homeDyn.games >= 3
        ? homeDyn.avgConcede * 0.7 + home.avgConcede * 0.3
        : home.avgConcede;
    final awayAvgConcede30 = awayDyn != null && awayDyn.games >= 3
        ? awayDyn.avgConcede * 0.7 + away.avgConcede * 0.3
        : away.avgConcede;

    // 直近5試合（動的データ優先）
    final homeRecent5 =
        (homeDyn != null && homeDyn.recent5.isNotEmpty)
            ? homeDyn.recent5
            : home.recent5;
    final awayRecent5 =
        (awayDyn != null && awayDyn.recent5.isNotEmpty)
            ? awayDyn.recent5
            : away.recent5;
    final homeRecent5Rate = homeRecent5.isEmpty
        ? homeWinRate30
        : homeRecent5.where((r) => r == 'W').length / homeRecent5.length;
    final awayRecent5Rate = awayRecent5.isEmpty
        ? awayWinRate30
        : awayRecent5.where((r) => r == 'W').length / awayRecent5.length;

    // スコア計算（重み付き）
    double homeScore = 0;
    homeScore += home.homeWinRate * 0.25;
    homeScore += homeWinRate30 * 0.30;
    homeScore += homeRecent5Rate * 0.25;
    homeScore += min(homeAvgScore30 / max(awayAvgConcede30, 0.1) / 3.0, 1.0) * 0.20;

    double awayScore = 0;
    awayScore += away.awayWinRate * 0.25;
    awayScore += awayWinRate30 * 0.30;
    awayScore += awayRecent5Rate * 0.25;
    awayScore += min(awayAvgScore30 / max(homeAvgConcede30, 0.1) / 3.0, 1.0) * 0.20;

    // 確率変換（ソフトマックス）
    final expH = exp(homeScore * 4);
    final expA = exp(awayScore * 4);
    final total = expH + expA;
    final homeProb = expH / total;
    final awayProb = expA / total;

    // 予想スコア
    final predHome = (homeAvgScore30 + awayAvgConcede30) / 2 * 1.05;
    final predAway = (awayAvgScore30 + homeAvgConcede30) / 2;

    final winnerIsHome = homeProb >= awayProb;

    // 根拠テキスト（データソースも明示）
    final dataSource = homeDyn != null && homeDyn.games >= 3
        ? '過去${homeDyn.games}試合のデータ'
        : 'シーズン通算データ';
    final reason = _buildReason(
      home, away, homeProb, awayProb,
      homeWinRate30, awayWinRate30,
      homeRecent5, awayRecent5,
      predHome, predAway, dataSource,
    );

    return Prediction(
      game: game,
      homeTeam: home,
      awayTeam: away,
      winnerTeamId: winnerIsHome ? home.id : away.id,
      homeWinProbability: homeProb,
      awayWinProbability: awayProb,
      predictedHomeScore: predHome,
      predictedAwayScore: predAway,
      reason: reason,
      predictedAt: DateTime.now(),
    );
  }

  static String _buildReason(
    Team home, Team away,
    double homeProb, double awayProb,
    double homeWinRate30, double awayWinRate30,
    List<String> homeRecent5, List<String> awayRecent5,
    double predHome, double predAway,
    String dataSource,
  ) {
    final parts = <String>[];

    parts.add('【分析基準: $dataSource】');

    // 直近勝率
    if (homeWinRate30 > awayWinRate30) {
      parts.add(
          '${home.name}の直近勝率(${(homeWinRate30 * 100).toStringAsFixed(1)}%)が'
          '${away.name}(${(awayWinRate30 * 100).toStringAsFixed(1)}%)を上回る');
    } else {
      parts.add(
          '${away.name}の直近勝率(${(awayWinRate30 * 100).toStringAsFixed(1)}%)が'
          '${home.name}(${(homeWinRate30 * 100).toStringAsFixed(1)}%)を上回る');
    }

    // 直近5試合
    final homeW = homeRecent5.where((r) => r == 'W').length;
    final awayW = awayRecent5.where((r) => r == 'W').length;
    if (homeRecent5.isNotEmpty) {
      parts.add('${home.name}の直近${homeRecent5.length}試合: $homeW勝${homeRecent5.length - homeW}敗');
    }
    if (awayRecent5.isNotEmpty) {
      parts.add('${away.name}の直近${awayRecent5.length}試合: $awayW勝${awayRecent5.length - awayW}敗');
    }

    // 予想スコア
    parts.add(
        '予想スコア: ${home.name} ${predHome.round()} - ${predAway.round()} ${away.name}');

    return parts.join('\n');
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
      predictedHomeScore: p.predictedHomeScoreInt,
      predictedAwayScore: p.predictedAwayScoreInt,
    );
    await DatabaseService.savePredictionHistory(history);
  }

  static Future<List<PredictionHistory>> getHistory() =>
      DatabaseService.getPredictionHistory();
}
