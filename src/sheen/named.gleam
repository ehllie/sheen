import gleam/dict
import gleam/dynamic
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import sheen/internal/command_builder as cb
import sheen/internal/endec
import sheen/internal/error.{rule_conflict}

pub opaque type Builder(a) {
  Builder(
    name: String,
    spec: cb.NamedSpec,
    parse: fn(String) -> error.ParseResult(a),
    decode: dynamic.Decoder(a),
  )
}

const default_spec = cb.NamedSpec(
  short: None,
  long: None,
  display: None,
  optional: False,
  repeated: False,
  help: "",
)

pub fn new(name: String) -> Builder(String) {
  Builder(
    name: name,
    spec: default_spec,
    parse: fn(value) { Ok(value) },
    decode: dynamic.string,
  )
}

pub fn short(builder: Builder(a), short: String) -> Builder(a) {
  Builder(..builder, spec: cb.NamedSpec(..builder.spec, short: Some(short)))
}

pub fn long(builder: Builder(a), long: String) -> Builder(a) {
  Builder(..builder, spec: cb.NamedSpec(..builder.spec, long: Some(long)))
}

pub fn display(builder: Builder(a), display: String) -> Builder(a) {
  Builder(..builder, spec: cb.NamedSpec(..builder.spec, display: Some(display)))
}

pub fn help(builder: Builder(a), help: String) -> Builder(a) {
  Builder(..builder, spec: cb.NamedSpec(..builder.spec, help: help))
}

pub fn repeated(builder: Builder(a)) -> cb.BuilderFn(List(a), b) {
  Builder(..builder, spec: cb.NamedSpec(..builder.spec, repeated: True))
  |> build(
    fn(parser, values) {
      list.map(values, parser)
      |> result.all
    },
    endec.decode_list,
  )
}

pub fn required(builder: Builder(a)) -> cb.BuilderFn(a, b) {
  Builder(..builder, spec: cb.NamedSpec(..builder.spec, optional: False))
  |> build(
    fn(parser, values) {
      case values {
        [value] -> parser(value)
        _ -> Error([error.ValidationError("Expected exactly one value")])
      }
    },
    endec.from_dynamic,
  )
}

pub fn optional(builder: Builder(a)) -> cb.BuilderFn(Option(a), b) {
  Builder(..builder, spec: cb.NamedSpec(..builder.spec, optional: True))
  |> build(
    fn(parser, values) {
      case values {
        [value] ->
          parser(value)
          |> result.map(Some)
        [] -> Ok(None)
        _ -> Error([error.ValidationError("Expected at most one value")])
      }
    },
    endec.decode_optional,
  )
}

pub fn integer(builder: Builder(String)) -> Builder(Int) {
  Builder(
    name: builder.name,
    spec: cb.NamedSpec(
      ..builder.spec,
      display: option.or(builder.spec.display, Some("INTEGER")),
    ),
    parse: fn(value) {
      case int.parse(value) {
        Ok(value) -> Ok(value)
        Error(_) -> Error([error.ValidationError("Expected an integer")])
      }
    },
    decode: dynamic.int,
  )
}

pub fn enum(builder: Builder(String), values: List(#(String, a))) -> Builder(a) {
  let #(parse, decode) = endec.enum(values)
  Builder(
    name: builder.name,
    spec: cb.NamedSpec(
      ..builder.spec,
      display: option.or(builder.spec.display, Some("ENUM")),
    ),
    parse: parse,
    decode: decode,
  )
}

fn build(
  builder: Builder(a),
  map: fn(fn(String) -> error.ParseResult(a), List(String)) ->
    error.ParseResult(b),
  decode_wrapper: fn(dynamic.Decoder(a)) -> endec.DecodeFn(b),
) -> cb.BuilderFn(b, c) {
  cb.new(fn(cmd_builder: cb.Builder(Nil)) {
    let Builder(name, spec, parse, decode) = builder
    let cb.NamedSpec(long: long, short: short, ..) = spec
    let cb.Builder(spec: cmd, ..) = cmd_builder

    let long = option.unwrap(long, name)

    use <- rule_conflict(long == "", "Argument name cannot be empty")

    let invalid_short = case short {
      Some(s) ->
        case string.length(s) {
          1 -> ""
          _ -> "Argument short name must be a single character: " <> s
        }
      None -> ""
    }

    use <- rule_conflict(invalid_short != "", invalid_short)

    use <- rule_conflict(
      dict.has_key(cmd.named, name),
      "Argument " <> name <> " already defined",
    )

    let spec = cb.NamedSpec(..spec, long: Some(long))
    let named = dict.insert(cmd.named, name, spec)
    let cmd = cb.CommandSpec(..cmd, named: named)

    let encode = fn(input: endec.EncoderInput) {
      dict.get(input.named, name)
      |> result.unwrap([])
      |> map(parse, _)
      |> result.map(dynamic.from)
    }

    let decode = decode_wrapper(decode)

    Ok(cb.Definition(cmd, encode, decode))
  })
}
