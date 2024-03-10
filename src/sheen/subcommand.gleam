// pub fn optional(subcommands)
import gleam/option.{type Option, None, Some}
import gleam/list
import gleam/bool
import gleam/dict
import gleam/dynamic
import gleam/result
import gleam/function
import sheen/internal/command_builder as cb
import sheen/internal/endec

pub type Builder(a) {
  Builder(name: String, command: cb.Command(a))
}

pub fn new(name: String, command: cb.Command(a)) {
  Builder(name: name, command: command)
}

pub fn optional(
  name: String,
  subcommand: cb.Command(a),
  cont: cb.Continuation(Option(a), b),
) -> cb.Command(b) {
  cb.new(fn(builder) {
    let subcommands =
      builder.spec.subcommands
      |> dict.values
    let mismatched_commands = case subcommands {
      [cb.Required(_), ..] -> True
      _ -> False
    }

    use <- bool.guard(
      mismatched_commands,
      Error("Optional and required subcommands can't be mixed"),
    )

    use <- bool.guard(
      dict.has_key(builder.spec.subcommands, name),
      Error("Subcommand " <> name <> " defined twice"),
    )

    let inner_builder =
      cb.Builder(
        spec: cb.new_spec(),
        encoders: [],
        decoder: endec.Decoder(fn(_) { Ok(Nil) }),
      )
    use inner_builder <- result.try(subcommand(inner_builder))
    let cb.Builder(spec, encoders, decoder) = inner_builder
    let cmd =
      cb.CommandSpec(
        ..builder.spec,
        subcommands: dict.insert(
          builder.spec.subcommands,
          name,
          cb.Optional(spec),
        ),
      )

    let encode = fn(input: endec.EncoderInput) {
      case dict.get(input.subcommands, name) {
        Ok(input) ->
          list.map(encoders, function.apply1(_, input))
          |> result.all
          |> result.map(Some)
          |> result.map(dynamic.from)
        _ -> Ok(dynamic.from(None))
      }
    }

    let decode = fn(dyn) {
      use values <- result.try(
        dyn
        |> dynamic.optional(dynamic.list(dynamic.dynamic)),
      )
      case values {
        Some(values) -> {
          let endec.Decoder(decoder) = decoder
          use result <- result.try(
            decoder(values)
            |> result.replace_error([]),
          )
          Ok(Some(result))
        }
        None -> Ok(None)
      }
    }

    Ok(cb.Definition(cmd, encode, decode))
  })(cont)
}
