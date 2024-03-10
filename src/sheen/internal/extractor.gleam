import gleam/dict
import gleam/option.{type Option, None, Some}
import gleam/list
import gleam/string
import gleam/bool.{guard}
import sheen/internal/command_builder as cb
import sheen/internal/endec
import sheen/error.{type ExtractionError, type ParseError}

pub type OptionKind {
  /// This is a flag, and will not consume the next argument.
  Flag(String)
  /// This is a named option, and will consume the next argument.
  Named(String)
}

pub type ExtractorSpec {
  /// This provides the context necessary to create ValidatorInput.
  /// We need to know how to interpret short and long flags,
  /// ie. whether they are flags or named options, since the
  /// former will not consume the next argument, and the latter
  /// will.
  /// We also need to know how to interpret subcommands, since
  /// they can have their own flags and named options.
  ExtractorSpec(
    short: dict.Dict(String, OptionKind),
    long: dict.Dict(String, OptionKind),
    max_args: Option(Int),
    subcommands: dict.Dict(String, ExtractorSpec),
  )
}

pub type Extractor {
  Extractor(
    spec: ExtractorSpec,
    opts_ignored: Bool,
    result: endec.EncoderInput,
    errors: List(ParseError),
  )
}

fn create_spec(cmd: cb.CommandSpec) {
  let short = dict.new()
  let long = dict.new()

  let #(short, long) =
    dict.fold(
      over: cmd.flags,
      from: #(short, long),
      with: fn(acc, flag_name, spec) {
        let #(short, long) = acc

        let short = case spec.short {
          Some(name) -> dict.insert(short, name, Flag(flag_name))
          None -> short
        }

        let long = case spec.long {
          Some(name) -> dict.insert(long, name, Flag(flag_name))
          None -> long
        }

        #(short, long)
      },
    )

  let #(short, long) =
    dict.fold(
      over: cmd.named,
      from: #(short, long),
      with: fn(acc, arg_name, spec) {
        let #(short, long) = acc

        let short = case spec.short {
          Some(name) -> dict.insert(short, name, Named(arg_name))
          None -> short
        }

        let long = case spec.long {
          Some(name) -> dict.insert(long, name, Named(arg_name))
          None -> long
        }

        #(short, long)
      },
    )

  let subcommands =
    dict.map_values(cmd.subcommands, fn(_, subcommand) {
      create_spec(subcommand.spec)
    })

  let max_args =
    list.fold(cmd.args, Some(0), fn(max, arg) {
      case max {
        Some(max) -> {
          use <- guard(arg.repeated, None)
          Some(max + 1)
        }
        _ -> None
      }
    })

  ExtractorSpec(
    short: short,
    long: long,
    subcommands: subcommands,
    max_args: max_args,
  )
}

pub fn new(cmd: cb.CommandSpec) -> Extractor {
  let spec = create_spec(cmd)
  Extractor(
    spec: spec,
    opts_ignored: False,
    result: endec.ValidatorInput(
      args: list.new(),
      flags: dict.new(),
      named: dict.new(),
      subcommands: dict.new(),
    ),
    errors: list.new(),
  )
}

fn add_arg(extractor: Extractor, arg: String) -> Extractor {
  let Extractor(result: result, spec: spec, ..) = extractor
  let result = endec.ValidatorInput(..result, args: [arg, ..result.args])
  let spec =
    ExtractorSpec(
      ..spec,
      max_args: option.map(spec.max_args, fn(old) { old - 1 }),
    )
  Extractor(..extractor, result: result, spec: spec)
}

fn reverse_args(extractor: Extractor) -> Extractor {
  let Extractor(result: result, ..) = extractor
  let result = endec.ValidatorInput(..result, args: list.reverse(result.args))
  Extractor(..extractor, result: result)
}

fn add_flag(extractor: Extractor, name: String) -> Extractor {
  let Extractor(result: result, ..) = extractor
  let endec.ValidatorInput(flags: flags, ..) = result
  let result =
    endec.ValidatorInput(
      ..result,
      flags: dict.update(flags, name, fn(old) {
        option.map(old, fn(old) { old + 1 })
        |> option.unwrap(1)
      }),
    )
  Extractor(..extractor, result: result)
}

