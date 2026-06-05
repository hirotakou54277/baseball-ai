import 'package:flutter/material.dart';
import '../models/prediction.dart';
import '../services/prediction_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<PredictionHistory> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final history = await PredictionService.getHistory();
    setState(() {
      _history = history;
      _loading = false;
    });
  }

  int get _totalPredictions =>
      _history.where((h) => h.isCorrect != null).length;
  int get _correctPredictions =>
      _history.where((h) => h.isCorrect == true).length;
  double get _accuracy =>
      _totalPredictions == 0 ? 0 : _correctPredictions / _totalPredictions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('予想履歴'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('まだ予想履歴がありません',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    _buildSummary(),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: _history.length,
                        itemBuilder: (_, i) =>
                            _buildHistoryCard(_history[i]),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSummary() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF283593)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStat('予想数', '${_history.length}試合', Colors.white),
          _buildStat('的中数', '$_correctPredictions試合', Colors.amber),
          _buildStat('的中率',
              _totalPredictions == 0
                  ? '-'
                  : '${(_accuracy * 100).toStringAsFixed(1)}%',
              Colors.greenAccent),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  Widget _buildHistoryCard(PredictionHistory h) {
    final resultColor = h.isCorrect == null
        ? Colors.grey
        : h.isCorrect!
            ? Colors.green
            : Colors.red;
    final resultIcon = h.isCorrect == null
        ? Icons.hourglass_empty
        : h.isCorrect!
            ? Icons.check_circle
            : Icons.cancel;
    final resultText =
        h.isCorrect == null ? '結果待ち' : h.isCorrect! ? '的中！' : 'はずれ';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(resultIcon, color: resultColor, size: 32),
        title: Text('${h.homeTeamName} vs ${h.awayTeamName}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${h.gameDate}  予想: ${h.predictedWinnerId == h.homeTeamId ? h.homeTeamName : h.awayTeamName}勝利',
                style: const TextStyle(fontSize: 12)),
            if (h.actualHomeScore != null)
              Text(
                  '結果: ${h.homeTeamName} ${h.actualHomeScore} - ${h.actualAwayScore} ${h.awayTeamName}',
                  style: const TextStyle(fontSize: 12)),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${(h.winProbability * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                    color: resultColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            Text(resultText,
                style:
                    TextStyle(color: resultColor, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
