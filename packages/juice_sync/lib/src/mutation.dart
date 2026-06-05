/// Lifecycle of one queued mutation.
enum MutationStatus {
  /// Waiting to be sent (or waiting on a backoff).
  pending,

  /// Currently being sent (persisted so a crash mid-send is recoverable).
  inFlight,

  /// Dead-lettered — permanent failure or max attempts exhausted.
  failed,
}

/// A durable record of an intended write.
///
/// [id] is client-generated and is **the idempotency key** — delivery is
/// at-least-once, so the executor's adapter must send `id` to the server and the
/// server must dedupe on it. [seq] is a monotonic, persisted ordering key
/// (durable FIFO across restarts — never order by [createdAt], which is wall
/// clock and can skew).
class Mutation {
  final String id;
  final int seq;
  final String type;
  final Map<String, Object?> payload;

  /// Mutations sharing an [orderingKey] are sent in strict FIFO order; a blocked
  /// one holds back only its own key. Null means independent (its own partition).
  final String? orderingKey;

  final DateTime createdAt;
  final int attempts;
  final String? lastError;
  final MutationStatus status;

  const Mutation({
    required this.id,
    required this.seq,
    required this.type,
    required this.payload,
    this.orderingKey,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
    this.status = MutationStatus.pending,
  });

  /// The partition this mutation orders within. Null [orderingKey] ⇒ its own id,
  /// so independent mutations never block one another.
  String get partition => orderingKey ?? id;

  Mutation copyWith({
    int? attempts,
    Object? lastError = _unset,
    MutationStatus? status,
  }) {
    return Mutation(
      id: id,
      seq: seq,
      type: type,
      payload: payload,
      orderingKey: orderingKey,
      createdAt: createdAt,
      attempts: attempts ?? this.attempts,
      lastError: identical(lastError, _unset) ? this.lastError : lastError as String?,
      status: status ?? this.status,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'seq': seq,
        'type': type,
        'payload': payload,
        'orderingKey': orderingKey,
        'createdAt': createdAt.toIso8601String(),
        'attempts': attempts,
        'lastError': lastError,
        'status': status.name,
      };

  factory Mutation.fromJson(Map<String, Object?> json) => Mutation(
        id: json['id'] as String,
        seq: json['seq'] as int,
        type: json['type'] as String,
        payload: (json['payload'] as Map).cast<String, Object?>(),
        orderingKey: json['orderingKey'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        attempts: json['attempts'] as int? ?? 0,
        lastError: json['lastError'] as String?,
        status: MutationStatus.values.byName(json['status'] as String? ?? 'pending'),
      );

  @override
  String toString() => 'Mutation($id, seq:$seq, $type, $status, attempts:$attempts)';
}

const Object _unset = Object();
