import 'package:flutter/material.dart';
import 'dart:async';
import '../services/prompt_service.dart';

class InterventionScreen extends StatefulWidget {
  final int waitTimeSeconds;
  final String targetAppName;
  final String? debugInfo;
  final bool isZenBlock;

  const InterventionScreen({
    super.key,
    this.waitTimeSeconds = 10,
    this.targetAppName = 'the app',
    this.debugInfo,
    this.isZenBlock = false,
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
  String _phrase = PromptService.getRandomCuratedPrompt();

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.waitTimeSeconds;

    // Breathing animation (4 seconds inhale, 4 seconds exhale)
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.4).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOutSine,
      ),
    );

    _startTimer();
    _loadDailyQuote();
    WidgetsBinding.instance.addObserver(this);
  }

  void _loadDailyQuote() {
    PromptService.getNextQuote().then((quote) {
      if (mounted && quote.isNotEmpty) {
        setState(() {
          _phrase = quote;
        });
      }
    });
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
    if (widget.isZenBlock) return;
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
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                  minWidth: constraints.maxWidth,
                ),
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Spacer(flex: 1),

                          // Quote Text
                          SizedBox(
                            width: double.infinity,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12.0),
                              child: Text(
                                _phrase,
                                textAlign: TextAlign.center,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w400,
                                  fontStyle: FontStyle.italic,
                                  height: 1.35,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Breathing Circle Animation
                          SizedBox(
                            height: 140,
                            width: 140,
                            child: Center(
                              child: AnimatedBuilder(
                                animation: _scaleAnimation,
                                builder: (context, child) {
                                  return Transform.scale(
                                    scale: _scaleAnimation.value,
                                    child: Container(
                                      width: 75,
                                      height: 75,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
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

                          const SizedBox(height: 24),

                          // Timer Text
                          Center(
                            child: Text(
                              widget.isZenBlock
                                  ? 'Zen Space Active'
                                  : _remainingSeconds > 0 ? '$_remainingSeconds' : 'Ready',
                              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Action Buttons
                          if (!widget.isZenBlock && _remainingSeconds == 0) ...[
                            Text(
                              'Set your session limit',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
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
                            ),
                            const SizedBox(height: 20),
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
                                  vertical: 14,
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
                                Navigator.of(context).pop(false);
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 48,
                                  vertical: 14,
                                ),
                                side: const BorderSide(color: Colors.white54),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),

                          const Spacer(flex: 2),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
