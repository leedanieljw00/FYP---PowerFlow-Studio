import 'complex.dart';

/// Pivots smaller than `tolerance × max|a_ij|` are treated as zero.
const double _relativePivotTolerance = 1e-13;

/// Thrown when a linear system cannot be solved because the matrix is
/// singular (or numerically indistinguishable from singular).
class SingularMatrixException implements Exception {
  const SingularMatrixException([this.message = 'Matrix is singular.']);

  final String message;

  @override
  String toString() => 'SingularMatrixException: $message';
}

/// Largest absolute value in [values] (0 for an empty list, NaN propagates).
double maxAbsOf(Iterable<double> values) {
  var m = 0.0;
  for (final v in values) {
    if (v.isNaN) return double.nan;
    final a = v.abs();
    if (a > m) m = a;
  }
  return m;
}

// ---------------------------------------------------------------------------
// Real matrix
// ---------------------------------------------------------------------------

/// A dense, mutable, row-major matrix of doubles.
class RealMatrix {
  /// Creates a `rows × cols` zero matrix.
  RealMatrix(this.rows, this.cols)
      : assert(rows >= 0 && cols >= 0),
        _data = List.generate(
          rows,
          (_) => List<double>.filled(cols, 0.0),
          growable: false,
        );

  /// `n × n` identity matrix.
  factory RealMatrix.identity(int n) {
    final m = RealMatrix(n, n);
    for (var i = 0; i < n; i++) {
      m._data[i][i] = 1.0;
    }
    return m;
  }

  /// Builds a matrix from a list of equally sized rows (deep-copied).
  factory RealMatrix.fromRows(List<List<double>> values) {
    final r = values.length;
    final c = r == 0 ? 0 : values.first.length;
    final m = RealMatrix(r, c);
    for (var i = 0; i < r; i++) {
      if (values[i].length != c) {
        throw ArgumentError(
          'All rows must have the same length '
          '(row $i has ${values[i].length}, expected $c).',
        );
      }
      for (var j = 0; j < c; j++) {
        m._data[i][j] = values[i][j];
      }
    }
    return m;
  }

  final int rows;
  final int cols;
  final List<List<double>> _data;

  bool get isSquare => rows == cols;

  double get(int i, int j) => _data[i][j];

  void set(int i, int j, double value) => _data[i][j] = value;

  /// Mutable access to row [i].
  List<double> operator [](int i) => _data[i];

  /// Read-only copy of row [i].
  List<double> row(int i) => List.unmodifiable(_data[i]);

  /// Copy of column [j].
  List<double> column(int j) => [for (var i = 0; i < rows; i++) _data[i][j]];

  /// Largest absolute entry.
  double get maxAbs => maxAbsOf(_data.expand((r) => r));

  RealMatrix copy() {
    final m = RealMatrix(rows, cols);
    for (var i = 0; i < rows; i++) {
      for (var j = 0; j < cols; j++) {
        m._data[i][j] = _data[i][j];
      }
    }
    return m;
  }

  RealMatrix transpose() {
    final m = RealMatrix(cols, rows);
    for (var i = 0; i < rows; i++) {
      for (var j = 0; j < cols; j++) {
        m._data[j][i] = _data[i][j];
      }
    }
    return m;
  }

  RealMatrix operator +(RealMatrix other) {
    _requireSameShape(other);
    final m = RealMatrix(rows, cols);
    for (var i = 0; i < rows; i++) {
      for (var j = 0; j < cols; j++) {
        m._data[i][j] = _data[i][j] + other._data[i][j];
      }
    }
    return m;
  }

  RealMatrix operator -(RealMatrix other) {
    _requireSameShape(other);
    final m = RealMatrix(rows, cols);
    for (var i = 0; i < rows; i++) {
      for (var j = 0; j < cols; j++) {
        m._data[i][j] = _data[i][j] - other._data[i][j];
      }
    }
    return m;
  }

  RealMatrix operator *(RealMatrix other) {
    if (cols != other.rows) {
      throw ArgumentError(
        'Dimension mismatch: ($rows×$cols) · (${other.rows}×${other.cols}).',
      );
    }
    final m = RealMatrix(rows, other.cols);
    for (var i = 0; i < rows; i++) {
      for (var k = 0; k < cols; k++) {
        final a = _data[i][k];
        if (a == 0) continue;
        for (var j = 0; j < other.cols; j++) {
          m._data[i][j] += a * other._data[k][j];
        }
      }
    }
    return m;
  }

