import gleam/dynamic

pub type BuildError =
  String

pub type BuildResult(a) =
  Result(a, BuildError)

pub type ParseError {
  DecodeError(dynamic.DecodeError)
  ValidationError(String)
  ExtractionError(ExtractionError)
  InternalError(String)
}

pub type ParseResult(a) =
  Result(a, ParseError)

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
