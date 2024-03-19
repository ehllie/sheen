import gleam/dict
import gleam/dynamic
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import sheen/internal/command_builder as cb
import sheen/internal/endec
import sheen/internal/error.{rule_conflict}

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
  build(builder, Ok, endec.decode_int)
}

pub fn boolean(builder: Builder) -> cb.BuilderFn(Bool, a) {
  build(builder, fn(count: Int) { Ok(count > 0) }, endec.decode_bool)
}

fn build(
  builder: Builder,
  map: fn(Int) -> error.ParseResult(a),
  decode: endec.DecodeFn(a),
) -> cb.BuilderFn(a, b) {
  cb.new(fn(cmd_builder: cb.Builder(Nil)) {
    let Builder(name, spec) = builder
    let cb.FlagSpec(long: long, short: short, ..) = spec
    let cb.Builder(spec: cmd, ..) = cmd_builder

    let long = option.unwrap(long, name)

    use <- rule_conflict(long == "", "Flag name cannot be empty")

    let invalid_short = case short {
      Some(s) ->
        case string.length(s) {
          1 -> ""
          _ -> "Short flag must be a single character: " <> s
        }
      None -> ""
    }

    use <- rule_conflict(invalid_short != "", invalid_short)

    use <- rule_conflict(
      dict.has_key(cmd.flags, name),
      "Flag " <> name <> " already defined",
    )

    let spec = cb.FlagSpec(..spec, long: Some(long))
    let flags = dict.insert(cmd.flags, name, spec)
    let cmd = cb.CommandSpec(..cmd, flags: flags)

    let encode = fn(input: endec.EncoderInput) {
      let count =
        dict.get(input.flags, name)
        |> result.unwrap(0)
      map(count)
      |> result.map(dynamic.from)
    }

    Ok(cb.Definition(cmd, encode, decode))
  })
}
