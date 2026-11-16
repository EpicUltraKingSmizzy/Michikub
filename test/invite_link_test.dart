import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/net/invite_link.dart';

void main() {
  test('share text starts with the invitation, then the room code and the link', () {
    expect(inviteShareText('ABCD'), 'Come play Michikub with me!\nRoom code: ABCD\nmichikub://join/ABCD');
    expect(inviteShareText(' k7mq2p '), 'Come play Michikub with me!\nRoom code: K7MQ2P\nmichikub://join/K7MQ2P');
    expect(inviteShareText('ABCD').split('\n').first, 'Come play Michikub with me!');
  });

  test('join link and reading the code back', () {
    expect(joinLink('abcd'), 'michikub://join/ABCD');
    expect(codeFromJoinLink(inviteShareText('XY7Z9Q')), 'XY7Z9Q');
    expect(codeFromJoinLink('michikub://join/abcd'), 'ABCD');
    expect(codeFromJoinLink('abcd'), 'ABCD');
    expect(codeFromJoinLink('hello there'), isNull);
  });

  test('deep link: michikub://join/CODE opens Join with that code', () {
    expect(codeFromAppLink(Uri.parse('michikub://join/ABCD')), 'ABCD');
    expect(codeFromAppLink(Uri.parse('michikub://join/k7mq2p')), 'K7MQ2P');
    expect(codeFromAppLink(Uri.parse(joinLink('ab12'))), 'AB12');
    expect(codeFromAppLink(Uri.parse('MICHIKUB://JOIN/ABCD')), 'ABCD');
    expect(codeFromAppLink(Uri.parse('michikub://join/')), isNull);
    expect(codeFromAppLink(Uri.parse('michikub://other/ABCD')), isNull);
    expect(codeFromAppLink(Uri.parse('https://join/ABCD')), isNull);
    expect(codeFromAppLink(Uri.parse('michikub://join/AB')), isNull);
  });
}
