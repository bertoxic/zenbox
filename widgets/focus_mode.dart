import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zenbox/models/model.dart';
import 'package:zenbox/theme/theme.dart';

enum FocusModeType { focus, shortBreak, longBreak }

class FocusTimerState {
  const FocusTimerState({
    required this.mode,
    required this.totalSeconds,
    required this.remainingSeconds,
    required this.isRunning,
    required this.completedSessions,
    this.targetSessions = 4,
  });

  final FocusModeType mode;
  final int totalSeconds;
  final int remainingSeconds;
  final bool isRunning;
  final int completedSessions;
  final int targetSessions;

  bool get isActive => isRunning || (remainingSeconds < totalSeconds && remainingSeconds > 0);

  String get formattedTime {
    final mins = remainingSeconds ~/ 60;
    final secs = remainingSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String get modeLabel => switch (mode) {
    FocusModeType.focus => 'Focus',
    FocusModeType.shortBreak => 'Short break',
    FocusModeType.longBreak => 'Long break',
  };

  FocusTimerState copyWith({
    FocusModeType? mode,
    int? totalSeconds,
    int? remainingSeconds,
    bool? isRunning,
    int? completedSessions,
    int? targetSessions,
  }) {
    return FocusTimerState(
      mode: mode ?? this.mode,
      totalSeconds: totalSeconds ?? this.totalSeconds,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      isRunning: isRunning ?? this.isRunning,
      completedSessions: completedSessions ?? this.completedSessions,
      targetSessions: targetSessions ?? this.targetSessions,
    );
  }
}

class FocusTimerService extends ValueNotifier<FocusTimerState> {
  FocusTimerService()
      : super(
          const FocusTimerState(
            mode: FocusModeType.focus,
            totalSeconds: 25 * 60,
            remainingSeconds: 25 * 60,
            isRunning: false,
            completedSessions: 0,
          ),
        );

  Timer? _ticker;
  void Function(String)? onToast;

  void applyMode(FocusModeType mode) {
    _ticker?.cancel();
    final minutes = switch (mode) {
      FocusModeType.focus => 25,
      FocusModeType.shortBreak => 5,
      FocusModeType.longBreak => 15,
    };
    final total = minutes * 60;
    value = value.copyWith(
      mode: mode,
      totalSeconds: total,
      remainingSeconds: total,
      isRunning: false,
    );
  }

  void modifyMinutes(int delta) {
    if (value.isRunning) return;
    final currentMinutes = (value.totalSeconds / 60).round();
    final newMinutes = (currentMinutes + delta).clamp(1, 180);
    final total = newMinutes * 60;
    value = value.copyWith(
      totalSeconds: total,
      remainingSeconds: total,
    );
  }

  void setMinutes(int minutes) {
    if (value.isRunning) return;
    final total = minutes.clamp(1, 180) * 60;
    value = value.copyWith(
      totalSeconds: total,
      remainingSeconds: total,
    );
  }

  void toggle() {
    if (value.isRunning) {
      pause();
    } else {
      start();
    }
  }

