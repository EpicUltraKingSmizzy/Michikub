import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/keep_alive.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/net/online.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keep-alive is a no-op off Android', () async {
    await LinkKeepAlive.start('x');
    expect(LinkKeepAlive.active, false);
    await LinkKeepAlive.stop();
  });

  test('host away pauses the turn clock and resumes it on return', () {
    final net = NetHost('Ann', const HouseRules(turnSeconds: 60), open: false);
    final session = net.start();
    final h = net.host!;
    expect(h.msLeft, isNotNull);
    net.setAway(true);
    expect(net.away, true);
    expect(h.msLeft, isNull);
    net.setAway(false);
    expect(net.away, false);
    expect(h.msLeft, isNotNull);
    session.leave();
  });

}
