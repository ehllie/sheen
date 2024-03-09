import gleam/option.{None, Some}
import gleam/list
import gleam/result
import sheen/command.{type Validator}
import sheen/internal/extractor

pub type ParserSpec {
  ParserSpec(
    cmd: command.CommandSpec,
    name: option.Option(String),
    authors: List(String),
    version: option.Option(String),
  )
}

pub type Parser(a) {
  Parser(spec: ParserSpec, validator: Validator(a))
}

pub fn new() -> ParserSpec {
  ParserSpec(name: None, authors: list.new(), cmd: command.new(), version: None)
}

pub fn name(to parser: ParserSpec, set name: String) {
  ParserSpec(..parser, name: Some(name))
}

pub fn authors(to parser: ParserSpec, set authors: List(String)) {
  ParserSpec(..parser, authors: authors)
}

pub fn version(to parser: ParserSpec, set version: String) {
  ParserSpec(..parser, version: Some(version))
}

pub fn build(
  from parser: ParserSpec,
  with builder: command.BuilderFn(a),
) -> Result(Parser(a), command.BuildError) {
  use command.Builder(spec, validator) <- result.try(builder(parser.cmd))
  let spec = ParserSpec(..parser, cmd: spec)
  Ok(Parser(spec, validator))
}

pub fn extract(
  from validator: Validator(a),
  to cont: fn(a) -> Validator(b),
) -> Validator(b) {
  fn(input) {
    use result <- result.try(validator(input))
    cont(result)(input)
  }
}

pub type ParseError {
  ExtractionError(List(extractor.ExtractionError))
  ValidationError(command.ValidationError)
}

pub type ParseResult(a) =
  Result(a, ParseError)

pub fn run(parser: Parser(a), args: List(String)) -> ParseResult(a) {
  let Parser(spec, validator) = parser
  let ParserSpec(cmd, ..) = spec
  let #(result, errors) =
    extractor.new(cmd)
    |> extractor.run(args)
  case errors {
    [] ->
      validator(result)
      |> result.map_error(fn(ve) { ValidationError(ve) })
    _ -> Error(ExtractionError(errors))
  }
}
