import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/net/invite_link.dart';
import 'package:michikub/net/peer.dart';

void main() {
  test('share text starts with the invitation, then the room code and the link', () {
    expect(inviteShareText('ABCD'), 'Come play Michikub with me!\nRoom code: ABCD\nmichikub://join/ABCD');
    expect(inviteShareText(' ktmqzp '), 'Come play Michikub with me!\nRoom code: KTMQZP\nmichikub://join/KTMQZP');
    expect(inviteShareText('ABCD').split('\n').first, 'Come play Michikub with me!');
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
  });

  test('room codes are 6 letters, no digits or look-alikes (v0.1.8)', () {
    for (var i = 0; i < 200; i++) {
      final c = randomRoomCode();
      expect(c, matches(RegExp(r'^[A-HJKMNP-Z]{6}$')));
      expect(codeFromJoinLink(inviteShareText(c)), c);
    }
  });
}
