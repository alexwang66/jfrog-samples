import 'package:jfrog_pub_sample/jfrog_pub_sample.dart';
import 'package:test/test.dart';

void main() {
  test('greeting returns the expected message', () {
    expect(greeting('JFrog'), 'Hello, JFrog!');
  });
}
