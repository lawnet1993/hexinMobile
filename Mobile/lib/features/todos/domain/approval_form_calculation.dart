final class ApprovalFormCalculation {
  const ApprovalFormCalculation({
    required this.expression,
    required this.scale,
    required this.roundingMode,
  });

  factory ApprovalFormCalculation.fromJson(Map<String, Object?> json) {
    final parsedScale = int.tryParse(json['scale']?.toString() ?? '') ?? 0;
    return ApprovalFormCalculation(
      expression: json['expression']?.toString().trim() ?? '',
      scale: parsedScale.clamp(0, 8),
      roundingMode: json['roundingMode']?.toString().trim().isNotEmpty == true
          ? json['roundingMode'].toString()
          : 'half_up',
    );
  }

  final String expression;
  final int scale;
  final String roundingMode;
}

final class ApprovalFormCalculationField {
  const ApprovalFormCalculationField({
    required this.id,
    required this.label,
    required this.type,
    this.calculation,
  });

  final String id;
  final String label;
  final String type;
  final ApprovalFormCalculation? calculation;
}

final class ApprovalFormCalculationResult {
  const ApprovalFormCalculationResult({
    required this.values,
    required this.errors,
  });

  final Map<String, Object?> values;
  final Map<String, String> errors;
}

ApprovalFormCalculationResult evaluateApprovalFormCalculations({
  required List<ApprovalFormCalculationField> fields,
  required Map<String, Object?> sourceValues,
}) {
  final values = Map<String, Object?>.from(sourceValues);
  final errors = <String, String>{};
  final fieldsById = {for (final field in fields) field.id: field};
  final calculated = fields
      .where((field) => field.calculation != null)
      .toList(growable: false);
  final expressions = <String, _ParsedExpression>{};

  for (final field in calculated) {
    values.remove(field.id);
    if (field.type != 'number' && field.type != 'amount') {
      errors[field.id] = '只有数字和金额字段可以启用计算';
      continue;
    }
    try {
      final parsed = _ExpressionParser(field.calculation!.expression).parse();
      expressions[field.id] = parsed;
      final missingReference = parsed.references
          .where((reference) => !fieldsById.containsKey(reference))
          .firstOrNull;
      if (missingReference != null) {
        errors[field.id] = '引用字段不存在：$missingReference';
        continue;
      }
      final invalidReference = parsed.references.where((reference) {
        final type = fieldsById[reference]!.type;
        return type != 'number' && type != 'amount';
      }).firstOrNull;
      if (invalidReference != null) {
        errors[field.id] = '引用字段必须是数字或金额：$invalidReference';
      }
    } on FormatException catch (error) {
      errors[field.id] = error.message;
    }
  }

  final visiting = <String>{};
  final visited = <String>{};
  final stack = <String>[];
  void validateCycles(String fieldId) {
    if (visited.contains(fieldId)) return;
    if (visiting.contains(fieldId)) {
      final cycleStart = stack.indexOf(fieldId);
      for (final item in stack.skip(cycleStart < 0 ? 0 : cycleStart)) {
        errors[item] = '计算字段存在循环引用';
      }
      return;
    }
    visiting.add(fieldId);
    stack.add(fieldId);
    for (final reference in expressions[fieldId]?.references ?? const []) {
      if (expressions.containsKey(reference)) validateCycles(reference);
    }
    stack.removeLast();
    visiting.remove(fieldId);
    visited.add(fieldId);
  }

  for (final field in calculated) {
    validateCycles(field.id);
  }
  if (errors.isNotEmpty) {
    return ApprovalFormCalculationResult(values: values, errors: errors);
  }

  final ordered = <ApprovalFormCalculationField>[];
  final orderedIds = <String>{};
  void order(ApprovalFormCalculationField field) {
    if (!orderedIds.add(field.id)) return;
    for (final reference in expressions[field.id]!.references) {
      final dependency = fieldsById[reference];
      if (dependency?.calculation != null) order(dependency!);
    }
    ordered.add(field);
  }

  for (final field in calculated) {
    order(field);
  }
  for (final field in ordered) {
    try {
      final value = _evaluateExpression(expressions[field.id]!.root, (
        reference,
      ) {
        final raw = values[reference];
        final referencedField = fieldsById[reference]!;
        if (raw == null || raw.toString().trim().isEmpty) {
          throw FormatException('请填写“${referencedField.label}”');
        }
        final number = num.tryParse(raw.toString());
        if (number == null || !number.isFinite) {
          throw FormatException('“${referencedField.label}”必须是数字');
        }
        return number.toDouble();
      });
      values[field.id] = _round(
        value,
        field.calculation!.scale,
        field.calculation!.roundingMode,
      );
    } on FormatException catch (error) {
      errors[field.id] = error.message;
    }
  }
  return ApprovalFormCalculationResult(values: values, errors: errors);
}

double _round(double value, int scale, String roundingMode) {
  const numberEpsilon = 2.220446049250313e-16;
  var factor = 1.0;
  for (var index = 0; index < scale; index += 1) {
    factor *= 10;
  }
  final scaled = value * factor;
  if (!scaled.isFinite) throw const FormatException('结果超出 decimal 精度');
  final rounded = switch (roundingMode) {
    'floor' => scaled.floorToDouble(),
    'ceiling' => scaled.ceilToDouble(),
    'truncate' => scaled.truncateToDouble(),
    _ =>
      scaled.isNegative
          ? -((-scaled + numberEpsilon).roundToDouble())
          : (scaled + numberEpsilon).roundToDouble(),
  };
  return rounded / factor;
}

