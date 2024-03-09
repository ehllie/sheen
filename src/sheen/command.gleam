import gleam/dict
import gleam/result
import gleam/option.{None, Some}
import gleam/list
import gleam/dynamic
import sheen/error.{type BuildResult}
import sheen/internal/endec

pub type FlagSpec {
  FlagSpec(
    short: option.Option(String),
    long: option.Option(String),
    display: option.Option(String),
    count: Bool,
    help: String,
  )
}

pub type NamedSpec {
  NamedSpec(
    short: option.Option(String),
    long: option.Option(String),
    display: option.Option(String),
    repeated: Bool,
    optional: Bool,
    help: String,
  )
}

pub type ArgSpec {
  ArgSpec(
    display: option.Option(String),
    repeated: Bool,
    optional: Bool,
    help: String,
  )
}

pub type CommandSpec {
  CommandSpec(
    flags: dict.Dict(String, FlagSpec),
    named: dict.Dict(String, NamedSpec),
    args: List(ArgSpec),
    subcommands: dict.Dict(String, CommandSpec),
    description: option.Option(String),
  )
}

pub type BuilderFn(a) =
  fn(Builder(Nil)) -> BuildResult(Builder(a))

pub type Continuation(a, b) =
  fn(endec.DecodeBuilder(a, b)) -> BuilderFn(b)

pub type Command(a, b) =
  fn(Continuation(a, b)) -> BuilderFn(b)

pub type Builder(a) {
  Builder(
    spec: CommandSpec,
    encoders: endec.Encoders,
    decoder: endec.Decoder(a),
  )
}

pub fn command(
  define: fn(CommandSpec) -> BuildResult(CommandSpec),
  validate: endec.Validator(a),
  decode: dynamic.Decoder(a),
) {
  fn(cont: Continuation(a, b)) {
    fn(builder: Builder(Nil)) {
      let Builder(spec: spec, encoders: encoders, ..) = builder
      use spec <- result.try(define(spec))
      let #(encoders, decode_builder) =
        endec.insert_validator(encoders, validate, decode)
      let builder = Builder(..builder, encoders: encoders, spec: spec)
      cont(decode_builder)(builder)
    }
  }
}

pub fn new() -> CommandSpec {
  CommandSpec(
    flags: dict.new(),
    named: dict.new(),
    args: list.new(),
    subcommands: dict.new(),
    description: None,
  )
}

pub fn describe(description: String, cont: BuilderFn(a)) -> BuilderFn(a) {
  fn(builder: Builder(Nil)) {
    let spec = CommandSpec(..builder.spec, description: Some(description))
    cont(Builder(..builder, spec: spec))
  }
}

pub fn return(decoder: endec.Decoder(a)) -> BuilderFn(a) {
  fn(builder: Builder(Nil)) {
    let Builder(spec, encoders, ..) = builder
    let builder = Builder(spec: spec, encoders: encoders, decoder: decoder)
    Ok(builder)
  }
}
