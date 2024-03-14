import gleam/dict
import gleam/list
import gleam/option.{None}
import sheen/internal/endec
import sheen/internal/error.{type BuildResult}

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

pub type Command(a) {
  Command(fn(Builder(Nil)) -> BuildResult(Builder(a)))
}

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
    decode: endec.DecodeFn(a),
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
    Command(fn(builder: Builder(Nil)) {
      case define(builder) {
        Ok(definition) -> {
          let Definition(spec: spec, encode: encode, decode: decode) =
            definition

          let Builder(encoders: encoders, ..) = builder
          let #(encoders, decode_builder) =
            endec.insert_encoder(encoders, encode, decode)
          let builder = Builder(..builder, encoders: encoders, spec: spec)

          let Command(cmd) = cont(decode_builder)
          cmd(builder)
        }
        Error(define_errors) -> {
          let fake_builder = fn(_) {
            endec.Decoder(fn(_) { Error([error.InternalError("")]) })
          }
          let Command(cmd) = cont(fake_builder)
          case cmd(builder) {
            Ok(_) -> {
              Error(define_errors)
            }
            Error(errors) -> {
              Error(list.append(define_errors, errors))
            }
          }
        }
      }
    })
  }
}
