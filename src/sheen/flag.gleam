import gleam/bool.{guard}
import gleam/dict
import gleam/result
import gleam/option.{None, Some}
import gleam/string
import gleam/dynamic
import sheen/error
import sheen/command
import sheen/internal/endec

pub opaque type Builder {
  Builder(name: String, spec: command.FlagSpec)
}

const default_desc = command.FlagSpec(
  short: None,
  long: None,
  display: None,
  count: False,
  help: "",
)

pub fn new(name: String) -> Builder {
  Builder(name: name, spec: default_desc)
}

pub fn short(builder: Builder, short: String) -> Builder {
  Builder(..builder, spec: command.FlagSpec(..builder.spec, short: Some(short)))
}

pub fn long(builder: Builder, long: String) -> Builder {
  Builder(..builder, spec: command.FlagSpec(..builder.spec, long: Some(long)))
}

pub fn display(builder: Builder, display: String) -> Builder {
  Builder(
    ..builder,
    spec: command.FlagSpec(..builder.spec, display: Some(display)),
  )
}

pub fn help(builder: Builder, help: String) -> Builder {
  Builder(..builder, spec: command.FlagSpec(..builder.spec, help: help))
}

pub fn count(builder: Builder) -> command.Command(Int, a) {
  build(builder, Ok, dynamic.int)
}

pub fn boolean(builder: Builder) -> command.Command(Bool, a) {
  build(builder, fn(count: Int) { Ok(count > 0) }, dynamic.bool)
}

fn build(
  builder: Builder,
  map: fn(Int) -> error.ParseResult(a),
  decode: dynamic.Decoder(a),
) -> command.Command(a, b) {
  let Builder(name, spec) = builder

  let define = fn(cmd: command.CommandSpec) {
    let command.FlagSpec(long: long, short: short, ..) = spec

    use first <- result.try(
      string.first(name)
      |> result.replace_error("Flag name cannot be empty"),
    )

    let long = option.unwrap(long, name)
    let short = option.unwrap(short, first)

    use <- guard(
      dict.has_key(cmd.flags, name),
      Error("Flag " <> name <> " already defined"),
    )

    let spec = command.FlagSpec(..spec, long: Some(long), short: Some(short))
    let flags = dict.insert(cmd.flags, name, spec)
    let cmd = command.CommandSpec(..cmd, flags: flags)

    Ok(cmd)
  }

  let validate = fn(input: endec.ValidatorInput) {
    let count =
      dict.get(input.flags, name)
      |> result.unwrap(0)
    map(count)
  }

  command.command(define, validate, decode)
}
