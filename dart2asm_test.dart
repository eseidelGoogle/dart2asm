import "package:test/test.dart";
import "dart2asm.dart";

void main() {
  test("parseAssemblyFromStderr simple", () {
    var input =
        """Code for optimized function 'file:///src/dart2asm/default.dart_::_main_main' {
        ;; Enter frame
0x3239c50    e92d4860               stmdb sp!, {pp, r6, fp, lr}
""";
    AssemblyParserResult result = parseAssemblyFromStderr(input);
    expect(result.stderr, equals(""));
    expect(
        result.assembly,
        equals('_main_main:\n'
            '        ;; Enter frame\n'
            '0x3239c50    e92d4860               stmdb sp!, {pp, r6, fp, lr}'));
  });
  test("parseAssemblyFromStderr medium", () {
    var input =
        """Code for optimized function 'file:///src/dart2asm/default.dart_::_main_main' {
        ;; Enter frame
0x3239c50    e92d4860               stmdb sp!, {pp, r6, fp, lr}
}
Unable to write snapshot file '/var/folders/pv/54yz_0_n2tv2__qp5h959kzr0026zg/T/yzPV9k'
""";
    AssemblyParserResult result = parseAssemblyFromStderr(input);
    expect(
        result.stderr,
        equals(
            "Unable to write snapshot file \'/var/folders/pv/54yz_0_n2tv2__qp5h959kzr0026zg/T/yzPV9k\'"));
    expect(
        result.assembly,
        equals('_main_main:\n'
            '        ;; Enter frame\n'
            '0x3239c50    e92d4860               stmdb sp!, {pp, r6, fp, lr}'));
  });
}
