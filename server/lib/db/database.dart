// Postgres connection pool + Row helper.
//
// The `postgres` Dart package (3.x) doesn't ship a built-in connection
// pool, so we implement a tiny one here. For higher scale, swap to
// `pg_pool` or run pgbouncer in front.

import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import '../config.dart';

class _Conn {
  final Connection conn;
  bool inUse = false;
  _Conn(this.conn);
}

/// A single row from a query, exposed as `columnName -> value`.
class Row {
  final Map<String, dynamic> _data;
  Row(this._data);

  T col<T>(String name) {
    final v = _data[name];
    if (v == null) {
      throw StateError(
          'Column "$name" not present in row (have: ${_data.keys})');
    }
    return v as T;
  }

  T? nullable<T>(String name) {
    return _data[name] as T?;
  }

  bool has(String name) {
    return _data.containsKey(name) && _data[name] != null;
  }

  /// Read a non-null timestamp column. Handles both DateTime (returned by
  /// the postgres package for TIMESTAMPTZ) and String (in case a future
  /// query uses to_char or similar).
  DateTime dateTime(String name) {
    final v = _data[name];
    if (v == null) {
      throw StateError('Column "$name" not present in row');
    }
    if (v is DateTime) return v;
    if (v is String) return DateTime.parse(v);
    throw StateError(
        'Column "$name" is not a DateTime: ${v.runtimeType}');
  }

  /// Read a nullable timestamp column.
  DateTime? dateTimeOpt(String name) {
    final v = _data[name];
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.parse(v);
    throw StateError(
        'Column "$name" is not a DateTime: ${v.runtimeType}');
  }
}

class Database {
  final List<_Conn> _pool;
  final int _max;
  final Endpoint _endpoint;
  final ConnectionSettings _settings;
  final AppConfig _cfg;
  final Logger _log = Logger('Database');

  Database._(this._pool, this._max, this._endpoint, this._settings, this._cfg);

  static Future<Database> connect(AppConfig cfg) async {
    final log = Logger('Database');
    log.info('Connecting to Postgres...');

    final endpoint = Endpoint(
      host: _extractHost(cfg.databaseUrl),
      port: _extractPort(cfg.databaseUrl),
      database: _extractDb(cfg.databaseUrl),
      username: _extractUser(cfg.databaseUrl),
      password: _extractPassword(cfg.databaseUrl),
    );
    final settings = ConnectionSettings(
        sslMode: _parseSslMode(cfg.databaseSslMode));

    final max = cfg.databaseMaxConnections.clamp(1, 50);
    final pool = <_Conn>[];

    final first = await Connection.open(endpoint, settings: settings);
    pool.add(_Conn(first));
    log.info('Postgres connection OK (max=$max, ssl=${cfg.databaseSslMode})');

    final db = Database._(pool, max, endpoint, settings, cfg);
    if (cfg.runMigrations) {
      await db.migrate();
    }
    return db;
  }

  /// Apply the SQL schema if the database is empty.
  ///
  /// Idempotent: only runs when the `users` table is missing.
  /// Disable with RUN_MIGRATIONS=false if you manage migrations externally.
  Future<void> migrate() async {
    final result = await query(
      "SELECT EXISTS ("
      "  SELECT 1 FROM information_schema.tables "
      "  WHERE table_schema = 'public' AND table_name = 'users'"
      ")",
    );
    final usersExists = result.isNotEmpty && result.first._data.values.first == true;
    if (usersExists) {
      _log.info('Schema already applied, skipping migrations');
      return;
    }

    final sql = await _loadSchemaSql();
    if (sql == null) {
      _log.warning(
        'Schema file not found. Set SCHEMA_PATH or place schema.sql in the working dir. '
        'Database will be empty — apply schema manually.');
      return;
    }

    _log.info('Applying schema (first run)...');
    final statements = _splitStatements(sql);
    for (var i = 0; i < statements.length; i++) {
      final stmt = statements[i];
      try {
        await execute(stmt);
      } catch (e) {
        _log.severe('Migration failed at statement ${i + 1}: $e');
        _log.severe('Statement was:\n$stmt');
        rethrow;
      }
    }
    _log.info('Schema applied: ${statements.length} statements');
  }

  Future<String?> _loadSchemaSql() async {
    final candidates = <String>[
      if (_cfg.schemaPath.isNotEmpty) _cfg.schemaPath,
      './lib/db/schema.sql',
      'lib/db/schema.sql',
      './schema.sql',
      'schema.sql',
      '/app/schema.sql',
      '${Directory.current.path}/lib/db/schema.sql',
      '${Directory.current.path}/schema.sql',
    ];
    for (final path in candidates) {
      final f = File(path);
      if (await f.exists()) {
        _log.info('Loading schema from $path');
        return f.readAsString();
      }
    }
    return null;
  }

