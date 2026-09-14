// ignore_for_file: invalid_use_of_protected_member
part of '../../studio.dart';

extension _StudioStatusBar on _StudioState {
  Widget statusBar() {
    final runningStudyTools = BackgroundQuizManager.instance.tasksNotifier.value
        .where((task) => task.status == BackgroundQuizStatus.running)
        .toList();
    return Container(
      height: 27,
      color: paper,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Icon(
            store.error == null
                ? Icons.check_circle_outline
                : Icons.error_outline,
            size: 11,
            color: store.error == null ? sage : Colors.red,
          ),
          const SizedBox(width: 6),
          Text(store.saveState, style: TextStyle(fontSize: 9, color: muted)),
          const SizedBox(width: 20),
          Text(
            '${project.objects.length} objects',
            style: TextStyle(fontSize: 9, color: muted),
          ),
          const Spacer(),
          if (runningStudyTools.isNotEmpty) ...[
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.7, color: sage),
            ),
            const SizedBox(width: 7),
            Text(
              runningStudyTools.length == 1
                  ? 'Generating ${runningStudyTools.first.output == StudyToolOutput.quiz ? 'quiz' : 'flashcards'}…'
                  : 'Generating ${runningStudyTools.length} study tools…',
              style: TextStyle(
                fontSize: 9,
                color: sage,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 18),
          ],
          if (importing) ...[
            Text(
              'Importing files…',
              style: TextStyle(fontSize: 9, color: muted),
            ),
            const SizedBox(width: 8),
          ],
          ValueListenableBuilder<FocusTimerState>(
            valueListenable: focusTimerNotifier,
            builder: (context, timerState, _) {
              if (!timerState.isActive) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 20),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      setState(() {
                        dock = 'Focus';
                        showDock = true;
                      });
                      saveLayout();
                    },
                    icon: Icon(
                      timerState.isRunning
                          ? Icons.timer_outlined
                          : Icons.pause_circle_outline,
                      size: 11,
                      color: timerState.isRunning ? sage : muted,
                    ),
                    label: Text(
                      '${timerState.modeLabel} ${timerState.formattedTime}',
                      style: TextStyle(
                        fontSize: 9,
                        color: timerState.isRunning ? sage : muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              );
            },
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 20),
            ),
            onPressed: () {
              setState(() => showTray = !showTray);
              saveLayout();
            },
            child: Text(
              '${showTray ? 'Hide' : 'Show'} temporary tray',
              style: TextStyle(fontSize: 9, color: muted),
            ),
          ),
          const SizedBox(width: 15),
          Text(
            'MADE FOR YOUR NEXT IDEA',
            style: TextStyle(fontSize: 8, color: muted, letterSpacing: 1.2),
          ),
        ],
      ),
    );
  }
}
