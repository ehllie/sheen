import gleam/dynamic
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import sheen/error.{from_decode_error, rule_conflict}
import sheen/internal/command_builder as cb
import sheen/internal/endec

pub opaque type Builder(a) {
  Builder(
    spec: cb.ArgSpec,
    parse: fn(String) -> error.ParseResult(a),
    decode: dynamic.Decoder(a),
  )
}

const default_spec = cb.ArgSpec(
  display: None,
  optional: False,
  repeated: False,
  help: "",
)

pub fn new() -> Builder(String) {
  Builder(
    spec: default_spec,
    parse: fn(value) { Ok(value) },
    decode: dynamic.string,
  )
}

pub fn display(builder: Builder(a), display: String) -> Builder(a) {
  Builder(..builder, spec: cb.ArgSpec(..builder.spec, display: Some(display)))
}

pub fn help(builder: Builder(a), help: String) -> Builder(a) {
  Builder(..builder, spec: cb.ArgSpec(..builder.spec, help: help))
}

pub fn repeated(builder: Builder(a)) -> cb.BuilderFn(List(a), b) {
  Builder(..builder, spec: cb.ArgSpec(..builder.spec, repeated: True))
  |> build(
    fn(parser, values) {
      list.map(values, parser)
      |> result.all
    },
    fn(decoder) {
      fn(dyn) {
        dynamic.list(decoder)(dyn)
        |> result.map_error(from_decode_error)
      }
    },
  )
}

pub fn required(builder: Builder(a)) -> cb.BuilderFn(a, b) {
  Builder(..builder, spec: cb.ArgSpec(..builder.spec, optional: False))
  |> build(
    fn(parser, values) {
      case values {
        [value] -> parser(value)
        _ -> Error([error.ValidationError("Expected exactly one value")])
      }
    },
    fn(decoder) {
      fn(dyn) {
        decoder(dyn)
        |> result.map_error(from_decode_error)
      }
    },
  )
}

pub fn optional(builder: Builder(a)) -> cb.BuilderFn(Option(a), b) {
  Builder(..builder, spec: cb.ArgSpec(..builder.spec, optional: True))
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
    fn(decoder) {
      fn(dyn) {
        dynamic.optional(decoder)(dyn)
        |> result.map_error(from_decode_error)
      }
    },
  )
}

pub fn integer(builder: Builder(String)) -> Builder(Int) {
  Builder(
    spec: cb.ArgSpec(
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
    spec: cb.ArgSpec(
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
  decode_wrap: fn(dynamic.Decoder(a)) -> endec.DecodeFn(b),
) -> cb.BuilderFn(b, c) {
  cb.new(fn(cmd_builder: cb.Builder(Nil)) {
    let Builder(spec, parse, decode) = builder
    let cb.ArgSpec(optional: optional, repeated: repeated, ..) = spec
    let cb.Builder(spec: cmd, ..) = cmd_builder
    let position = list.length(cmd.args)

    use <- rule_conflict(
      optional && repeated,
      "Arguments can be either optional or repeated, not both",
    )

    let required = !optional || !repeated
    let conflict = case list.last(cmd.args) {
      Ok(cb.ArgSpec(repeated: True, ..)) ->
        "Can't add a positional argument after a repeated one"
      Ok(cb.ArgSpec(optional: True, ..)) if required ->
        "Can't add a required positional argument after an optional one"
      _ -> ""
    }

    use <- rule_conflict(conflict != "", conflict)
    let cmd = cb.CommandSpec(..cmd, args: list.append(cmd.args, [spec]))

    let encode = fn(input: endec.EncoderInput) {
      let values = list.drop(input.args, position)
      let values = case repeated {
        True -> values
        False -> list.take(values, 1)
      }
      map(parse, values)
      |> result.map(dynamic.from)
    }

    let decode = decode_wrap(decode)

    Ok(cb.Definition(cmd, encode, decode))
  })
}
