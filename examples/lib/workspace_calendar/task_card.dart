/// One task in the selected day's list.
library;

import 'package:flutter/material.dart';

import 'calendar_data.dart';
import 'harbor_theme.dart';

class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.task, required this.onMore});

  final CalendarTask task;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: HarborColors.surface,
        borderRadius: BorderRadius.circular(14.0),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16.0, 12.0, 4.0, 14.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const _StatusRing(),
                        const SizedBox(width: 6.0),
                        Text(
                          task.timeRange,
                          style: const TextStyle(
                            fontSize: 14.0,
                            color: HarborColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8.0),
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16.0,
                        fontWeight: FontWeight.w600,
                        color: HarborColors.text,
                      ),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      task.status.label,
                      style: const TextStyle(
                        fontSize: 14.0,
                        color: HarborColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_horiz),
              color: HarborColors.textMuted,
              tooltip: "Task actions",
              visualDensity: VisualDensity.compact,
              onPressed: onMore,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusRing extends StatelessWidget {
  const _StatusRing();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10.0,
      height: 10.0,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: HarborColors.primary, width: 2.5),
      ),
    );
  }
}