  RealMatrix scaled(double k) {
    final m = RealMatrix(rows, cols);
    for (var i = 0; i < rows; i++) {
      for (var j = 0; j < cols; j++) {
        m._data[i][j] = _data[i][j] * k;
      }
    }
    return m;
  }

  List<double> multiplyVector(List<double> v) {
    if (v.length != cols) {
      throw ArgumentError('Vector length ${v.length} ≠ column count $cols.');
    }
    return [
      for (var i = 0; i < rows; i++)
        () {
          var s = 0.0;
          for (var j = 0; j < cols; j++) {
            s += _data[i][j] * v[j];
          }
          return s;
        }(),
    ];
  }

  /// Extracts rows `[rowStart, rowEnd)` and columns `[colStart, colEnd)`.
  RealMatrix subMatrix(int rowStart, int rowEnd, int colStart, int colEnd) {
    if (rowStart < 0 ||
        rowEnd > rows ||
        colStart < 0 ||
        colEnd > cols ||
        rowStart > rowEnd ||
        colStart > colEnd) {
      throw RangeError('Invalid sub-matrix range.');
    }
    final m = RealMatrix(rowEnd - rowStart, colEnd - colStart);
    for (var i = rowStart; i < rowEnd; i++) {
      for (var j = colStart; j < colEnd; j++) {
        m._data[i - rowStart][j - colStart] = _data[i][j];
      }
    }
    return m;
  }

  /// Solves `A·x = b` using Gaussian elimination with partial pivoting.
  ///
  /// Throws [SingularMatrixException] if a (numerically) zero pivot occurs.
  List<double> solve(List<double> b) {
    _requireSquare('solve');
    if (b.length != rows) {
      throw ArgumentError('RHS length ${b.length} ≠ matrix size $rows.');
    }
    final n = rows;
    final a = [for (final r in _data) List<double>.of(r)];
    final x = List<double>.of(b);
    final tol = _pivotTolerance();

    for (var k = 0; k < n; k++) {
      var p = k;
      var best = a[k][k].abs();
      for (var i = k + 1; i < n; i++) {
        final v = a[i][k].abs();
        if (v > best) {
          best = v;
          p = i;
        }
      }
      if (!(best > tol)) {
        throw SingularMatrixException(
          'Zero pivot in column ${k + 1}; matrix is singular.',
        );
      }
      if (p != k) {
        final tr = a[k];
        a[k] = a[p];
        a[p] = tr;
        final tb = x[k];
        x[k] = x[p];
        x[p] = tb;
      }
      for (var i = k + 1; i < n; i++) {
        final f = a[i][k] / a[k][k];
        if (f == 0) continue;
        for (var j = k; j < n; j++) {
          a[i][j] -= f * a[k][j];
        }
        x[i] -= f * x[k];
      }
    }

    final result = List<double>.filled(n, 0.0);
    for (var i = n - 1; i >= 0; i--) {
      var s = x[i];
      for (var j = i + 1; j < n; j++) {
        s -= a[i][j] * result[j];
      }
      result[i] = s / a[i][i];
    }
    return result;
  }

  /// Matrix inverse by Gauss–Jordan elimination with partial pivoting.
  RealMatrix inverse() {
    _requireSquare('inverse');
    final n = rows;
    final a = [for (final r in _data) List<double>.of(r)];
    final inv = [
      for (var i = 0; i < n; i++)
        [for (var j = 0; j < n; j++) i == j ? 1.0 : 0.0],
    ];
    final tol = _pivotTolerance();

    for (var k = 0; k < n; k++) {
      var p = k;
      var best = a[k][k].abs();
      for (var i = k + 1; i < n; i++) {
        final v = a[i][k].abs();
        if (v > best) {
          best = v;
          p = i;
        }
      }
      if (!(best > tol)) {
        throw SingularMatrixException(
          'Zero pivot in column ${k + 1}; matrix is singular.',
        );
      }
      if (p != k) {
        final t1 = a[k];
        a[k] = a[p];
        a[p] = t1;
        final t2 = inv[k];
        inv[k] = inv[p];
        inv[p] = t2;
      }
      final pivot = a[k][k];
      for (var j = 0; j < n; j++) {
        a[k][j] /= pivot;
        inv[k][j] /= pivot;
      }
      for (var i = 0; i < n; i++) {
        if (i == k) continue;
        final f = a[i][k];
        if (f == 0) continue;
        for (var j = 0; j < n; j++) {
          a[i][j] -= f * a[k][j];
          inv[i][j] -= f * inv[k][j];
        }
      }
    }
    return RealMatrix.fromRows(inv);
  }