  void start() {
    int remaining = value.remainingSeconds;
    if (remaining <= 0) {
      remaining = value.totalSeconds;
    }
    _ticker?.cancel();
    value = value.copyWith(isRunning: true, remainingSeconds: remaining);

    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (value.remainingSeconds > 1) {
        value = value.copyWith(remainingSeconds: value.remainingSeconds - 1);
      } else {
        timer.cancel();
        _onComplete();
      }
    });
  }

  void pause() {
    _ticker?.cancel();
    value = value.copyWith(isRunning: false);
  }

  void reset() {
    _ticker?.cancel();
    value = value.copyWith(
      isRunning: false,
      remainingSeconds: value.totalSeconds,
    );
  }

  void _onComplete() {
    final completed = value.mode == FocusModeType.focus
        ? value.completedSessions + 1
        : value.completedSessions;
    value = value.copyWith(
      isRunning: false,
      remainingSeconds: 0,
      completedSessions: completed,
    );

    try {
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {}

    if (value.mode == FocusModeType.focus) {
      onToast?.call('🎉 Great focus session completed! Time for a well-deserved break.');
    } else {
      onToast?.call('✨ Break over! Ready to focus again?');
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

final focusTimerService = FocusTimerService();
ValueNotifier<FocusTimerState> get focusTimerNotifier => focusTimerService;

class FocusModeDock extends StatefulWidget {
  const FocusModeDock({
    super.key,
    required this.store,
    required this.onToast,
  });

  final StudioStore store;
  final void Function(String) onToast;

  @override
  State<FocusModeDock> createState() => _FocusModeDockState();
}

class _FocusModeDockState extends State<FocusModeDock> {
  final TextEditingController _goalController = TextEditingController();
  final List<Map<String, dynamic>> _sessionTasks = [];
  final TextEditingController _taskController = TextEditingController();

  @override
  void initState() {
    super.initState();
    focusTimerService.onToast = widget.onToast;
  }

  @override
  void didUpdateWidget(covariant FocusModeDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    focusTimerService.onToast = widget.onToast;
  }

  @override
  void dispose() {
    _goalController.dispose();
    _taskController.dispose();
    super.dispose();
  }

  void _applyModeDefaults(FocusModeType mode) => focusTimerService.applyMode(mode);

  void _modifyMinutes(int delta) => focusTimerService.modifyMinutes(delta);

  void _setMinutes(int minutes) => focusTimerService.setMinutes(minutes);

  void _toggleTimer() => focusTimerService.toggle();

  void _resetTimer() => focusTimerService.reset();

  FocusTimerState get _timerState => focusTimerService.value;
  FocusModeType get _currentMode => _timerState.mode;
  int get _totalSeconds => _timerState.totalSeconds;
  int get _remainingSeconds => _timerState.remainingSeconds;
  bool get _isRunning => _timerState.isRunning;
  int get _completedSessions => _timerState.completedSessions;
  int get _targetSessions => _timerState.targetSessions;

  void _editCustomMinutes() async {
    if (_isRunning) return;
    final controller = TextEditingController(text: '${(_totalSeconds / 60).round()}');
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Timer Duration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter duration in minutes (1 - 180):', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                suffixText: 'mins',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final val = int.tryParse(controller.text.trim());
              Navigator.pop(context, val);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );

    if (result != null && result > 0) {
      _setMinutes(result);
    }
  }

  String _formatTime(int totalSecs) {
    final mins = totalSecs ~/ 60;
    final secs = totalSecs % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FocusTimerState>(
      valueListenable: focusTimerService,
      builder: (context, timerState, _) {
        final progress = _totalSeconds > 0 ? (_remainingSeconds / _totalSeconds).clamp(0.0, 1.0) : 0.0;
        final modeLabel = switch (_currentMode) {
          FocusModeType.focus => 'Focus Session',
          FocusModeType.shortBreak => 'Short Break',
          FocusModeType.longBreak => 'Long Break',
        };

        return Container(
          color: paper,
          child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        children: [
          Row(
            children: [
              Icon(
                _currentMode == FocusModeType.focus ? Icons.self_improvement : Icons.coffee_outlined,
                size: 20,
                color: sage,
              ),
              const SizedBox(width: 8),
              Text(
                'Focus Studio',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _isRunning ? sage.withValues(alpha: 0.15) : cream,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _isRunning ? sage : line),
                ),
                child: Text(
                  _isRunning ? 'ACTIVE' : 'IDLE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: _isRunning ? sage : muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: cream,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: line),
            ),
            child: Row(
              children: [
                _buildModeButton('Focus', FocusModeType.focus),
                _buildModeButton('Short Break', FocusModeType.shortBreak),
                _buildModeButton('Long Break', FocusModeType.longBreak),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: SizedBox(
              width: 170,
              height: 170,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 160,
                    height: 160,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 7,
                      backgroundColor: line,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _currentMode == FocusModeType.focus ? sage : const Color(0xFFE29578),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: _isRunning ? null : _editCustomMinutes,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Text(
                            _formatTime(_remainingSeconds),
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'monospace',
                              letterSpacing: 1,
                              color: ink,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        modeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: muted,
                        ),
                      ),
                      if (!_isRunning) ...[
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: _editCustomMinutes,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_outlined, size: 11, color: sage),
                              const SizedBox(width: 3),
                              Text(
                                'customize',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: sage,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            children: [
              _buildAdjustButton('-5m', () => _modifyMinutes(-5)),
              _buildAdjustButton('-1m', () => _modifyMinutes(-1)),
              _buildAdjustButton('+1m', () => _modifyMinutes(1)),
              _buildAdjustButton('+5m', () => _modifyMinutes(5)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            children: _currentMode == FocusModeType.focus
                ? [15, 25, 45, 60].map((m) => _buildPresetChip(m)).toList()
                : _currentMode == FocusModeType.shortBreak
                    ? [3, 5, 10].map((m) => _buildPresetChip(m)).toList()
                    : [15, 20, 30].map((m) => _buildPresetChip(m)).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _isRunning ? const Color(0xFFC75B5B) : sage,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _toggleTimer,
                  icon: Icon(_isRunning ? Icons.pause : Icons.play_arrow, size: 18),
                  label: Text(
                    _isRunning ? 'Pause' : 'Start Focus',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Reset Timer',
                onPressed: _resetTimer,
                icon: const Icon(Icons.refresh, size: 18),
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  side: BorderSide(color: line),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Focus Target',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ),
              Text(
                '$_completedSessions / $_targetSessions completed',
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(_targetSessions, (i) {
              final isDone = i < _completedSessions;
              return Expanded(
                child: Container(
                  height: 6,
                  margin: EdgeInsets.only(right: i < _targetSessions - 1 ? 4 : 0),
                  decoration: BoxDecoration(
                    color: isDone ? sage : line,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          Text(
            'Current Study Intention',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _goalController,
            style: TextStyle(fontSize: 12, color: ink),
            decoration: InputDecoration(
              hintText: 'e.g., Memorize formulas, finish chapter 4 summary',
              hintStyle: TextStyle(fontSize: 11, color: muted),
              prefixIcon: Icon(Icons.track_changes, size: 16, color: sage),
              filled: true,
              fillColor: cream,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: line),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'Session Checklist',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const Spacer(),
              if (_sessionTasks.isNotEmpty)
                Text(
                  '${_sessionTasks.where((t) => t['done'] == true).length}/${_sessionTasks.length}',
                  style: TextStyle(fontSize: 10, color: muted),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _taskController,
                  style: TextStyle(fontSize: 11, color: ink),
                  decoration: InputDecoration(
                    hintText: 'Add quick step...',
                    hintStyle: TextStyle(fontSize: 11, color: muted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: line),
                    ),
                  ),
                  onSubmitted: (_) => _addTask(),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Add Step',
                icon: const Icon(Icons.add, size: 18),
                onPressed: _addTask,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_sessionTasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No mini-tasks added yet. Break your session into bite-sized steps!',
                style: TextStyle(fontSize: 10, color: muted, fontStyle: FontStyle.italic),
              ),
            )
          else
            ..._sessionTasks.asMap().entries.map((entry) {
              final idx = entry.key;
              final task = entry.value;
              final isDone = task['done'] as bool? ?? false;
              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cream,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: line),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: Checkbox(
                        value: isDone,
                        activeColor: sage,
                        onChanged: (val) {
                          setState(() => task['done'] = val ?? false);
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        task['title'] as String? ?? '',
                        style: TextStyle(
                          fontSize: 11,
                          decoration: isDone ? TextDecoration.lineThrough : null,
                          color: isDone ? muted : ink,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 14),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        setState(() => _sessionTasks.removeAt(idx));
                      },
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  },
);
  }

  void _addTask() {
    final text = _taskController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _sessionTasks.add({'title': text, 'done': false});
      _taskController.clear();
    });
  }

  Widget _buildModeButton(String label, FocusModeType mode) {
    final isSelected = _currentMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () => _applyModeDefaults(mode),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? paper : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? ink : muted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdjustButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: _isRunning ? null : onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: cream,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: _isRunning ? muted : ink,
          ),
        ),
      ),
    );
  }

  Widget _buildPresetChip(int minutes) {
    final isSelected = (_totalSeconds / 60).round() == minutes;
    return InkWell(
      onTap: _isRunning ? null : () => _setMinutes(minutes),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? sage : cream,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? sage : line),
        ),
        child: Text(
          '${minutes}m',
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : ink,
          ),
        ),
      ),
    );
  }
}
