import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/team.dart';
import '../models/game.dart';
import 'database_service.dart';

// GitHubリポジトリのRaw URLに変更してください
const _dataUrl =
    'https://raw.githubusercontent.com/YOUR_USERNAME/baseball-ai/main/data/games.json';

class DataService {
  static Future<bool> refreshData() async {
    try {
      final response = await http
          .get(Uri.parse(_dataUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return false;

      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

      final teams = (json['teams'] as List)
          .map((t) => Team.fromJson(t as Map<String, dynamic>))
          .toList();

      final games = <Game>[];
      if (json['games'] != null) {
        games.addAll((json['games'] as List)
            .map((g) => Game.fromJson(g as Map<String, dynamic>)));
      }
      if (json['results'] != null) {
        games.addAll((json['results'] as List).map((g) {
          final map = Map<String, dynamic>.from(g as Map<String, dynamic>);
          map['status'] = 'finished';
          return Game.fromJson(map);
        }));
      }

      await DatabaseService.saveTeams(teams);
      await DatabaseService.saveGames(games);
      await DatabaseService.setMetadata(
          'last_updated', json['updated_at'] as String);

      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> needsRefresh() async {
    final lastUpdated = await DatabaseService.getMetadata('last_updated');
    if (lastUpdated == null) return true;
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    return lastUpdated != todayStr;
  }

  static Future<String?> getLastUpdated() =>
      DatabaseService.getMetadata('last_updated');
}