  /// Determinant via LU elimination (0 for singular matrices).
  double determinant() {
    _requireSquare('determinant');
    final n = rows;
    final a = [for (final r in _data) List<double>.of(r)];
    var det = 1.0;
    for (var k = 0; k < n; k++) {
      var p = k;
      var best = a[k][k].abs();
      for (var i = k + 1; i < n; i++) {
        final v = a[i][k].abs();
        if (v > best) {
          best = v;
          p = i;
        }
      }
      if (best == 0) return 0.0;
      if (p != k) {
        final t = a[k];
        a[k] = a[p];
        a[p] = t;
        det = -det;
      }
      det *= a[k][k];
      for (var i = k + 1; i < n; i++) {
        final f = a[i][k] / a[k][k];
        for (var j = k; j < n; j++) {
          a[i][j] -= f * a[k][j];
        }
      }
    }
    return det;
  }

  bool approxEquals(RealMatrix other, [double tolerance = 1e-9]) {
    if (rows != other.rows || cols != other.cols) return false;
    for (var i = 0; i < rows; i++) {
      for (var j = 0; j < cols; j++) {
        if ((_data[i][j] - other._data[i][j]).abs() > tolerance) return false;
      }
    }
    return true;
  }

  /// Deep copy as nested lists.
  List<List<double>> toList() => [for (final r in _data) List<double>.of(r)];

  double _pivotTolerance() {
    final scale = maxAbs;
    return _relativePivotTolerance * (scale == 0 || scale.isNaN ? 1.0 : scale);
  }

  void _requireSquare(String op) {
    if (!isSquare) {
      throw ArgumentError('$op requires a square matrix (got $rows×$cols).');
    }
  }

  void _requireSameShape(RealMatrix other) {
    if (rows != other.rows || cols != other.cols) {
      throw ArgumentError(
        'Shape mismatch: ($rows×$cols) vs (${other.rows}×${other.cols}).',
      );
    }
  }

  @override
  String toString() =>
      'RealMatrix($rows×$cols)\n${_data.map((r) => r.map((v) => v.toStringAsFixed(4)).join('\t')).join('\n')}';
}

// ---------------------------------------------------------------------------
// Complex matrix
// ---------------------------------------------------------------------------

/// A dense, mutable, row-major matrix of [Complex] values.
class ComplexMatrix {
  /// Creates a `rows × cols` zero matrix.
  ComplexMatrix(this.rows, this.cols)
      : assert(rows >= 0 && cols >= 0),
        _data = List.generate(
          rows,
          (_) => List<Complex>.filled(cols, Complex.zero),
          growable: false,
        );

  /// `n × n` identity matrix.
  factory ComplexMatrix.identity(int n) {
    final m = ComplexMatrix(n, n);
    for (var i = 0; i < n; i++) {
      m._data[i][i] = Complex.one;
    }
    return m;
  }

  /// Builds a matrix from equally sized rows (copied).
  factory ComplexMatrix.fromRows(List<List<Complex>> values) {
    final r = values.length;
    final c = r == 0 ? 0 : values.first.length;
    final m = ComplexMatrix(r, c);
    for (var i = 0; i < r; i++) {
      if (values[i].length != c) {
        throw ArgumentError('All rows must have the same length.');
      }
      for (var j = 0; j < c; j++) {
        m._data[i][j] = values[i][j];
      }
    }
    return m;
  }

  final int rows;
  final int cols;
  final List<List<Complex>> _data;

  bool get isSquare => rows == cols;

  Complex get(int i, int j) => _data[i][j];

  void set(int i, int j, Complex value) => _data[i][j] = value;

  /// `A[i][j] += value`.
  void addTo(int i, int j, Complex value) => _data[i][j] = _data[i][j] + value;

  /// Mutable access to row [i].
  List<Complex> operator [](int i) => _data[i];

  ComplexMatrix copy() => ComplexMatrix.fromRows(_data);

  ComplexMatrix transpose() {
    final m = ComplexMatrix(cols, rows);
    for (var i = 0; i < rows; i++) {
      for (var j = 0; j < cols; j++) {
        m._data[j][i] = _data[i][j];
      }
    }
    return m;
  }

