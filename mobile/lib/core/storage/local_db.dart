import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQLite cache + durable outbox for the offline-first sync engine.
///
/// Outbox rows survive app kills; every mutation made while offline is queued
/// here and drained by [SyncEngine] when connectivity returns.
class LocalDb {
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'ijwi_ryajye.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE outbox (
            client_op_id TEXT PRIMARY KEY,
            op_type TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE cache (
            collection TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            body TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (collection, entity_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE sync_cursors (
            collection TEXT PRIMARY KEY,
            cursor TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  // ---- outbox ----

  Future<void> enqueueOp({
    required String clientOpId,
    required String opType,
    required Map<String, dynamic> payload,
  }) async {
    final db = await database;
    await db.insert('outbox', {
      'client_op_id': clientOpId,
      'op_type': opType,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'attempts': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> pendingOps({int limit = 50}) async {
    final db = await database;
    return db.query('outbox',
        orderBy: 'created_at ASC', limit: limit);
  }

  Future<void> removeOp(String clientOpId) async {
    final db = await database;
    await db.delete('outbox',
        where: 'client_op_id = ?', whereArgs: [clientOpId]);
  }

  Future<int> pendingCount() async {
    final db = await database;
    final rows =
        await db.rawQuery('SELECT COUNT(*) AS n FROM outbox');
    return (rows.first['n'] as int?) ?? 0;
  }

  Future<void> incrementAttempts(String clientOpId) async {
    final db = await database;
    await db.rawUpdate(
        'UPDATE outbox SET attempts = attempts + 1 WHERE client_op_id = ?',
        [clientOpId]);
  }

  // ---- entity cache ----

  Future<void> upsertCache(
      String collection, String entityId, Map<String, dynamic> body,
      {String? updatedAt}) async {
    final db = await database;
    await db.insert('cache', {
      'collection': collection,
      'entity_id': entityId,
      'body': jsonEncode(body),
      'updated_at': updatedAt ?? DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> readCollection(String collection,
      {int limit = 200}) async {
    final db = await database;
    final rows = await db.query('cache',
        where: 'collection = ?',
        whereArgs: [collection],
        orderBy: 'updated_at DESC',
        limit: limit);
    return rows
        .map((r) => jsonDecode(r['body'] as String) as Map<String, dynamic>)
        .toList();
  }

  Future<Map<String, dynamic>?> readEntity(
      String collection, String entityId) async {
    final db = await database;
    final rows = await db.query('cache',
        where: 'collection = ? AND entity_id = ?',
        whereArgs: [collection, entityId],
        limit: 1);
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['body'] as String) as Map<String, dynamic>;
  }

  // ---- cursors ----

  Future<void> saveCursor(String collection, String cursor) async {
    final db = await database;
    await db.insert('sync_cursors', {'collection': collection, 'cursor': cursor},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> readCursor(String collection) async {
    final db = await database;
    final rows = await db.query('sync_cursors',
        where: 'collection = ?', whereArgs: [collection], limit: 1);
    return rows.isEmpty ? null : rows.first['cursor'] as String;
  }
}

Future<LocalDb> openLocalDb() async => LocalDb();

final localDbProvider = FutureProvider.autoDispose<LocalDb>((ref) async {
  final db = await openLocalDb();
  ref.onDispose(() => db.database.then((d) => d.close()));
  return db;
});
