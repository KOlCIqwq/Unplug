import 'package:flutter/material.dart';
import 'dart:async';

class InterventionScreen extends StatefulWidget {
  final int waitTimeSeconds;
  final String targetAppName;
  final String? debugInfo;

  const InterventionScreen({
    super.key,
    this.waitTimeSeconds = 10,
    this.targetAppName = 'the app',
    this.debugInfo,
  });

  @override
  State<InterventionScreen> createState() => _InterventionScreenState();
}

class _InterventionScreenState extends State<InterventionScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late int _remainingSeconds;
  Timer? _timer;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _proceeded = false;
  bool _isPopped = false;
  int _selectedMinutes = 5;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.waitTimeSeconds;

    // Breathing animation (4 seconds inhale, 4 seconds exhale)
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.5).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOutSine,
      ),
    );

    _startTimer();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused || state == AppLifecycleState.hidden) && !_proceeded && !_isPopped) {
      if (mounted && Navigator.of(context).canPop()) {
        _isPopped = true;
        Navigator.of(context).pop(false);
      }
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(
        0xFF121212,
      ), // Deep dark background for focus
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Take a deep breath...',
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 60),

              // Breathing Circle Animation
              SizedBox(
                height: 200,
                width: 200,
                child: Center(
                  child: AnimatedBuilder(
                    animation: _scaleAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _scaleAnimation.value,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.3),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 60),

              // Timer Text
              Text(
                _remainingSeconds > 0 ? '$_remainingSeconds' : 'Ready',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 40),

              // Action Buttons
              if (_remainingSeconds == 0) ...[
                Text(
                  'Set your session limit',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [1, 3, 5, 10, 15, 20].map((mins) {
                    final isSelected = _selectedMinutes == mins;
                    return ChoiceChip(
                      label: Text('$mins min${mins > 1 ? 's' : ''}'),
                      selected: isSelected,
                      selectedColor: Theme.of(context).colorScheme.primary,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedMinutes = mins;
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    if (_isPopped) return;
                    _isPopped = true;
                    _proceeded = true;
                    Navigator.of(context).pop(_selectedMinutes);
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  child: Text('Continue for $_selectedMinutes min${_selectedMinutes > 1 ? 's' : ''}'),
                ),
              ] else
                OutlinedButton(
                  onPressed: () {
                    if (_isPopped) return;
                    _isPopped = true;
                    // User successfully resisted the urge! Return false.
                    Navigator.of(context).pop(false);
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 16,
                    ),
                    side: const BorderSide(color: Colors.white54),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              /* if (widget.debugInfo != null) ...[
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    widget.debugInfo!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 10,
                    ),
                  ),
                ),
              ], */
            ],
          ),
        ),
      ),
    );
  }
}
