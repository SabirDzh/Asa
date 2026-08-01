import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme.dart';

class QuantityCounter extends StatefulWidget {
  final double currentValue;
  final double targetValue;
  final String unit;
  final ValueChanged<double> onAdjust;
  final Color textColor;
  final String decreaseLabel;
  final String increaseLabel;

  const QuantityCounter({
    super.key,
    required this.currentValue,
    required this.targetValue,
    required this.unit,
    required this.onAdjust,
    required this.textColor,
    required this.decreaseLabel,
    required this.increaseLabel,
  });

  @override
  State<QuantityCounter> createState() => _QuantityCounterState();
}

class _QuantityCounterState extends State<QuantityCounter> {
  Timer? _repeatTimer;
  int _repeatCount = 0;

  bool get _canDecrease => widget.currentValue > 0;
  bool get _canIncrease => widget.currentValue < widget.targetValue;

  String _number(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  void _adjust(double delta) {
    if (delta < 0 && !_canDecrease) return;
    if (delta > 0 && !_canIncrease) return;
    widget.onAdjust(delta);
  }

  void _startRepeating(double delta) {
    _stopRepeating();
    _repeatCount = 0;
    _adjust(delta);
    _scheduleNext(delta);
  }

  void _scheduleNext(double delta) {
    final delay = switch (_repeatCount) {
      0 => const Duration(milliseconds: 220),
      1 => const Duration(milliseconds: 150),
      2 => const Duration(milliseconds: 100),
      _ => const Duration(milliseconds: 70),
    };
    _repeatTimer = Timer(delay, () {
      if (!mounted) return;
      final canContinue = delta < 0 ? _canDecrease : _canIncrease;
      if (!canContinue) {
        _stopRepeating();
        return;
      }
      _repeatCount++;
      _adjust(delta);
      if (!mounted) return;
      _scheduleNext(delta);
    });
  }

  void _stopRepeating() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  @override
  void dispose() {
    _stopRepeating();
    super.dispose();
  }

  Widget _button({
    required IconData icon,
    required String label,
    required double delta,
    required bool enabled,
  }) {
    final background = widget.textColor.withValues(
      alpha: enabled ? 0.08 : 0.04,
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => _adjust(delta) : null,
        onLongPressStart: enabled ? (_) => _startRepeating(delta) : null,
        onLongPressEnd: enabled ? (_) => _stopRepeating() : null,
        onLongPressCancel: enabled ? _stopRepeating : null,
        child: Container(
          key: ValueKey(
            delta < 0 ? 'quantity-decrement' : 'quantity-increment',
          ),
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppTheme.pillRadius),
          ),
          child: Icon(
            icon,
            color:
                enabled
                    ? widget.textColor
                    : widget.textColor.withValues(alpha: 0.35),
            size: 20,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('quantity-counter'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: Text(
            '${_number(widget.currentValue)} / ${_number(widget.targetValue)} ${widget.unit.trim()}',
            key: const ValueKey('quantity-counter-value'),
            style: TextStyle(color: widget.textColor, fontSize: 15),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        _button(
          icon: Iconsax.minus,
          label: widget.decreaseLabel,
          delta: -1,
          enabled: _canDecrease,
        ),
        const SizedBox(width: 8),
        _button(
          icon: Iconsax.add,
          label: widget.increaseLabel,
          delta: 1,
          enabled: _canIncrease,
        ),
      ],
    );
  }
}
