import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../services/prompt_service.dart';

class InterventionScreen extends StatefulWidget {
  final int waitTimeSeconds;
  final String targetAppName;
  final String? debugInfo;
  final bool isZenBlock;
  final bool isLimitBlock;
  final int usedMinutes;
  final int limitMinutes;

  const InterventionScreen({
    super.key,
    this.waitTimeSeconds = 10,
    this.targetAppName = 'the app',
    this.debugInfo,
    this.isZenBlock = false,
    this.isLimitBlock = false,
    this.usedMinutes = 0,
    this.limitMinutes = 0,
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
  bool _showQuotes = true;
  String _phrase = PromptService.getRandomCuratedPrompt();

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.waitTimeSeconds;

    final available = _getAvailableSessionMinutes();
    if (!available.contains(_selectedMinutes)) {
      _selectedMinutes = available.contains(5) ? 5 : available.last;
    }

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
    _loadQuoteSettings();
    WidgetsBinding.instance.addObserver(this);
  }

  void _loadQuoteSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final bool show = prefs.getBool('show_quotes') ?? true;
    if (mounted) {
      setState(() {
        _showQuotes = show;
      });
    }
    if (show) {
      _loadDailyQuote();
    }
  }

  List<int> _getAvailableSessionMinutes() {
    final defaultPresets = [1, 3, 5, 10, 15, 20];
    if (widget.limitMinutes <= 0) {
      return defaultPresets;
    }
    final remaining = widget.limitMinutes - widget.usedMinutes;
    if (remaining <= 0) {
      return [1];
    }

    final options = defaultPresets.where((m) => m <= remaining).toList();
    if (!options.contains(remaining) && remaining > 0) {
      options.add(remaining);
      options.sort();
    }
    return options.isEmpty ? [remaining] : options;
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

  void _cycleNextQuote() {
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
    if (widget.isZenBlock || widget.isLimitBlock) return;
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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

                          // App Logo Icon
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              'assets/logo.png',
                              width: 54,
                              height: 54,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Quote Text (if enabled in settings)
                          if (_showQuotes) ...[
                            GestureDetector(
                              onTap: _cycleNextQuote,
                              child: SizedBox(
                                width: double.infinity,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                                  child: Text(
                                    _phrase,
                                    textAlign: TextAlign.center,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: colorScheme.onSurface.withValues(alpha: 0.9),
                                      fontWeight: FontWeight.w400,
                                      fontStyle: FontStyle.italic,
                                      height: 1.35,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

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
                                        color: colorScheme.primary.withValues(alpha: 0.25),
                                        border: Border.all(
                                          color: colorScheme.primary,
                                          width: 2.5,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Timer / Status Text
                          Center(
                            child: Text(
                              widget.isLimitBlock
                                  ? 'Daily Limit Reached'
                                  : widget.isZenBlock
                                      ? 'Zen Space Active'
                                      : _remainingSeconds > 0 ? '$_remainingSeconds' : 'Ready',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),

                          if (widget.isLimitBlock) ...[
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Text(
                                'You have reached your daily limit of ${widget.limitMinutes}m for ${widget.targetAppName} (Used: ${widget.usedMinutes}m today).',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                              ),
                            ),
                          ] else if (!widget.isZenBlock && widget.limitMinutes > 0) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Daily usage: ${widget.usedMinutes}m / ${widget.limitMinutes}m',
                                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                              ),
                            ),
                          ],

                          const SizedBox(height: 24),

                          // Action Buttons
                          if (!widget.isZenBlock && !widget.isLimitBlock && _remainingSeconds == 0) ...[
                            Text(
                              widget.limitMinutes > 0
                                  ? 'Set your session limit (${widget.limitMinutes - widget.usedMinutes}m left today)'
                                  : 'Set your session limit',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
                                children: _getAvailableSessionMinutes().map((mins) {
                                  final isSelected = _selectedMinutes == mins;
                                  return ChoiceChip(
                                    label: Text('$mins min${mins > 1 ? 's' : ''}'),
                                    selected: isSelected,
                                    selectedColor: colorScheme.primaryContainer,
                                    labelStyle: TextStyle(
                                      color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
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
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                                side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.6)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: Text(
                                widget.isLimitBlock ? 'Close' : 'Cancel',
                                style: TextStyle(color: colorScheme.onSurface),
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
