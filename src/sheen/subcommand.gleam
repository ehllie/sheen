import gleam/dict
import gleam/dynamic
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/result
import gleam/set
import gleam/string
import sheen/error.{rule_conflict}
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

    use <- rule_conflict(
      mismatched_commands,
      "Optional and required subcommands can't be mixed",
    )

    use <- rule_conflict(
      dict.has_key(builder.spec.subcommands, name),
      "Subcommand " <> name <> " defined twice",
    )

    let inner_builder =
      cb.Builder(
        spec: cb.new_spec(),
        encoders: [],
        decoder: endec.Decoder(fn(_) { Ok(Nil) }),
      )
    let cb.Command(cmd) = subcommand
    use inner_builder <- result.try(cmd(inner_builder))
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
          endec.encode_all(input, encoders)
          |> result.map(Some)
          |> result.map(dynamic.from)
        _ -> Ok(dynamic.from(None))
      }
    }

    let decode = fn(dyn) {
      use values <- result.try(
        dyn
        |> endec.from_dynamic(dynamic.optional(dynamic.list(dynamic.dynamic))),
      )
      case values {
        Some(values) -> {
          let endec.Decoder(decoder) = decoder
          use result <- result.try(decoder(values))
          Ok(Some(result))
        }
        None -> Ok(None)
      }
    }

    Ok(cb.Definition(cmd, encode, decode))
  })(cont)
}

pub fn required(commands: List(#(String, cb.Command(a))), cont) {
  cb.new(fn(builder) {
    let subcommands = builder.spec.subcommands

    use <- rule_conflict(
      dict.new() != subcommands,
      "Required subcommands can only be used if no subcommands were defined previously",
    )

    use <- rule_conflict(
      [] == commands,
      "You must define at least one subcommand to require",
    )

    let names = list.map(commands, pair.first)

    let #(_, non_unique) =
      list.fold(names, #(set.new(), []), fn(acc, name) {
        let #(names, non_unique) = acc
        case set.contains(names, name) {
          True -> #(names, [name, ..non_unique])
          False -> #(set.insert(names, name), non_unique)
        }
      })

    use <- rule_conflict([] != non_unique, {
      "Subcommands defined multiple times: " <> string.join(non_unique, ", ")
    })

    use #(cmd, encoders, decoders) <- result.try(
      list.fold(commands, Ok(#(builder.spec, [], [])), fn(acc, subcommand) {
        use #(cmd_spec, encoders, decoders) <- result.try(acc)
        let #(name, cb.Command(cmd)) = subcommand
        let inner_builder =
          cb.Builder(
            spec: cb.new_spec(),
            encoders: [],
            decoder: endec.Decoder(fn(_) { Ok(Nil) }),
          )
        use inner_builder <- result.try(cmd(inner_builder))
        let cb.Builder(spec, new_encoders, decoder) = inner_builder
        let cmd =
          cb.CommandSpec(
            ..cmd_spec,
            subcommands: dict.insert(
              cmd_spec.subcommands,
              name,
              cb.Required(spec),
            ),
          )

        Ok(#(cmd, [new_encoders, ..encoders], [decoder, ..decoders]))
      }),
    )

    let encoders = list.reverse(encoders)
    let decoders = list.reverse(decoders)

    let encode = fn(input: endec.EncoderInput) {
      list.zip(names, encoders)
      |> list.index_map(fn(item, idx) {
        let #(name, encoders) = item
        use input <- result.try(
          dict.get(input.subcommands, name)
          |> result.replace_error([
            error.ValidationError("A subcommand must be specified"),
          ]),
        )

        use values <- result.try(endec.encode_all(input, encoders))

        Ok(dynamic.from(pair.new(idx, values)))
      })
      |> list.reduce(result.or)
      |> result.replace_error([
        error.InternalError(
          "There were no subcommands passed into the required subcommand builder. This should have been caught earlier",
        ),
      ])
      |> result.flatten
    }

    let decode = fn(dyn) {
      use #(idx, dyn_list) <- result.try(
        dyn
        |> endec.from_dynamic(dynamic.decode2(
          pair.new,
          dynamic.element(0, dynamic.int),
          dynamic.element(1, dynamic.list(dynamic.dynamic)),
        )),
      )
      use endec.Decoder(decoder) <- result.try(
        list.at(decoders, idx)
        |> result.replace_error([error.InternalError("Decoder not found")]),
      )

      decoder(dyn_list)
    }

    Ok(cb.Definition(cmd, encode, decode))
  })(cont)
}
