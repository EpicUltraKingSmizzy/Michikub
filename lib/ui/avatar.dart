import 'package:flutter/material.dart';

import '../app/avatars.dart';
import '../app/prefs.dart';
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
    // [image] is an avatar id (see avatars.dart): a picture, or a letter avatar's colour.
    final image = avatarImage(this.image);
    final color = avatarColor(this.image) ?? this.color;
    // The drawn avatars (assets/avatars/) carry their own gold ring, so they replace the frame's.
    final ownRing = image != null && image.startsWith('assets/avatars/');
    final face = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: image != null ? const Color(0xFF16100C) : color,
        border: ownRing ? null : Border.all(color: ringColor, width: ringWidth),
        boxShadow: [
          if (current) const BoxShadow(color: Color(0xAAFFD36B), blurRadius: 14, spreadRadius: 2),
          const BoxShadow(color: Colors.black54, blurRadius: 5, offset: Offset(0, 2)),
        ],
      ),
      alignment: Alignment.center,
      child: image != null
          ? ClipOval(
              child: Image.asset(image, width: ownRing ? size : inner, height: ownRing ? size : inner, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
            )
          : Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: MK.body(size * .42, color: Colors.white, weight: FontWeight.w700),
            ),
    );
    return onLongPress == null ? face : GestureDetector(behavior: HitTestBehavior.opaque, onLongPress: onLongPress, child: face);
  }
}

/// Opens "Select your avatar": a grid of the avatar set. Picking one saves it (it's used in
/// every game and sent to online players). Returns the id picked, or null.
Future<String?> showAvatarPicker(BuildContext context) async {
  final prefs = AppPrefs.instance;
  final picked = await showDialog<String>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: MkPanel(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: Text('Select your avatar', style: MK.title(20))),
              IconButton(key: const ValueKey('avatarClose'), onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, color: MK.goldLight)),
            ]),
            Flexible(
              child: GridView.extent(
                shrinkWrap: true,
                maxCrossAxisExtent: 64,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  for (final id in avatarChoices)
                    GestureDetector(
                      key: ValueKey('avatar:$id'),
                      onTap: () => Navigator.pop(ctx, id),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [if (id == prefs.avatar) const BoxShadow(color: Color(0xEEFFE9A8), blurRadius: 10, spreadRadius: 3)],
                        ),
                        child: PlayerAvatar(size: 56, name: prefs.name, image: id),
                      ),
                    ),
                ],
              ),
            ),
          ]),
        ),
      ),
    ),
  );
  if (picked != null) {
    prefs.avatar = picked;
    await prefs.save();
  }
  return picked;
}

/// Your avatar, tappable to change it (Options and Join screens).
class MyAvatarButton extends StatefulWidget {
  final double size;
  const MyAvatarButton({super.key, this.size = 48});
  @override
  State<MyAvatarButton> createState() => _MyAvatarButtonState();
}

class _MyAvatarButtonState extends State<MyAvatarButton> {
  @override
  Widget build(BuildContext context) {
    final prefs = AppPrefs.instance;
    return Tooltip(
      message: 'Select your avatar',
      child: GestureDetector(
        key: const ValueKey('avatarButton'),
        onTap: () async {
          await showAvatarPicker(context);
          if (mounted) setState(() {});
        },
        child: PlayerAvatar(size: widget.size, name: prefs.name, image: prefs.avatar),
      ),
    );
  }
}