  /// Split a SQL script into individual statements.
  ///
  /// Handles:
  ///   - line comments (`-- foo`)
  ///   - statements ending in `;`
  ///   - blank lines
  /// Does NOT handle:
  ///   - `;` inside string literals (none in our schema)
  ///   - dollar-quoted blocks (e.g. `$$ ... $$`)
  static List<String> _splitStatements(String sql) {
    final result = <String>[];
    final buffer = StringBuffer();
    for (final line in sql.split('\n')) {
      final stripped = line.replaceFirst(RegExp(r'--.*$'), '').trim();
      if (stripped.isEmpty && buffer.isEmpty) continue;
      buffer.writeln(line);
      if (stripped.endsWith(';')) {
        final s = buffer.toString().trim();
        if (s.isNotEmpty) result.add(s);
        buffer.clear();
      }
    }
    final rest = buffer.toString().trim();
    if (rest.isNotEmpty) result.add(rest);
    return result;
  }

  Future<List<Row>> query(
    String sql, [
    Map<String, dynamic>? params,
  ]) async {
    final conn = await _acquire();
    try {
      final result = await _execute(conn, sql, params);
      return _rowsFromResult(result);
    } finally {
      _release(conn);
    }
  }

  Future<dynamic> queryValue(String sql, [Map<String, dynamic>? params]) async {
    final rows = await query(sql, params);
    if (rows.isEmpty) return null;
    return rows.first._data.values.first;
  }

  Future<int> execute(String sql, [Map<String, dynamic>? params]) async {
    final conn = await _acquire();
    try {
      final result = await _execute(conn, sql, params);
      return result.affectedRows;
    } finally {
      _release(conn);
    }
  }

  /// Execute a SQL string with optional named parameters.
  ///
  /// The postgres 3.x package has a quirk: passing an empty `{}` as
  /// `parameters` to a String query throws "Maps are only supported
  /// by Sql.named". We avoid that by:
  ///   - passing `null` when there are no parameters, or
  ///   - wrapping the SQL in `Sql.named(...)` when there are some.
  static Future<Result> _execute(
    Connection conn,
    String sql,
    Map<String, dynamic>? params,
  ) {
    if (params == null) {
      return conn.execute(sql);
    }
    return conn.execute(Sql.named(sql), parameters: params);
  }

  Future<Connection> _acquire() async {
    for (final c in _pool) {
      if (!c.inUse) {
        c.inUse = true;
        return c.conn;
      }
    }
    if (_pool.length < _max) {
      try {
        final c = await Connection.open(_endpoint, settings: _settings);
        final wrapper = _Conn(c);
        wrapper.inUse = true;
        _pool.add(wrapper);
        _log.info('Pool grew to ${_pool.length}');
        return c;
      } catch (e) {
        _log.warning('Failed to grow pool: $e');
      }
    }
    while (true) {
      await Future.delayed(const Duration(milliseconds: 5));
      for (final c in _pool) {
        if (!c.inUse) {
          c.inUse = true;
          return c.conn;
        }
      }
    }
  }

  void _release(Connection conn) {
    for (final c in _pool) {
      if (identical(c.conn, conn)) {
        c.inUse = false;
        return;
      }
    }
  }

  Future<void> close() async {
    for (final c in _pool) {
      try {
        await c.conn.close();
      } catch (_) {}
    }
    _pool.clear();
    _log.info('Postgres pool closed');
  }

  static List<Row> _rowsFromResult(Result result) {
    if (result.isEmpty) return [];
    final columns = result.schema.columns;
    return result.map((row) {
      final data = <String, dynamic>{};
      for (var i = 0; i < columns.length; i++) {
        data[columns[i].columnName ?? 'col$i'] = row[i];
      }
      return Row(data);
    }).toList();
  }

  static SslMode _parseSslMode(String s) {
    switch (s.toLowerCase()) {
      case 'disable':
      case 'disabled':
        return SslMode.disable;
      case 'require':
      case 'prefer':
        return SslMode.require;
      case 'verify-full':
      case 'verifyfull':
        return SslMode.verifyFull;
      default:
        return SslMode.disable;
    }
  }

  static String _extractHost(String url) => _parse(url, 'host', 'localhost');
  static int _extractPort(String url) =>
      int.parse(_parse(url, 'port', '5432'));
  static String _extractDb(String url) => _parse(url, 'database', 'patchfly');
  static String _extractUser(String url) => _parse(url, 'username', 'patchfly');
  static String _extractPassword(String url) =>
      _parse(url, 'password', '');

  static String _parse(String url, String key, String fallback) {
    try {
      final uri = Uri.parse(url);
      switch (key) {
        case 'host':
          return uri.host.isEmpty ? fallback : uri.host;
        case 'port':
          return uri.hasPort ? uri.port.toString() : fallback;
        case 'database':
          return uri.pathSegments.isEmpty
              ? fallback
              : uri.pathSegments.first;
        case 'username':
          return uri.userInfo.isEmpty
              ? fallback
              : uri.userInfo.split(':').first;
        case 'password':
          if (uri.userInfo.isEmpty) return fallback;
          final parts = uri.userInfo.split(':');
          return parts.length > 1 ? parts[1] : '';
      }
    } catch (_) {}
    return fallback;
  }
}
