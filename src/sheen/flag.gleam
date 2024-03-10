import gleam/bool.{guard}
import gleam/dict
import gleam/result
import gleam/option.{None, Some}
import gleam/string
import gleam/dynamic
import sheen/error
import sheen/internal/command_builder as cb
import sheen/internal/endec

pub opaque type Builder {
  Builder(name: String, spec: cb.FlagSpec)
}

const default_desc = cb.FlagSpec(
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
  Builder(..builder, spec: cb.FlagSpec(..builder.spec, short: Some(short)))
}

pub fn long(builder: Builder, long: String) -> Builder {
  Builder(..builder, spec: cb.FlagSpec(..builder.spec, long: Some(long)))
}

pub fn display(builder: Builder, display: String) -> Builder {
  Builder(..builder, spec: cb.FlagSpec(..builder.spec, display: Some(display)))
}

pub fn help(builder: Builder, help: String) -> Builder {
  Builder(..builder, spec: cb.FlagSpec(..builder.spec, help: help))
}

pub fn count(builder: Builder) -> cb.BuilderFn(Int, a) {
  build(builder, Ok, dynamic.int)
}

pub fn boolean(builder: Builder) -> cb.BuilderFn(Bool, a) {
  build(builder, fn(count: Int) { Ok(count > 0) }, dynamic.bool)
}

fn build(
  builder: Builder,
  map: fn(Int) -> error.ParseResult(a),
  decode: dynamic.Decoder(a),
) -> cb.BuilderFn(a, b) {
  cb.new(fn(cmd_builder: cb.Builder(Nil)) {
    let Builder(name, spec) = builder
    let cb.FlagSpec(long: long, short: short, ..) = spec
    let cb.Builder(spec: cmd, ..) = cmd_builder

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

    let spec = cb.FlagSpec(..spec, long: Some(long), short: Some(short))
    let flags = dict.insert(cmd.flags, name, spec)
    let cmd = cb.CommandSpec(..cmd, flags: flags)

    let validate = fn(input: endec.ValidatorInput) {
      let count =
        dict.get(input.flags, name)
        |> result.unwrap(0)
      map(count)
    }

    Ok(cb.Definition(cmd, validate, decode))
  })
}
