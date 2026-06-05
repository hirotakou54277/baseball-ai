import 'package:flutter/material.dart';
import '../models/game.dart';
import '../models/team.dart';
import '../models/prediction.dart';
import '../services/prediction_service.dart';

class PredictionScreen extends StatefulWidget {
  final Game game;
  final Team homeTeam;
  final Team awayTeam;

  const PredictionScreen({
    super.key,
    required this.game,
    required this.homeTeam,
    required this.awayTeam,
  });

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen>
    with SingleTickerProviderStateMixin {
  Prediction? _prediction;
  late AnimationController _animCtrl;
  late Animation<double> _barAnimation;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _barAnimation = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _runPrediction();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _runPrediction() async {
    final p = PredictionService.predict(
        widget.game, widget.homeTeam, widget.awayTeam);
    await PredictionService.savePrediction(p);
    setState(() => _prediction = p);
    _animCtrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    final home = widget.homeTeam;
    final away = widget.awayTeam;
    final p = _prediction;

    return Scaffold(
      appBar: AppBar(
        title: Text('${home.name} vs ${away.name}'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildMatchupCard(p),
                  const SizedBox(height: 16),
                  _buildProbabilityBar(p),
                  const SizedBox(height: 16),
                  _buildStatsCard(p),
                  const SizedBox(height: 16),
                  _buildReasonCard(p),
                ],
              ),
            ),
    );
  }

  Widget _buildMatchupCard(Prediction p) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(widget.game.date,
                style:
                    const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildTeamColumn(p.homeTeam, isWinner: p.winnerTeamId == p.homeTeam.id),
                Column(
                  children: [
                    const Text('VS',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('ホーム/アウェイ',
                          style:
                              TextStyle(fontSize: 10, color: Colors.blue)),
                    ),
                  ],
                ),
                _buildTeamColumn(p.awayTeam, isWinner: p.winnerTeamId == p.awayTeam.id),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamColumn(Team team, {required bool isWinner}) {
    return Column(
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor:
              isWinner ? const Color(0xFF1A237E) : Colors.grey.shade200,
          child: Text(
            team.name.substring(0, 1),
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isWinner ? Colors.white : Colors.grey.shade600),
          ),
        ),
        const SizedBox(height: 8),
        Text(team.name,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontWeight:
                    isWinner ? FontWeight.bold : FontWeight.normal,
                fontSize: 13)),
        if (isWinner)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.amber,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('予想勝利',
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }

  Widget _buildProbabilityBar(Prediction p) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('勝率予測',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                    width: 60,
                    child: Text(
                      '${(p.homeWinProbability * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A237E)),
                    )),
                Expanded(
                  child: AnimatedBuilder(
                    animation: _barAnimation,
                    builder: (context, child) => ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: p.homeWinProbability * _barAnimation.value,
                        backgroundColor: Colors.red.shade200,
                        valueColor: const AlwaysStoppedAnimation(
                            Color(0xFF1A237E)),
                        minHeight: 18,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                    width: 60,
                    child: Text(
                      '${(p.awayWinProbability * 100).toStringAsFixed(0)}%',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red),
                    )),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(widget.homeTeam.name,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF1A237E))),
                Text(widget.awayTeam.name,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.red)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(Prediction p) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('チーム成績',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 12),
            _buildStatRow('勝率', p.homeTeam.winRate, p.awayTeam.winRate),
            _buildStatRow('直近5試合勝率',
                p.homeTeam.recent5WinRate, p.awayTeam.recent5WinRate),
            _buildStatRow('平均得点', p.homeTeam.avgScore / 10,
                p.awayTeam.avgScore / 10,
                homeLabel:
                    p.homeTeam.avgScore.toStringAsFixed(1),
                awayLabel:
                    p.awayTeam.avgScore.toStringAsFixed(1)),
            _buildStatRow('平均失点', 1 - p.homeTeam.avgConcede / 10,
                1 - p.awayTeam.avgConcede / 10,
                homeLabel:
                    p.homeTeam.avgConcede.toStringAsFixed(1),
                awayLabel:
                    p.awayTeam.avgConcede.toStringAsFixed(1),
                lowerIsBetter: true),
            const SizedBox(height: 8),
            _buildRecent5Row(p.homeTeam, p.awayTeam),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, double homeVal, double awayVal,
      {String? homeLabel, String? awayLabel, bool lowerIsBetter = false}) {
    final homeWins = lowerIsBetter ? homeVal >= awayVal : homeVal >= awayVal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 80,
              child: Text(
                  homeLabel ?? '${(homeVal * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontWeight: homeWins
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: homeWins
                          ? const Color(0xFF1A237E)
                          : Colors.grey))),
          Expanded(
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12))),
          SizedBox(
              width: 80,
              child: Text(
                  awayLabel ?? '${(awayVal * 100).toStringAsFixed(0)}%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontWeight: !homeWins
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: !homeWins ? Colors.red : Colors.grey))),
        ],
      ),
    );
  }

  Widget _buildRecent5Row(Team home, Team away) {
    return Row(
      children: [
        _buildRecent5Chips(home.recent5),
        const Expanded(
            child: Text('直近5試合',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12))),
        _buildRecent5Chips(away.recent5, reversed: true),
      ],
    );
  }

  Widget _buildRecent5Chips(List<String> results, {bool reversed = false}) {
    final items = reversed ? results.reversed.toList() : results;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: items.map((r) {
        final isW = r == 'W';
        return Container(
          margin: const EdgeInsets.only(right: 3),
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: isW ? Colors.green : Colors.red.shade300,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(isW ? '○' : '●',
                style:
                    const TextStyle(color: Colors.white, fontSize: 9)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildReasonCard(Prediction p) {
    return Card(
      elevation: 2,
      color: Colors.amber.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.lightbulb, color: Colors.amber, size: 20),
                SizedBox(width: 6),
                Text('予想根拠',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${p.winnerTeam.name}が有利と予想します（${(p.winnerProbability * 100).toStringAsFixed(0)}%）',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(p.reason,
                style: const TextStyle(fontSize: 13, height: 1.6)),
          ],
        ),
      ),
    );
  }
}