fn add_named(extractor: Extractor, name: String, value: String) -> Extractor {
  let Extractor(result: result, ..) = extractor
  let endec.ValidatorInput(named: named, ..) = result
  let result =
    endec.ValidatorInput(
      ..result,
      named: dict.update(named, name, fn(old) {
        option.map(old, fn(old) { [value, ..old] })
        |> option.unwrap([value])
      }),
    )
  Extractor(..extractor, result: result)
}

fn with_spec(extractor: Extractor, spec: ExtractorSpec) -> Extractor {
  Extractor(..extractor, spec: spec)
}

fn error(extractor: Extractor, error: ExtractionError) -> Extractor {
  let Extractor(errors: errors, ..) = extractor
  Extractor(..extractor, errors: [error.ExtractionError(error), ..errors])
}

fn ignore_opts(extractor: Extractor) -> Extractor {
  Extractor(..extractor, opts_ignored: True)
}

pub fn run(
  extractor: Extractor,
  args: List(String),
) -> #(endec.EncoderInput, List(ParseError)) {
  let Extractor(spec: spec, opts_ignored: opts_ignored, errors: errors, ..) =
    extractor

  let takes_args =
    option.map(spec.max_args, fn(max) { max > 0 })
    |> option.unwrap(True)

  case args {
    [] -> #(reverse_args(extractor).result, errors)
    ["--", ..rest] if !opts_ignored ->
      ignore_opts(extractor)
      |> run(rest)
    ["--" <> long, ..rest] if !opts_ignored -> {
      case string.split_once(long, "=") {
        Ok(#(long, val)) ->
          case dict.get(spec.long, long) {
            Ok(Named(named)) ->
              add_named(extractor, named, val)
              |> run(rest)
            Ok(_) ->
              error(extractor, error.NotAFlag(long))
              |> run(rest)
            _ ->
              error(extractor, error.UnrecognisedLong(long))
              |> run(rest)
          }
        _ ->
          case dict.get(spec.long, long), rest {
            Ok(Named(named)), [val, ..rest] ->
              add_named(extractor, named, val)
              |> run(rest)
            Ok(Named(named)), _ ->
              error(extractor, error.NoArgument(named))
              |> run(rest)
            Ok(Flag(named)), _ ->
              add_flag(extractor, named)
              |> run(rest)
            _, _ ->
              error(extractor, error.UnrecognisedLong(long))
              |> run(rest)
          }
      }
    }

    ["-" <> short, ..rest] if !opts_ignored -> {
      case string.to_graphemes(short) {
        [short] ->
          case dict.get(spec.short, short) {
            Ok(Flag(named)) ->
              add_flag(extractor, named)
              |> run(rest)
            Ok(Named(named)) -> {
              case rest {
                [] ->
                  error(extractor, error.NoArgument(named))
                  |> run(rest)
                [val, ..rest] ->
                  add_named(extractor, named, val)
                  |> run(rest)
              }
            }
            _ ->
              error(extractor, error.UnrecognisedShort(short))
              |> run(rest)
          }

        [] ->
          error(extractor, error.UnrecognisedShort(short))
          |> run(rest)

        [flag, ..short] -> {
          let #(extractor, last) =
            list.fold(short, #(extractor, flag), fn(acc, flag) {
              let extractor = case dict.get(spec.short, acc.1) {
                Ok(Flag(named)) -> add_flag(acc.0, named)
                Ok(Named(named)) -> error(acc.0, error.NoArgument(named))
                _ -> error(acc.0, error.UnrecognisedShort(acc.1))
              }
              #(extractor, flag)
            })

          case dict.get(spec.short, last) {
            Ok(Flag(named)) ->
              add_flag(extractor, named)
              |> run(rest)

            Ok(Named(named)) ->
              case rest {
                [] ->
                  error(extractor, error.NoArgument(named))
                  |> run(rest)
                [val, ..rest] ->
                  add_named(extractor, named, val)
                  |> run(rest)
              }

            _ ->
              error(extractor, error.UnrecognisedShort(last))
              |> run(rest)
          }
        }
      }
    }

    [arg, ..rest] if takes_args -> {
      case dict.get(spec.subcommands, arg) {
        Ok(sub) ->
          with_spec(extractor, sub)
          |> run(rest)
        _ ->
          add_arg(extractor, arg)
          |> run(rest)
      }
    }

    [arg, ..rest] -> {
      error(extractor, error.UnexpectedArgument(arg))
      |> run(rest)
    }
  }
}
