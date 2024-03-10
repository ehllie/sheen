import gleam/dict
import gleam/result
import gleam/option.{None}
import gleam/dynamic
import gleam/list
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

pub type Subcommand {
  Optional(spec: CommandSpec)
  Required(spec: CommandSpec)
}

pub type CommandSpec {
  CommandSpec(
    flags: dict.Dict(String, FlagSpec),
    named: dict.Dict(String, NamedSpec),
    args: List(ArgSpec),
    subcommands: dict.Dict(String, Subcommand),
    description: option.Option(String),
  )
}

pub type Command(a) =
  fn(Builder(Nil)) -> BuildResult(Builder(a))

pub type Continuation(a, b) =
  fn(endec.DecodeBuilder(a, b)) -> Command(b)

pub type BuilderFn(a, b) =
  fn(Continuation(a, b)) -> Command(b)

pub type Builder(a) {
  Builder(
    spec: CommandSpec,
    encoders: endec.Encoders,
    decoder: endec.Decoder(a),
  )
}

pub type Definition(a) {
  Definition(
    spec: CommandSpec,
    encode: endec.Encoder,
    decode: dynamic.Decoder(a),
  )
}

pub fn new_spec() {
  CommandSpec(
    flags: dict.new(),
    named: dict.new(),
    args: list.new(),
    subcommands: dict.new(),
    description: None,
  )
}

pub fn new(
  define: fn(Builder(Nil)) -> BuildResult(Definition(a)),
) -> BuilderFn(a, b) {
  fn(cont: Continuation(a, b)) {
    fn(builder: Builder(Nil)) {
      use definition <- result.try(define(builder))
      let Definition(spec: spec, encode: encode, decode: decode) = definition

      let Builder(encoders: encoders, ..) = builder
      let #(encoders, decode_builder) =
        endec.insert_encoder(encoders, encode, decode)
      let builder = Builder(..builder, encoders: encoders, spec: spec)

      cont(decode_builder)(builder)
    }
  }
}
