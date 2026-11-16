import 'package:flutter/material.dart';

import 'theme.dart';

/// The one circular avatar frame every player uses: a 3 px #c9a24a gold ring and a drop shadow,
/// with either the robot's art (clipped to a circle) or the player's initial on their seat colour.
/// The player whose turn it is also gets a soft gold glow.
class PlayerAvatar extends StatelessWidget {
  static const ringColor = Color(0xFFC9A24A);
  static const ringWidth = 3.0;

  final double size;
  final String? image;
  final String name;
  final Color color;
  final bool current;
  final VoidCallback? onLongPress;

  const PlayerAvatar({
    super.key,
    required this.size,
    required this.name,
    this.image,
    this.color = const Color(0xFF3A1F14),
    this.current = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final inner = size - ringWidth * 2;
    final face = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: image != null ? const Color(0xFF16100C) : color,
        border: Border.all(color: ringColor, width: ringWidth),
        boxShadow: [
          if (current) const BoxShadow(color: Color(0xAAFFD36B), blurRadius: 14, spreadRadius: 2),
          const BoxShadow(color: Colors.black54, blurRadius: 5, offset: Offset(0, 2)),
        ],
      ),
      alignment: Alignment.center,
      child: image != null
          ? ClipOval(
              child: Image.asset(image!, width: inner, height: inner, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
            )
          : Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: MK.body(size * .42, color: Colors.white, weight: FontWeight.w700),
            ),
    );
    return onLongPress == null ? face : GestureDetector(behavior: HitTestBehavior.opaque, onLongPress: onLongPress, child: face);
  }
}
