import gleam/bool.{guard}
import gleam/result
import gleam/list
import gleam/string
import gleam/option.{type Option, None, Some}
import gleam/int
import sheen/command

pub opaque type Builder(a) {
  Builder(
    spec: command.ArgSpec,
    parse: fn(String) -> command.ValidationResult(a),
  )
}

const default_spec = command.ArgSpec(
  display: None,
  optional: False,
  repeated: False,
  help: "",
)

pub fn new() -> Builder(String) {
  Builder(spec: default_spec, parse: fn(value) { Ok(value) })
}

pub fn display(builder: Builder(a), display: String) -> Builder(a) {
  Builder(
    ..builder,
    spec: command.ArgSpec(..builder.spec, display: Some(display)),
  )
}

pub fn help(builder: Builder(a), help: String) -> Builder(a) {
  Builder(..builder, spec: command.ArgSpec(..builder.spec, help: help))
}

pub fn repeated(builder: Builder(a)) -> command.Command(List(a), b) {
  Builder(..builder, spec: command.ArgSpec(..builder.spec, repeated: True))
  |> build(fn(parser, values) {
    list.map(values, parser)
    |> result.all
  })
}

pub fn required(builder: Builder(a)) -> command.Command(a, b) {
  Builder(..builder, spec: command.ArgSpec(..builder.spec, optional: False))
  |> build(fn(parser, values) {
    case values {
      [value] -> parser(value)
      _ -> Error("Expected exactly one value")
    }
  })
}

pub fn optional(builder: Builder(a)) -> command.Command(Option(a), b) {
  Builder(..builder, spec: command.ArgSpec(..builder.spec, optional: True))
  |> build(fn(parser, values) {
    case values {
      [value] ->
        parser(value)
        |> result.map(Some)
      [] -> Ok(None)
      _ -> Error("Expected at most one value")
    }
  })
}

pub fn integer(builder: Builder(String)) -> Builder(Int) {
  Builder(
    spec: command.ArgSpec(
      ..builder.spec,
      display: option.or(builder.spec.display, Some("INTEGER")),
    ),
    parse: fn(value) {
      case int.parse(value) {
        Ok(value) -> Ok(value)
        Error(_) -> Error("Expected an integer")
      }
    },
  )
}

pub fn enum(builder: Builder(String), values: List(#(String, a))) -> Builder(a) {
  Builder(
    spec: command.ArgSpec(
      ..builder.spec,
      display: option.or(builder.spec.display, Some("ENUM")),
    ),
    parse: fn(value) {
      case list.find(values, fn(variant) { variant.0 == value }) {
        Ok(#(_, value)) -> Ok(value)
        _ ->
          Error(
            "Expected one of: "
            <> string.join(list.map(values, fn(variant) { variant.0 }), ", "),
          )
      }
    },
  )
}

fn build(
  builder: Builder(a),
  map: fn(fn(String) -> command.ValidationResult(a), List(String)) ->
    command.ValidationResult(b),
) -> command.Command(b, c) {
  command.command(fn(cmd: command.CommandSpec) {
    let Builder(spec, parse) = builder
    let command.ArgSpec(optional: optional, repeated: repeated, ..) = spec

    use <- guard(
      optional && repeated,
      Error("Arguments can be either optional or repeated, not both"),
    )

    let conflict = case list.last(cmd.args) {
      Ok(command.ArgSpec(repeated: True, ..)) ->
        "Can't add a positional argument after a repeated one"
      Ok(command.ArgSpec(optional: True, ..)) if !optional || !repeated ->
        "Can't add a required positional argument after an optional one"
      _ -> ""
    }

    use <- guard(conflict != "", Error(conflict))
    let position = list.length(cmd.args)
    let cmd = command.CommandSpec(..cmd, args: list.append(cmd.args, [spec]))
    let validator = fn(input: command.ValidatorInput) {
      let values = list.drop(input.args, position)
      let values = case repeated {
        True -> values
        False -> list.take(values, 1)
      }
      map(parse, values)
    }

    Ok(command.Builder(cmd, validator))
  })
}
