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
        try {
          return _ExactNumber.parse(raw.toString());
        } on FormatException catch (error) {
          if (error.message == '数字格式不正确') {
            throw FormatException('“${referencedField.label}”必须是数字');
          }
          rethrow;
        }
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

Object _round(_ExactNumber value, int scale, String roundingMode) {
  if (scale < 0 || scale > 8) throw const FormatException('计算精度必须在 0 到 8 位之间');
  final factor = BigInt.from(10).pow(scale);
  final scaled = value.numerator.abs() * factor;
  var rounded = scaled ~/ value.denominator;
  final remainder = scaled.remainder(value.denominator);
  final increment = switch (roundingMode) {
    'floor' => value.numerator.isNegative && remainder != BigInt.zero,
    'ceiling' => !value.numerator.isNegative && remainder != BigInt.zero,
    'truncate' => false,
    _ => remainder * BigInt.two >= value.denominator,
  };
  if (increment) rounded += BigInt.one;
  if (value.numerator.isNegative) rounded = -rounded;
  var coefficient = rounded.abs();
  var coefficientScale = scale;
  final ten = BigInt.from(10);
  while (coefficientScale > 0 && coefficient.remainder(ten) == BigInt.zero) {
    coefficient ~/= ten;
    coefficientScale -= 1;
  }
  if (coefficient > _ExactNumber._maxDecimal) {
    throw const FormatException('结果超出 decimal 精度');
  }
  final result = _ExactNumber(rounded, factor);
  final digits = rounded.abs().toString().padLeft(scale + 1, '0');
  final magnitude = scale == 0
      ? digits
      : '${digits.substring(0, digits.length - scale)}.${digits.substring(digits.length - scale)}';
  final text = '${rounded.isNegative ? '-' : ''}$magnitude';

  // Keep ordinary numeric JSON values compatible. When converting to double would
  // alter the decimal digits, use the same decimal-text representation as user
  // entered amount fields. Never leak BigInt into JSON or round a large amount.
  // JSON consumers such as the desktop JavaScript UI use binary doubles, even
  // when native Dart could hold the value as an exact 64-bit integer.
  final number = double.tryParse(text);
  if (number != null && number.isFinite) {
    try {
      final serialized = _ExactNumber.parse(number.toString());
      if (serialized.numerator == result.numerator &&
          serialized.denominator == result.denominator) {
        return number;
      }
    } on FormatException catch (_) {
      // A rounded double may itself exceed the decimal bound.
    }
  }
  return text;
}

_ExactNumber _evaluateExpression(
  _ExpressionNode node,
  _ExactNumber Function(String fieldId) readReference,
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
      final result = switch (operation) {
        '+' => leftValue + rightValue,
        '-' => leftValue - rightValue,
        '*' => leftValue * rightValue,
        _ => leftValue / rightValue,
      };
      return result;
    }(),
  };
}

// Decimal input is parsed directly into a reduced fraction, without passing
// through binary floating point. Quantize only at each calculated field's
// configured scale, so dependent formulas consume the visible rounded result.
final class _ExactNumber {
  factory _ExactNumber(BigInt numerator, BigInt denominator) {
    if (denominator == BigInt.zero) throw const FormatException('不能除以零');
    if (numerator.bitLength > 8192 || denominator.bitLength > 8192) {
      throw const FormatException('公式数值过于复杂');
    }
    if (denominator.isNegative) {
      numerator = -numerator;
      denominator = -denominator;
    }
    if (numerator.abs() > _maxDecimal * denominator) {
      throw const FormatException('结果超出 decimal 精度');
    }
    final divisor = numerator.abs().gcd(denominator);
    return _ExactNumber._(numerator ~/ divisor, denominator ~/ divisor);
  }

  const _ExactNumber._(this.numerator, this.denominator);

  factory _ExactNumber.parse(String raw) {
    final text = raw.trim();
    if (text.length > 512) throw const FormatException('数字超出支持精度');
    final match = _decimalPattern.firstMatch(text);
    if (match == null) throw const FormatException('数字格式不正确');
    final whole = match.group(2) ?? '0';
    final fractional = match.group(3) ?? match.group(4) ?? '';
    final exponentText = match.group(5) ?? '0';
    final exponent = int.tryParse(exponentText);
    if (exponent == null || exponent.abs() > 512) {
      throw const FormatException('数字超出支持精度');
    }
    final scale = fractional.length - exponent;
    if (scale.abs() > 512) throw const FormatException('数字超出支持精度');
    var numerator = BigInt.parse('$whole$fractional');
    if (match.group(1) == '-') numerator = -numerator;
    final factor = BigInt.from(10).pow(scale.abs());
    return scale < 0
        ? _ExactNumber(numerator * factor, BigInt.one)
        : _ExactNumber(numerator, factor);
  }

  static final _maxDecimal = BigInt.parse('79228162514264337593543950335');
  static final _decimalPattern = RegExp(
    r'^([+-]?)(?:(\d+)(?:\.(\d*))?|\.(\d+))(?:[eE]([+-]?\d+))?$',
  );

  final BigInt numerator;
  final BigInt denominator;

  _ExactNumber operator -() => _ExactNumber(-numerator, denominator);
  _ExactNumber operator +(_ExactNumber other) => _ExactNumber(
    numerator * other.denominator + other.numerator * denominator,
    denominator * other.denominator,
  );
  _ExactNumber operator -(_ExactNumber other) => this + -other;
  _ExactNumber operator *(_ExactNumber other) => _ExactNumber(
    numerator * other.numerator,
    denominator * other.denominator,
  );
  _ExactNumber operator /(_ExactNumber other) => _ExactNumber(
    numerator * other.denominator,
    denominator * other.numerator,
  );
}

sealed class _ExpressionNode {
  const _ExpressionNode();
}

final class _ConstantNode extends _ExpressionNode {
  const _ConstantNode(this.value);
  final _ExactNumber value;
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
    final value = _ExactNumber.parse(source.substring(start, _index));
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
