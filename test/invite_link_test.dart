import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/net/invite_link.dart';
import 'package:michikub/net/peer.dart';

void main() {
  test('share text: two lines, the invitation with the code, then the web link (no michikub:// line)', () {
    expect(inviteShareText('ABCD'), 'Come play Michikub with me! Code ABCD\nhttps://epicultrakingsmizzy.github.io/Michikub/?join=ABCD');
    expect(inviteShareText(' ktmqzp '), 'Come play Michikub with me! Code KTMQZP\nhttps://epicultrakingsmizzy.github.io/Michikub/?join=KTMQZP');
    expect(inviteShareText('ABCD'), isNot(contains('michikub://')));
    expect(codeFromJoinLink(inviteShareText('wxyz')), 'WXYZ', reason: 'pasting the whole invite into Join keeps the code');
  });

  test('join link and reading the code back', () {
    expect(joinLink('abcd'), 'michikub://join/ABCD');
    expect(codeFromJoinLink(inviteShareText('XYTZRQ')), 'XYTZRQ');
    expect(codeFromJoinLink('michikub://join/abcd'), 'ABCD');
    expect(codeFromJoinLink('abcd'), 'ABCD');
    expect(codeFromJoinLink('hello there'), isNull);
    expect(codeFromJoinLink('AB12'), isNull, reason: 'letters only');
  });

  test('deep link: michikub://join/CODE opens Join with that code', () {
    expect(codeFromAppLink(Uri.parse('michikub://join/ABCD')), 'ABCD');
    expect(codeFromAppLink(Uri.parse('michikub://join/ktmqzp')), 'KTMQZP');
    expect(codeFromAppLink(Uri.parse(joinLink('abcd'))), 'ABCD');
    expect(codeFromAppLink(Uri.parse('michikub://join/AB12')), isNull, reason: 'letters only');
    expect(codeFromAppLink(Uri.parse('MICHIKUB://JOIN/ABCD')), 'ABCD');
    expect(codeFromAppLink(Uri.parse('michikub://join/')), isNull);
    expect(codeFromAppLink(Uri.parse('michikub://other/ABCD')), isNull);
    expect(codeFromAppLink(Uri.parse('https://join/ABCD')), isNull);
    expect(codeFromAppLink(Uri.parse('michikub://join/AB')), isNull);
    // The web version's link.
    expect(codeFromAppLink(Uri.parse(webJoinLink('abcd'))), 'ABCD');
    expect(codeFromAppLink(Uri.parse('https://epicultrakingsmizzy.github.io/Michikub/?join=ktmqzp')), 'KTMQZP');
    expect(codeFromAppLink(Uri.parse('https://epicultrakingsmizzy.github.io/Michikub/?join=AB12')), isNull);
    expect(codeFromAppLink(Uri.parse('https://epicultrakingsmizzy.github.io/Michikub/')), isNull);
    expect(codeFromJoinLink('https://epicultrakingsmizzy.github.io/Michikub/?join=xytz'), 'XYTZ');
  });

  test('room codes are 6 letters, no digits or look-alikes (v0.1.8)', () {
    for (var i = 0; i < 200; i++) {
      final c = randomRoomCode();
      expect(c, matches(RegExp(r'^[A-HJKMNP-Z]{6}$')));
      expect(codeFromJoinLink(inviteShareText(c)), c);
    }
  });
}