double _evaluateExpression(
  _ExpressionNode node,
  double Function(String fieldId) readReference,
) {
  return switch (node) {
    _ConstantNode(:final value) => value,
    _ReferenceNode(:final fieldId) => readReference(fieldId),
    _UnaryNode(:final operation, :final operand) =>
      operation == '-'
          ? -_evaluateExpression(operand, readReference)
          : _evaluateExpression(operand, readReference),
    _BinaryNode(:final operation, :final left, :final right) => () {
      final leftValue = _evaluateExpression(left, readReference);
      final rightValue = _evaluateExpression(right, readReference);
      if (operation == '/' && rightValue == 0) {
        throw const FormatException('不能除以零');
      }
      final result = switch (operation) {
        '+' => leftValue + rightValue,
        '-' => leftValue - rightValue,
        '*' => leftValue * rightValue,
        _ => leftValue / rightValue,
      };
      if (!result.isFinite || result.abs() > 7.922816251426433e28) {
        throw const FormatException('结果超出 decimal 精度');
      }
      return result;
    }(),
  };
}

sealed class _ExpressionNode {
  const _ExpressionNode();
}

final class _ConstantNode extends _ExpressionNode {
  const _ConstantNode(this.value);
  final double value;
}

final class _ReferenceNode extends _ExpressionNode {
  const _ReferenceNode(this.fieldId);
  final String fieldId;
}

final class _UnaryNode extends _ExpressionNode {
  const _UnaryNode(this.operation, this.operand);
  final String operation;
  final _ExpressionNode operand;
}

final class _BinaryNode extends _ExpressionNode {
  const _BinaryNode(this.operation, this.left, this.right);
  final String operation;
  final _ExpressionNode left;
  final _ExpressionNode right;
}

final class _ParsedExpression {
  const _ParsedExpression(this.root, this.references);
  final _ExpressionNode root;
  final List<String> references;
}

final class _ExpressionParser {
  _ExpressionParser(this.source);

  final String source;
  int _index = 0;
  int _nodeCount = 0;
  final Set<String> _references = {};

  _ParsedExpression parse() {
    final expression = _parseExpression(0);
    _skipWhitespace();
    if (_index != source.length) _syntax('存在无法识别的字符');
    return _ParsedExpression(expression, _references.toList(growable: false));
  }

  _ExpressionNode _parseExpression(int depth) {
    var expression = _parseTerm(depth + 1);
    while (true) {
      _skipWhitespace();
      final operation = _readOperator(const ['+', '-']);
      if (operation == null) return expression;
      expression = _count(
        _BinaryNode(operation, expression, _parseTerm(depth + 1)),
      );
    }
  }

  _ExpressionNode _parseTerm(int depth) {
    var expression = _parseFactor(depth + 1);
    while (true) {
      _skipWhitespace();
      final operation = _readOperator(const ['*', '/']);
      if (operation == null) return expression;
      expression = _count(
        _BinaryNode(operation, expression, _parseFactor(depth + 1)),
      );
    }
  }

  _ExpressionNode _parseFactor(int depth) {
    if (depth > 32) _syntax('括号层级过深');
    _skipWhitespace();
    final operation = _readOperator(const ['+', '-']);
    if (operation != null) {
      return _count(_UnaryNode(operation, _parseFactor(depth + 1)));
    }
    if (_tryRead('(')) {
      final expression = _parseExpression(depth + 1);
      _skipWhitespace();
      if (!_tryRead(')')) _syntax('缺少右括号');
      return expression;
    }
    if (_index >= source.length) _syntax('缺少数字或字段');
    final character = source[_index];
    if (_isDigit(character) || character == '.') return _parseNumber();
    if (_isIdentifierStart(character)) return _parseReference();
    _syntax('仅支持字段、数字、括号及 + - * /');
  }

  _ExpressionNode _parseNumber() {
    final start = _index;
    var hasDecimalPoint = false;
    while (_index < source.length) {
      final character = source[_index];
      if (character == '.' && !hasDecimalPoint) {
        hasDecimalPoint = true;
        _index += 1;
        continue;
      }
      if (!_isDigit(character)) break;
      _index += 1;
    }
    final value = double.tryParse(source.substring(start, _index));
    if (value == null || !value.isFinite) _syntax('数字格式不正确');
    return _count(_ConstantNode(value));
  }

  _ExpressionNode _parseReference() {
    final start = _index;
    _index += 1;
    while (_index < source.length && _isIdentifierPart(source[_index])) {
      _index += 1;
    }
    final fieldId = source.substring(start, _index);
    _references.add(fieldId);
    return _count(_ReferenceNode(fieldId));
  }

  T _count<T extends _ExpressionNode>(T node) {
    _nodeCount += 1;
    if (_nodeCount > 128) _syntax('公式过于复杂');
    return node;
  }

  String? _readOperator(List<String> operators) {
    if (_index >= source.length) return null;
    final character = source[_index];
    if (!operators.contains(character)) return null;
    _index += 1;
    return character;
  }

  bool _tryRead(String value) {
    if (_index >= source.length || source[_index] != value) return false;
    _index += 1;
    return true;
  }

  void _skipWhitespace() {
    while (_index < source.length && source[_index].trim().isEmpty) {
      _index += 1;
    }
  }

  Never _syntax(String message) {
    throw FormatException('$message（位置 ${_index + 1}）');
  }
}

bool _isDigit(String value) =>
    value.codeUnitAt(0) >= 48 && value.codeUnitAt(0) <= 57;

bool _isIdentifierStart(String value) {
  final code = value.codeUnitAt(0);
  return code == 95 ||
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122);
}

bool _isIdentifierPart(String value) =>
    _isIdentifierStart(value) || _isDigit(value);
