import gleam/option.{None, Some}
import gleam/list
import gleam/result
import sheen/internal/command_builder as cb
import sheen/internal/extractor
import sheen/internal/endec
import sheen/error.{type BuildError, type ParseError}

pub type ParserSpec {
  ParserSpec(
    cmd: cb.CommandSpec,
    name: option.Option(String),
    authors: List(String),
    version: option.Option(String),
  )
}

pub type Parser(a) {
  Parser(spec: ParserSpec, encoders: endec.Encoders, decoder: endec.Decoder(a))
}

pub fn new() -> ParserSpec {
  ParserSpec(name: None, authors: list.new(), cmd: cb.new_spec(), version: None)
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
  with command: cb.Command(a),
) -> Result(Parser(a), BuildError) {
  let ParserSpec(cmd: cmd, ..) = parser
  let builder = cb.Builder(spec: cmd, encoders: [], decoder: valid(Nil))
  use cb.Builder(spec, encoders, decoder) <- result.try(command(builder))
  let spec = ParserSpec(..parser, cmd: spec)
  Ok(Parser(spec: spec, encoders: encoders, decoder: decoder))
}

pub type Command(a) =
  cb.Command(a)

pub fn describe(description: String, cont: Command(a)) -> Command(a) {
  fn(builder: cb.Builder(Nil)) {
    let spec = cb.CommandSpec(..builder.spec, description: Some(description))
    cont(cb.Builder(..builder, spec: spec))
  }
}

pub fn return(decoder: endec.Decoder(a)) -> Command(a) {
  fn(builder: cb.Builder(Nil)) {
    let cb.Builder(spec, encoders, ..) = builder
    let builder = cb.Builder(spec: spec, encoders: encoders, decoder: decoder)
    Ok(builder)
  }
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
