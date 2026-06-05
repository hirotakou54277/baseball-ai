import 'package:flutter/material.dart';
import '../models/game.dart';
import '../models/team.dart';

class GameCard extends StatelessWidget {
  final Game game;
  final Team homeTeam;
  final Team awayTeam;
  final VoidCallback onTap;

  const GameCard({
    super.key,
    required this.game,
    required this.homeTeam,
    required this.awayTeam,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _teamBlock(homeTeam, isHome: true),
              Expanded(
                child: Column(
                  children: [
                    game.isFinished
                        ? Text(
                            '${game.homeScore} - ${game.awayScore}',
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          )
                        : Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('予想する',
                                style: TextStyle(
                                    color: Colors.blue,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                          ),
                    const SizedBox(height: 4),
                    Text(
                      game.isFinished ? '試合終了' : '予定',
                      style: TextStyle(
                          fontSize: 11,
                          color: game.isFinished
                              ? Colors.grey
                              : Colors.green),
                    ),
                  ],
                ),
              ),
              _teamBlock(awayTeam, isHome: false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _teamBlock(Team team, {required bool isHome}) {
    return SizedBox(
      width: 90,
      child: Column(
        crossAxisAlignment:
            isHome ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFF1A237E).withValues(alpha: 0.1),
            child: Text(
              team.name.substring(0, 1),
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A237E),
                  fontSize: 16),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            team.name,
            textAlign: isHome ? TextAlign.left : TextAlign.right,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${(team.winRate * 100).toStringAsFixed(0)}%',
            textAlign: isHome ? TextAlign.left : TextAlign.right,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
