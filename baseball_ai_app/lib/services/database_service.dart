import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/team.dart';
import '../models/game.dart';
import '../models/prediction.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, 'baseball_ai.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE teams (
            id TEXT PRIMARY KEY,
            data TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE games (
            id TEXT PRIMARY KEY,
            data TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE prediction_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            game_date TEXT NOT NULL,
            home_team_id TEXT NOT NULL,
            home_team_name TEXT NOT NULL,
            away_team_id TEXT NOT NULL,
            away_team_name TEXT NOT NULL,
            predicted_winner_id TEXT NOT NULL,
            win_probability REAL NOT NULL,
            actual_home_score INTEGER,
            actual_away_score INTEGER,
            is_correct INTEGER,
            UNIQUE(game_date, home_team_id, away_team_id)
          )
        ''');
      },
    );
  }

  static Future<String?> getMetadata(String key) async {
    final db = await database;
    final rows = await db.query('metadata',
        where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  static Future<void> setMetadata(String key, String value) async {
    final db = await database;
    await db.insert('metadata', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> saveTeams(List<Team> teams) async {
    final db = await database;
    final batch = db.batch();
    for (final team in teams) {
      batch.insert(
        'teams',
        {'id': team.id, 'data': jsonEncode(team.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Team>> getTeams() async {
    final db = await database;
    final rows = await db.query('teams');
    return rows.map((r) =>
        Team.fromJson(jsonDecode(r['data'] as String))).toList();
  }

  static Future<Team?> getTeamById(String id) async {
    final db = await database;
    final rows =
        await db.query('teams', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Team.fromJson(jsonDecode(rows.first['data'] as String));
  }

  static Future<void> saveGames(List<Game> games) async {
    final db = await database;
    final batch = db.batch();
    for (final game in games) {
      final id = '${game.date}_${game.homeTeamId}_${game.awayTeamId}';
      batch.insert(
        'games',
        {'id': id, 'data': jsonEncode(game.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Game>> getGamesByDate(String date) async {
    final db = await database;
    final rows = await db.query('games',
        where: "id LIKE ?", whereArgs: ['${date}_%']);
    return rows
        .map((r) => Game.fromJson(jsonDecode(r['data'] as String)))
        .toList();
  }

  static Future<List<Game>> getAllGames() async {
    final db = await database;
    final rows = await db.query('games', orderBy: "id DESC");
    return rows
        .map((r) => Game.fromJson(jsonDecode(r['data'] as String)))
        .toList();
  }

  static Future<void> savePredictionHistory(
      PredictionHistory history) async {
    final db = await database;
    await db.insert('prediction_history', history.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<List<PredictionHistory>> getPredictionHistory() async {
    final db = await database;
    final rows = await db.query('prediction_history',
        orderBy: 'game_date DESC');
    return rows.map((r) => PredictionHistory.fromMap(r)).toList();
  }

  static Future<void> updatePredictionResult(
      String gameDate, String homeId, String awayId,
      int homeScore, int awayScore, bool isCorrect) async {
    final db = await database;
    await db.update(
      'prediction_history',
      {
        'actual_home_score': homeScore,
        'actual_away_score': awayScore,
        'is_correct': isCorrect ? 1 : 0,
      },
      where:
          'game_date = ? AND home_team_id = ? AND away_team_id = ?',
      whereArgs: [gameDate, homeId, awayId],
    );
  }
}
