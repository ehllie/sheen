import gleam/option.{None, Some}
import gleam/list
import gleam/result
import sheen/command
import sheen/internal/extractor
import sheen/internal/endec
import sheen/error.{type BuildError, type ParseError}

pub type ParserSpec {
  ParserSpec(
    cmd: command.CommandSpec,
    name: option.Option(String),
    authors: List(String),
    version: option.Option(String),
  )
}

pub type Parser(a) {
  Parser(spec: ParserSpec, encoders: endec.Encoders, decoder: endec.Decoder(a))
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
  with build_fn: command.BuilderFn(a),
) -> Result(Parser(a), BuildError) {
  let ParserSpec(cmd: cmd, ..) = parser
  let builder = command.Builder(spec: cmd, encoders: [], decoder: valid(Nil))
  use command.Builder(spec, encoders, decoder) <- result.try(build_fn(builder))
  let spec = ParserSpec(..parser, cmd: spec)
  Ok(Parser(spec: spec, encoders: encoders, decoder: decoder))
}

pub fn valid(value: a) -> endec.Decoder(a) {
  endec.Decoder(fn(_) { Ok(value) })
}

pub type ParseResult(a) =
  Result(a, List(ParseError))

pub fn run(parser: Parser(a), args: List(String)) -> ParseResult(a) {
  let Parser(spec, encoders, decoder) = parser
  let ParserSpec(cmd, ..) = spec
  let #(result, errors) =
    extractor.new(cmd)
    |> extractor.run(args)
  case errors {
    [] ->
      result
      |> endec.validate_and_run(encoders, decoder)
      |> result.map_error(fn(e) { e })

    errors -> Error(errors)
  }
}
