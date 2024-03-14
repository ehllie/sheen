import gleam/bool
import gleam/dynamic
import gleam/list
import gleam/result

pub type BuildError {
  RuleConflict(String)
}

pub type BuildResult(a) =
  Result(a, List(BuildError))

pub fn rule_conflict(
  requirement: Bool,
  conflict: String,
  alternative: fn() -> BuildResult(a),
) -> BuildResult(a) {
  bool.guard(requirement, Error([RuleConflict(conflict)]), alternative)
}

pub fn as_conflict(res: Result(a, b), conflict: String) -> BuildResult(a) {
  result.replace_error(res, [RuleConflict(conflict)])
}

pub fn from_decode_error(err: List(dynamic.DecodeError)) -> List(ParseError) {
  list.map(err, DecodeError)
}

pub type ParseError {
  DecodeError(dynamic.DecodeError)
  ValidationError(String)
  ExtractionError(ExtractionError)
  InternalError(String)
}

pub type ParseResult(a) =
  Result(a, List(ParseError))

pub type ExtractionError {
  /// When a long option is not recognised.
  UnrecognisedLong(String)
  /// When a short option is not recognised.
  UnrecognisedShort(String)
  /// When too many arguments are given.
  UnexpectedArgument(String)
  /// When a named argument option is not given an argument.
  NoArgument(String)
  /// When a flag is given an argument.
  NotAFlag(String)
}
