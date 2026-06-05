import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/game.dart';
import '../models/team.dart';
import '../services/database_service.dart';
import '../services/data_service.dart';
import '../widgets/game_card.dart';
import 'prediction_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  bool _refreshing = false;
  String _statusMessage = '';
  List<Game> _todayGames = [];
  List<Game> _tomorrowGames = [];
  Map<String, Team> _teams = {};
  String? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _loading = true);

    if (await DataService.needsRefresh()) {
      setState(() => _statusMessage = 'データを更新中...');
      final ok = await DataService.refreshData();
      _statusMessage = ok ? 'データ更新完了' : 'キャッシュデータを使用中（オフライン）';
    } else {
      _statusMessage = 'データ最新';
    }

    await _loadFromDb();
    setState(() => _loading = false);
  }

  Future<void> _loadFromDb() async {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    final fmt = DateFormat('yyyy-MM-dd');

    final todayStr = fmt.format(now);
    final tomorrowStr = fmt.format(tomorrow);

    final teams = await DatabaseService.getTeams();
    final todayGames = await DatabaseService.getGamesByDate(todayStr);
    final tomorrowGames = await DatabaseService.getGamesByDate(tomorrowStr);
    final lastUpdated = await DataService.getLastUpdated();

    setState(() {
      _teams = {for (final t in teams) t.id: t};
      _todayGames = todayGames;
      _tomorrowGames = tomorrowGames;
      _lastUpdated = lastUpdated;
    });
  }

  Future<void> _manualRefresh() async {
    setState(() => _refreshing = true);
    final ok = await DataService.refreshData();
    _statusMessage = ok ? 'データ更新完了' : '更新失敗（キャッシュを使用）';
    await _loadFromDb();
    setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('野球予想AI'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.refresh),
            onPressed: _refreshing ? null : _manualRefresh,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _manualRefresh,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildStatusBar()),
                  if (_todayGames.isNotEmpty) ...[
                    _buildSectionHeader('今日の試合',
                        DateFormat('M月d日(E)', 'ja').format(DateTime.now())),
                    _buildGameList(_todayGames),
                  ],
                  if (_tomorrowGames.isNotEmpty) ...[
                    _buildSectionHeader('明日の試合',
                        DateFormat('M月d日(E)', 'ja').format(
                            DateTime.now().add(const Duration(days: 1)))),
                    _buildGameList(_tomorrowGames),
                  ],
                  if (_todayGames.isEmpty && _tomorrowGames.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.sports_baseball,
                                size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text('試合データがありません',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      color: const Color(0xFF1A237E).withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 14, color: Colors.blueGrey),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _lastUpdated != null
                  ? '$_statusMessage  最終更新: $_lastUpdated'
                  : _statusMessage,
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            const Icon(Icons.calendar_today,
                size: 18, color: Color(0xFF1A237E)),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A237E))),
            const SizedBox(width: 8),
            Text(subtitle,
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildGameList(List<Game> games) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final game = games[index];
          final home = _teams[game.homeTeamId];
          final away = _teams[game.awayTeamId];
          if (home == null || away == null) return const SizedBox.shrink();
          return GameCard(
            game: game,
            homeTeam: home,
            awayTeam: away,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PredictionScreen(
                    game: game, homeTeam: home, awayTeam: away),
              ),
            ),
          );
        },
        childCount: games.length,
      ),
    );
  }
}
