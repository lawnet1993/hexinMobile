import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/todos/domain/approval_form_calculation.dart';

void main() {
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
