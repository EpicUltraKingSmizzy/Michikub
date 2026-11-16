import 'package:flutter/material.dart';

/// Michikub palette: mahogany browns, crimson velvet and gold.
class MK {
  static const ink = Color(0xFF0B0705);
  static const mahoganyDark = Color(0xFF2A0E07);
  static const mahogany = Color(0xFF5A1E0E);
  static const mahoganyLight = Color(0xFF8A3A1C);
  static const crimsonDark = Color(0xFF2A0308);
  static const crimson = Color(0xFF6E0E1C);
  static const crimsonLight = Color(0xFF8A1626);
  static const gold = Color(0xFFD9B45A);
  static const goldLight = Color(0xFFFBE08A);
  static const goldDeep = Color(0xFF8A5D0E);
  static const cream = Color(0xFFF7F3E8);
  static const creamText = Color(0xFFF3E6CC);
  static const red = Color(0xFFD3232A);
  static const blue = Color(0xFF1565C0);
  static const yellow = Color(0xFFF0A500);
  static const black = Color(0xFF191919);
  static const danger = Color(0xFFFF5A4E);

  static const goldGradient = LinearGradient(
    begin: Alignment(-1, -1),
    end: Alignment(1, 1),
    colors: [Color(0xFFFFF3B8), Color(0xFFF4CF5C), Color(0xFFD9A634), Color(0xFFB98620), Color(0xFFE6BB48), Color(0xFFFBE08A)],
    stops: [0, .18, .42, .58, .78, 1],
  );

  static const velvetGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF2A0308), Color(0xFF5A0A16), Color(0xFF6E0E1C), Color(0xFF4A0812), Color(0xFF200206)],
    stops: [0, .25, .5, .8, 1],
  );

  static const lipGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF8A1626), Color(0xFF6E0E1C), Color(0xFF480812), Color(0xFF24030A)],
    stops: [0, .4, .75, 1],
  );

  static TextStyle title(double size) => TextStyle(
        fontFamily: 'Playfair',
        fontWeight: FontWeight.w800,
        fontSize: size,
        color: creamText,
        letterSpacing: 0.5,
      );

  static TextStyle body(double size, {Color color = creamText, FontWeight weight = FontWeight.w500}) =>
      TextStyle(fontFamily: 'Rubik', fontSize: size, color: color, fontWeight: weight);

  static ThemeData theme() => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: ink,
        fontFamily: 'Rubik',
        colorScheme: const ColorScheme.dark(
          primary: gold,
          secondary: crimsonLight,
          surface: Color(0xFF1E0A06),
          onPrimary: Color(0xFF2A1404),
          onSurface: creamText,
        ),
        dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF241009)),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? gold : const Color(0xFF9A8670)),
          trackColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? crimsonLight : const Color(0xFF3A2016)),
        ),
        sliderTheme: const SliderThemeData(activeTrackColor: gold, thumbColor: goldLight, inactiveTrackColor: Color(0xFF4A2A1A)),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1A0905),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: gold)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: gold.withValues(alpha: .5))),
          focusedBorder:
              OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: goldLight, width: 1.6)),
        ),
        snackBarTheme: const SnackBarThemeData(backgroundColor: Color(0xFF2A1208), contentTextStyle: TextStyle(color: creamText)),
      );
}

/// The mahogany table texture with a soft vignette.
class WoodBackground extends StatelessWidget {
  final Widget child;
  const WoodBackground({super.key, required this.child});
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          color: MK.mahogany,
          image: DecorationImage(image: AssetImage('assets/textures/mahogany.jpg'), fit: BoxFit.cover),
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              radius: 1.2,
              colors: [Color(0x00000000), Color(0x88000000)],
              stops: [.55, 1],
            ),
          ),
          child: child,
        ),
      );
}

/// A gold-edged dark panel used for menus and forms.
class MkPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const MkPanel({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xEE2A1009), Color(0xEE160704)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MK.gold.withValues(alpha: .75), width: 1.2),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18, offset: Offset(0, 6))],
        ),
        child: child,
      );
}

/// Primary gold pill button.
class GoldButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool compact;
  final bool crimson;
  const GoldButton(this.label, {super.key, this.icon, this.onPressed, this.compact = false, this.crimson = false});
  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = crimson ? MK.creamText : const Color(0xFF2A1404);
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(40),
          onTap: onPressed,
          child: Ink(
            padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 22, vertical: compact ? 8 : 12),
            decoration: BoxDecoration(
              gradient: crimson ? MK.lipGradient : MK.goldGradient,
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: crimson ? MK.gold : MK.goldDeep, width: 1.2),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: compact ? 16 : 20, color: fg), SizedBox(width: compact ? 6 : 8)],
                Text(label, style: MK.body(compact ? 13 : 16, color: fg, weight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Round dark button with a gold ring (table controls).
class RingButton extends StatelessWidget {
  final IconData? icon;
  final Widget? child;
  final String? caption;
  final VoidCallback? onPressed;
  final double size;
  const RingButton({super.key, this.icon, this.child, this.caption, this.onPressed, this.size = 44});
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onPressed == null ? .45 : 1,
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(colors: [Color(0xFF3A160C), Color(0xFF1A0805)]),
              border: Border.all(color: MK.gold, width: 1.4),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                child ?? Icon(icon, color: MK.goldLight, size: size * .42),
                if (caption != null)
                  Text(caption!, style: MK.body(size * .15, color: MK.goldLight, weight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
}

/// Screen scaffold with the wood background and a gold title bar.
class MkScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget> actions;
  final bool showBack;

  /// Long-press on the title (e.g. "Room ABCD" copies the code).
  final VoidCallback? onTitleLongPress;
  const MkScaffold(
      {super.key, required this.title, required this.body, this.actions = const [], this.showBack = true, this.onTitleLongPress});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: WoodBackground(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 12, 2),
                  child: Row(children: [
                    if (showBack)
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, color: MK.goldLight, size: 20),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    if (onTitleLongPress == null)
                      Text(title, style: MK.title(22))
                    else
                      GestureDetector(onLongPress: onTitleLongPress, child: Text(title, style: MK.title(22))),
                    const Spacer(),
                    ...actions,
                  ]),
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      );
}

const seatColors = [Color(0xFFB0202C), Color(0xFF2F5FB0), Color(0xFF2E7D5B), Color(0xFFB07A1C)];

/// A dialog for typing into, built to survive a phone in landscape with the keyboard taking
/// most of the height: the title, content and buttons scroll together (buttons always below
/// the content), the title and spacing shrink when space is tight, and text fields keep their
/// natural height.
class MkFormDialog extends StatelessWidget {
  /// Optional: no title row at all when null.
  final String? title;
  final Widget content;
  final List<Widget> actions;
  final double maxWidth;
  const MkFormDialog({super.key, this.title, required this.content, required this.actions, this.maxWidth = 460});

  /// Below this height (dialog space left above the keyboard) the layout gets compact.
  static const double tightHeight = 240;

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 6),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: LayoutBuilder(builder: (context, c) {
            final tight = c.maxHeight < tightHeight;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, tight ? 8 : 18, 20, tight ? 2 : 10),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (title != null) ...[
                  Text(title!, style: MK.title(tight ? 16 : 20)),
                  SizedBox(height: tight ? 2 : 10),
                ],
                content,
                SizedBox(height: tight ? 0 : 6),
                Wrap(alignment: WrapAlignment.end, spacing: 4, children: actions),
              ]),
            );
          }),
        ),
      );
}