  /// Real parts (e.g. conductance matrix G of Y = G + jB).
  RealMatrix realPart() {
    final m = RealMatrix(rows, cols);
    for (var i = 0; i < rows; i++) {
      for (var j = 0; j < cols; j++) {
        m[i][j] = _data[i][j].re;
      }
    }
    return m;
  }

  /// Imaginary parts (e.g. susceptance matrix B of Y = G + jB).
  RealMatrix imagPart() {
    final m = RealMatrix(rows, cols);
    for (var i = 0; i < rows; i++) {
      for (var j = 0; j < cols; j++) {
        m[i][j] = _data[i][j].im;
      }
    }
    return m;
  }

  List<Complex> multiplyVector(List<Complex> v) {
    if (v.length != cols) {
      throw ArgumentError('Vector length ${v.length} ≠ column count $cols.');
    }
    final out = List<Complex>.filled(rows, Complex.zero);
    for (var i = 0; i < rows; i++) {
      var s = Complex.zero;
      for (var j = 0; j < cols; j++) {
        s = s + _data[i][j] * v[j];
      }
      out[i] = s;
    }
    return out;
  }

  ComplexMatrix operator *(ComplexMatrix other) {
    if (cols != other.rows) {
      throw ArgumentError('Dimension mismatch in complex matrix product.');
    }
    final m = ComplexMatrix(rows, other.cols);
    for (var i = 0; i < rows; i++) {
      for (var j = 0; j < other.cols; j++) {
        var s = Complex.zero;
        for (var k = 0; k < cols; k++) {
          s = s + _data[i][k] * other._data[k][j];
        }
        m._data[i][j] = s;
      }
    }
    return m;
  }

  /// Inverse by complex Gauss–Jordan elimination with partial pivoting.
  /// Useful e.g. for obtaining `Z_bus = Y_bus⁻¹`.
  ComplexMatrix inverse() {
    if (!isSquare) {
      throw ArgumentError('inverse requires a square matrix.');
    }
    final n = rows;
    final a = [for (final r in _data) List<Complex>.of(r)];
    final inv = [
      for (var i = 0; i < n; i++)
        [for (var j = 0; j < n; j++) i == j ? Complex.one : Complex.zero],
    ];
    var scale = 0.0;
    for (final r in _data) {
      for (final z in r) {
        if (z.abs > scale) scale = z.abs;
      }
    }
    final tol = _relativePivotTolerance * (scale == 0 ? 1.0 : scale);

    for (var k = 0; k < n; k++) {
      var p = k;
      var best = a[k][k].abs;
      for (var i = k + 1; i < n; i++) {
        final v = a[i][k].abs;
        if (v > best) {
          best = v;
          p = i;
        }
      }
      if (!(best > tol)) {
        throw SingularMatrixException(
          'Zero pivot in column ${k + 1}; matrix is singular.',
        );
      }
      if (p != k) {
        final t1 = a[k];
        a[k] = a[p];
        a[p] = t1;
        final t2 = inv[k];
        inv[k] = inv[p];
        inv[p] = t2;
      }
      final pivot = a[k][k];
      for (var j = 0; j < n; j++) {
        a[k][j] = a[k][j] / pivot;
        inv[k][j] = inv[k][j] / pivot;
      }
      for (var i = 0; i < n; i++) {
        if (i == k) continue;
        final f = a[i][k];
        if (f.isZero) continue;
        for (var j = 0; j < n; j++) {
          a[i][j] = a[i][j] - f * a[k][j];
          inv[i][j] = inv[i][j] - f * inv[k][j];
        }
      }
    }
    return ComplexMatrix.fromRows(inv);
  }

  bool isSymmetric([double tolerance = 1e-12]) {
    if (!isSquare) return false;
    for (var i = 0; i < rows; i++) {
      for (var j = i + 1; j < cols; j++) {
        if (!_data[i][j].approxEquals(_data[j][i], tolerance)) return false;
      }
    }
    return true;
  }

  bool approxEquals(ComplexMatrix other, [double tolerance = 1e-9]) {
    if (rows != other.rows || cols != other.cols) return false;
    for (var i = 0; i < rows; i++) {
      for (var j = 0; j < cols; j++) {
        if (!_data[i][j].approxEquals(other._data[i][j], tolerance)) {
          return false;
        }
      }
    }
    return true;
  }

  List<List<Complex>> toList() => [for (final r in _data) List<Complex>.of(r)];

  @override
  String toString() =>
      'ComplexMatrix($rows×$cols)\n${_data.map((r) => r.join('\t')).join('\n')}';
}
