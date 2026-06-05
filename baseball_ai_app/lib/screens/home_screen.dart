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

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _refreshing = false;
  String _statusMessage = '';
  Map<String, Team> _teams = {};
  String? _lastUpdated;

  // タブ
  late TabController _tabController;

  // 今日・明日の試合
  List<Game> _todayGames = [];
  List<Game> _tomorrowGames = [];

  // 過去1ヶ月の試合（日付ごとにグループ化）
  Map<String, List<Game>> _pastGames = {};

  final _fmt = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initialize();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
    final oneMonthAgo = now.subtract(const Duration(days: 90)); // 3ヶ月

    final todayStr = _fmt.format(now);
    final tomorrowStr = _fmt.format(tomorrow);
    final oneMonthAgoStr = _fmt.format(oneMonthAgo);

    final teams = await DatabaseService.getTeams();
    final todayGames = await DatabaseService.getGamesByDate(todayStr);
    final tomorrowGames = await DatabaseService.getGamesByDate(tomorrowStr);
    final pastGames = await DatabaseService.getGamesInRange(
        oneMonthAgoStr, todayStr);
    final lastUpdated = await DataService.getLastUpdated();

    // 過去の試合を日付ごとにグループ化（新しい順）
    final pastMap = <String, List<Game>>{};
    for (final g in pastGames.reversed) {
      pastMap.putIfAbsent(g.date, () => []).add(g);
    }

    setState(() {
      _teams = {for (final t in teams) t.id: t};
      _todayGames = todayGames;
      _tomorrowGames = tomorrowGames;
      _pastGames = pastMap;
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.today), text: '今日・明日'),
            Tab(icon: Icon(Icons.calendar_month), text: '過去1ヶ月'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildStatusBar(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildUpcomingTab(),
                      _buildPastTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      color: const Color(0xFF1A237E).withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 13, color: Colors.blueGrey),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _lastUpdated != null
                  ? '$_statusMessage  最終更新: $_lastUpdated'
                  : _statusMessage,
              style:
                  const TextStyle(fontSize: 11, color: Colors.blueGrey),
            ),
          ),
        ],
      ),
    );
  }

  // ── 今日・明日タブ ──────────────────────────────
  Widget _buildUpcomingTab() {
    if (_todayGames.isEmpty && _tomorrowGames.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sports_baseball, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('試合データがありません',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _manualRefresh,
      child: CustomScrollView(
        slivers: [
          if (_todayGames.isNotEmpty) ...[
            _sectionHeader('今日の試合',
                DateFormat('M月d日(E)', 'ja').format(DateTime.now())),
            _gameSliver(_todayGames),
          ],
          if (_tomorrowGames.isNotEmpty) ...[
            _sectionHeader('明日の試合',
                DateFormat('M月d日(E)', 'ja').format(
                    DateTime.now().add(const Duration(days: 1)))),
            _gameSliver(_tomorrowGames),
          ],
        ],
      ),
    );
  }

  // ── 過去1ヶ月タブ ──────────────────────────────
  Widget _buildPastTab() {
    if (_pastGames.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_month, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('過去の試合データがありません',
                style: TextStyle(color: Colors.grey)),
            SizedBox(height: 8),
            Text('🔄ボタンで更新してください',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    }

    final dates = _pastGames.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // 新しい順

    return ListView.builder(
      itemCount: dates.length,
      itemBuilder: (context, i) {
        final date = dates[i];
        final games = _pastGames[date]!;
        final dt = DateTime.tryParse(date);
        final label = dt != null
            ? DateFormat('M月d日(E)', 'ja').format(dt)
            : date;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: const Color(0xFF1A237E).withValues(alpha: 0.06),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today,
                      size: 14, color: Color(0xFF1A237E)),
                  const SizedBox(width: 6),
                  Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Color(0xFF1A237E))),
                ],
              ),
            ),
            ...games.map((game) {
              final home = _teams[game.homeTeamId];
              final away = _teams[game.awayTeamId];
              if (home == null || away == null) {
                return const SizedBox.shrink();
              }
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
            }),
          ],
        );
      },
    );
  }

  SliverToBoxAdapter _sectionHeader(String title, String subtitle) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Row(
          children: [
            const Icon(Icons.calendar_today,
                size: 16, color: Color(0xFF1A237E)),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A237E))),
            const SizedBox(width: 8),
            Text(subtitle,
                style:
                    const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  SliverList _gameSliver(List<Game> games) {
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
