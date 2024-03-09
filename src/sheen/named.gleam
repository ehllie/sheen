import gleam/bool.{guard}
import gleam/result
import gleam/dict
import gleam/list
import gleam/string
import gleam/option.{type Option, None, Some}
import gleam/int
import sheen/command

pub opaque type Builder(a) {
  Builder(
    name: String,
    spec: command.NamedSpec,
    parse: fn(String) -> command.ValidationResult(a),
  )
}

const default_spec = command.NamedSpec(
  short: None,
  long: None,
  display: None,
  optional: False,
  repeated: False,
  help: "",
)

pub fn new(name: String) -> Builder(String) {
  Builder(name: name, spec: default_spec, parse: fn(value) { Ok(value) })
}

pub fn short(builder: Builder(a), short: String) -> Builder(a) {
  Builder(
    ..builder,
    spec: command.NamedSpec(..builder.spec, short: Some(short)),
  )
}

pub fn long(builder: Builder(a), long: String) -> Builder(a) {
  Builder(..builder, spec: command.NamedSpec(..builder.spec, long: Some(long)))
}

pub fn display(builder: Builder(a), display: String) -> Builder(a) {
  Builder(
    ..builder,
    spec: command.NamedSpec(..builder.spec, display: Some(display)),
  )
}

pub fn help(builder: Builder(a), help: String) -> Builder(a) {
  Builder(..builder, spec: command.NamedSpec(..builder.spec, help: help))
}

pub fn repeated(builder: Builder(a)) -> command.Command(List(a), b) {
  Builder(..builder, spec: command.NamedSpec(..builder.spec, repeated: True))
  |> build(fn(parser, values) {
    list.map(values, parser)
    |> result.all
  })
}

pub fn required(builder: Builder(a)) -> command.Command(a, b) {
  Builder(..builder, spec: command.NamedSpec(..builder.spec, optional: False))
  |> build(fn(parser, values) {
    case values {
      [value] -> parser(value)
      _ -> Error("Expected exactly one value")
    }
  })
}

pub fn optional(builder: Builder(a)) -> command.Command(Option(a), b) {
  Builder(..builder, spec: command.NamedSpec(..builder.spec, optional: True))
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
    name: builder.name,
    spec: command.NamedSpec(
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
    name: builder.name,
    spec: command.NamedSpec(
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
    let Builder(name, spec, parse) = builder
    let command.NamedSpec(long: long, short: short, ..) = spec

    use first <- result.try(
      string.first(name)
      |> result.replace_error("Argument name cannot be empty"),
    )

    let long = option.unwrap(long, name)
    let short = option.unwrap(short, first)

    use <- guard(
      dict.has_key(cmd.named, name),
      Error("Argument " <> name <> " already defined"),
    )

    let spec = command.NamedSpec(..spec, short: Some(short), long: Some(long))
    let named = dict.insert(cmd.named, name, spec)
    let cmd = command.CommandSpec(..cmd, named: named)

    let validator = fn(input: command.ValidatorInput) {
      dict.get(input.named, name)
      |> result.unwrap([])
      |> map(parse, _)
    }

    Ok(command.Builder(cmd, validator))
  })
}
