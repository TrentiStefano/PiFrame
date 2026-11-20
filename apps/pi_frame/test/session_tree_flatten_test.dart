import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/features/session_tree/session_tree_dialog.dart';

void main() {
  test('forks are nested under their parent, siblings marked by isLast', () {
    final nodes = [
      {'id': 'root'},
      {'id': 'main', 'parentId': 'root'},
      {'id': 'branch', 'parentId': 'root'},
      {'id': 'deep', 'parentId': 'branch'},
    ];
    final rows = flattenSessionTree(nodes, const {});

    expect(rows.map((r) => r.node['id']), ['root', 'main', 'branch', 'deep']);
    expect(rows.map((r) => r.depth), [0, 1, 1, 2]);
    // main has a later sibling (branch), so it is not the last one.
    expect(rows[1].isLast, isFalse);
    expect(rows[2].isLast, isTrue);
    // Under branch (the last child) there is no guide; under main there would be.
    expect(rows[3].guides, [false]);
  });

  test('parents come from session entries when nodes do not carry them', () {
    final nodes = [
      {'id': 'root_user'},
      {'id': 'main_answer'},
      {'id': 'branch_answer'},
    ];
    final rows = flattenSessionTree(nodes, const {
      'root_user': null,
      'main_answer': 'root_user',
      'branch_answer': 'root_user',
    });
    expect(rows.map((r) => r.depth), [0, 1, 1]);
  });

  test('a node whose parent is unknown becomes a root, and cycles stop', () {
    final nodes = [
      {'id': 'orphan', 'parentId': 'missing'},
      {'id': 'a', 'parentId': 'b'},
      {'id': 'b', 'parentId': 'a'},
    ];
    final rows = flattenSessionTree(nodes, const {});
    // a and b only reach each other, so neither is reachable from a root and
    // neither is listed; the cycle cannot loop.
    expect(rows.map((r) => r.node['id']).toList(), ['orphan']);
  });
}
