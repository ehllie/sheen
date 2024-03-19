import gleam/dynamic
import gleam/list
import gleam/result

pub type BuildError {
  RuleConflict(String)
  ReusedShort(String)
  ReusedLong(String)
}

pub type BuildResult(a) =
  Result(a, List(BuildError))

pub fn rule_conflict(
  requirement: Bool,
  conflict: String,
  alternative: fn() -> BuildResult(a),
) -> BuildResult(a) {
  emit_error_guard(requirement, RuleConflict(conflict), alternative)
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

pub fn collect_results(
  results: List(Result(ok, List(err))),
) -> Result(List(ok), List(err)) {
  let #(ok, errors) = result.partition(results)
  case errors {
    [] -> Ok(ok)
    _ -> Error(list.concat(errors))
  }
}

pub fn emit_error_guard(
  condition: Bool,
  error: err,
  callback: fn() -> Result(ok, List(err)),
) {
  case callback(), condition {
    res, False -> res
    Ok(_), True -> Error([error])
    Error(errors), True -> Error([error, ..errors])
  }
}

pub fn emit_errors(errors: List(err), callback: fn() -> Result(ok, List(err))) {
  case callback(), errors {
    res, [] -> res
    Ok(_), _ -> Error(errors)
    Error(new_errors), _ -> Error(list.append(errors, new_errors))
  }
}
