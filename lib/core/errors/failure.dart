/// Shared Failure/Result pattern per architecture.md "Error Handling":
/// all Supabase/AI calls are wrapped in try/catch and surfaced through
/// these types — no raw exceptions bubbling to UI.
sealed class Failure {
  final String message;
  const Failure(this.message);

  @override
  String toString() => message;
}

class AiFailure extends Failure {
  const AiFailure(super.message);
}

class SupabaseFailure extends Failure {
  const SupabaseFailure(super.message);
}

class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

/// Lightweight Result wrapper so providers can return either a value
/// or a Failure without throwing raw exceptions into the UI layer.
sealed class Result<T> {
  const Result();

  factory Result.success(T value) = Success<T>;
  factory Result.failure(Failure failure) = Error<T>;

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Error<T>;
}

class Success<T> extends Result<T> {
  final T value;
  const Success(this.value);
}

class Error<T> extends Result<T> {
  final Failure failure;
  const Error(this.failure);
}
