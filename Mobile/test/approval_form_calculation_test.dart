import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/todos/domain/approval_form_calculation.dart';

void main() {
  for (final sample
      in <({String expression, String mode, int scale, num expected})>[
        (expression: '1.005', mode: 'half_up', scale: 2, expected: 1.01),
        (expression: '-1.005', mode: 'half_up', scale: 2, expected: -1.01),
        (expression: '4.015', mode: 'half_up', scale: 2, expected: 4.02),
        (expression: '0.29 * 100', mode: 'floor', scale: 0, expected: 29),
        (expression: '0.29 * 100', mode: 'truncate', scale: 0, expected: 29),
        (
          expression: '(0.1 + 0.2) * 10',
          mode: 'ceiling',
          scale: 0,
          expected: 3,
        ),
        (expression: '1 / 3 * 3', mode: 'half_up', scale: 8, expected: 1),
        (
          expression: '1.004999999999999999',
          mode: 'half_up',
          scale: 2,
          expected: 1,
        ),
        (
          expression: '1.005000000000000001',
          mode: 'half_up',
          scale: 2,
          expected: 1.01,
        ),
        (
          expression: '0.000000005',
          mode: 'half_up',
          scale: 8,
          expected: 0.00000001,
        ),
        (
          expression: '-0.000000005',
          mode: 'half_up',
          scale: 8,
          expected: -0.00000001,
        ),
        (expression: '-1.001', mode: 'floor', scale: 2, expected: -1.01),
        (expression: '-1.001', mode: 'ceiling', scale: 2, expected: -1),
        (expression: '-1.009', mode: 'truncate', scale: 2, expected: -1),
      ]) {
    test('decimal ${sample.mode} ${sample.expression} at ${sample.scale}', () {
      final result = _calculate(
        sample.expression,
        scale: sample.scale,
        mode: sample.mode,
      );
      expect(result.errors, isEmpty);
      expect(result.values['answer'], sample.expected);
    });
  }

  test('decimal input reference retains midpoint and scientific precision', () {
    for (final input in ['1.005', '1005e-3', '  +1.005  ']) {
      final result = _calculate('input', input: input);
      expect(result.errors, isEmpty);
      expect(result.values['answer'], 1.01, reason: input);
    }
  });

  test('decimal rounded dependency is used by the second formula', () {
    final result = evaluateApprovalFormCalculations(
      fields: const [
        ApprovalFormCalculationField(
          id: 'input',
          label: '原始费用',
          type: 'amount',
        ),
        ApprovalFormCalculationField(
          id: 'cost',
          label: '成本',
          type: 'amount',
          calculation: ApprovalFormCalculation(
            expression: 'amount * 3',
            scale: 2,
            roundingMode: 'half_up',
          ),
        ),
        ApprovalFormCalculationField(
          id: 'amount',
          label: '请款金额',
          type: 'amount',
          calculation: ApprovalFormCalculation(
            expression: 'input',
            scale: 2,
            roundingMode: 'half_up',
          ),
        ),
      ],
      sourceValues: const {'input': '1.005'},
    );
    expect(result.errors, isEmpty);
    expect(result.values['amount'], 1.01);
    expect(result.values['cost'], 3.03);
  });

  for (final expression in [
    '79228162514264337593543950336',
    '-79228162514264337593543950336',
    '79228162514264337593543950335 + 1',
    'input',
  ]) {
    test(
      'decimal rejects overflow even without an arithmetic operator $expression',
      () {
        final result = _calculate(
          expression,
          input: '79228162514264337593543950336',
          scale: 0,
        );
        expect(result.values.containsKey('answer'), isFalse);
        expect(result.errors['answer'], contains('精度'));
      },
    );
  }

  test('decimal preserves large field value through JSON roundtrip', () {
    final result = _calculate('input + 0.01', input: '90071992547409.92');
    expect(result.errors, isEmpty);
    final encoded =
        jsonDecode(jsonEncode(result.values)) as Map<String, dynamic>;
    expect(encoded['answer'].toString(), '90071992547409.93');
  });

  test('decimal preserves the existing maximum instead of rounding it up', () {
    final result = _calculate('79228162514264337593543950335', scale: 0);
    expect(result.errors, isEmpty);
    expect(result.values['answer'].toString(), '79228162514264337593543950335');
  });

  test('decimal avoids JSON integer loss in binary-number consumers', () {
    final result = _calculate('input', input: '9007199254740993', scale: 0);
    expect(result.errors, isEmpty);
    final decoded = jsonDecode(jsonEncode(result.values['answer']));
    final consumerText = decoded is num
        ? decoded.toDouble().toStringAsFixed(0) : decoded;
    expect(consumerText, '9007199254740993');
    expect(result.values['answer'], '9007199254740993');
  });

  test(
    'decimal invalid input and missing references cannot retain stale answers',
    () {
      for (final input in ['NaN', 'Infinity', 'not-a-number', '1e999999999']) {
        final result = _calculate('input / 2', input: input);
        expect(result.errors['answer'], isNotNull);
        expect(result.values.containsKey('answer'), isFalse);
      }
      expect(_calculate('deleted + 1').errors['answer'], contains('引用字段不存在'));
      expect(_calculate('input / 0', input: '1').errors['answer'], '不能除以零');
    },
  );

  test('decimal rejects coefficient precision overflow after rounding', () {
    final result = _calculate('7922816251426433759354395033.51');
    expect(result.values.containsKey('answer'), isFalse);
    expect(result.errors['answer'], contains('精度'));
    final integerWithScale = _calculate('79228162514264337593543950335');
    expect(integerWithScale.errors, isEmpty);
    expect(
      integerWithScale.values['answer'],
      '79228162514264337593543950335.00',
    );
  });

  test('decimal rounding agrees with integer mill-unit oracle', () {
    for (var milli = -2000; milli <= 2000; milli += 7) {
      final absolute = milli.abs();
      final input =
          '${milli < 0 ? '-' : ''}${absolute ~/ 1000}.'
          '${(absolute % 1000).toString().padLeft(3, '0')}';
      final cents =
          (absolute ~/ 10 + (absolute % 10 >= 5 ? 1 : 0)) *
          (milli < 0 ? -1 : 1);
      expect(
        _calculate('input', input: input).values['answer'],
        cents / 100,
        reason: input,
      );
    }
  });

  test('decimal has bounded input and expression complexity', () {
    expect(_calculate('input', input: '1${'0' * 1024}').errors, isNotEmpty);
    expect(_calculate('${'(' * 40}1${')' * 40}').errors, isNotEmpty);
    expect(_calculate('${'1+' * 130}1').errors, isNotEmpty);
    expect(_calculate('1', scale: 9).errors, isNotEmpty);
  });

  const fields = [
    ApprovalFormCalculationField(id: 'original', label: '原始费用', type: 'amount'),
    ApprovalFormCalculationField(id: 'ratio', label: '结算比例', type: 'number'),
    ApprovalFormCalculationField(
      id: 'exchangeRate',
      label: '汇率',
      type: 'number',
    ),
    ApprovalFormCalculationField(
      id: 'memberCount',
      label: '会员人数',
      type: 'number',
    ),
    ApprovalFormCalculationField(
      id: 'amount',
      label: '请款金额',
      type: 'amount',
      calculation: ApprovalFormCalculation(
        expression: 'original * ratio / exchangeRate',
        scale: 2,
        roundingMode: 'half_up',
      ),
    ),
    ApprovalFormCalculationField(
      id: 'cost',
      label: '成本',
      type: 'amount',
      calculation: ApprovalFormCalculation(
        expression: 'amount * exchangeRate / memberCount',
        scale: 4,
        roundingMode: 'floor',
      ),
    ),
  ];

  test('evaluates chained backend calculations in dependency order', () {
    final result = evaluateApprovalFormCalculations(
      fields: fields,
      sourceValues: const {
        'original': '1000',
        'ratio': '0.8',
        'exchangeRate': '2',
        'memberCount': '4',
        'amount': 'must not trust submitted calculated values',
      },
    );

    expect(result.errors, isEmpty);
    expect(result.values['amount'], 400);
    expect(result.values['cost'], 200);
  });

  test('returns formula errors without retaining stale calculated values', () {
    final result = evaluateApprovalFormCalculations(
      fields: fields,
      sourceValues: const {
        'original': 1000,
        'ratio': 0.8,
        'exchangeRate': 0,
        'memberCount': 4,
        'amount': 1,
        'cost': 1,
      },
    );

    expect(result.values.containsKey('amount'), isFalse);
    expect(result.values.containsKey('cost'), isFalse);
    expect(result.errors['amount'], '不能除以零');
  });

  test('detects circular backend field references', () {
    const circular = [
      ApprovalFormCalculationField(
        id: 'first',
        label: '字段一',
        type: 'number',
        calculation: ApprovalFormCalculation(
          expression: 'second + 1',
          scale: 0,
          roundingMode: 'half_up',
        ),
      ),
      ApprovalFormCalculationField(
        id: 'second',
        label: '字段二',
        type: 'number',
        calculation: ApprovalFormCalculation(
          expression: 'first + 1',
          scale: 0,
          roundingMode: 'half_up',
        ),
      ),
    ];
    final result = evaluateApprovalFormCalculations(
      fields: circular,
      sourceValues: const {},
    );

    expect(result.errors['first'], '计算字段存在循环引用');
    expect(result.errors['second'], '计算字段存在循环引用');
  });
}

ApprovalFormCalculationResult _calculate(
  String expression, {
  int scale = 2,
  String mode = 'half_up',
  String? input,
}) => evaluateApprovalFormCalculations(
  fields: [
    const ApprovalFormCalculationField(
      id: 'input',
      label: '原始费用',
      type: 'number',
    ),
    ApprovalFormCalculationField(
      id: 'answer',
      label: '计算结果',
      type: 'number',
      calculation: ApprovalFormCalculation(
        expression: expression,
        scale: scale,
        roundingMode: mode,
      ),
    ),
  ],
  sourceValues: {'input': input, 'answer': 'stale'},
);
