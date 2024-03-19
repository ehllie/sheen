import gleam/bool.{guard}
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result.{unwrap}
import gleam/string
import sheen/internal/command_builder as cb
import sheen/internal/endec
import sheen/internal/error.{type ExtractionError, type ParseError}

pub type OptionKind {
  /// This is a flag, and will not consume the next argument.
  Flag(name: String)
  /// This is a named option, and will consume the next argument.
  Named(name: String)
}

pub type ExtractorSpec {
  /// This provides the context necessary to create EncoderInput.
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
    subcommand_path: List(String),
    errors: List(ParseError),
  )
}

fn maybe_insert_unique(
  opt: Option(String),
  acc: dict.Dict(String, a),
  val: a,
  errors: List(error.BuildError),
  err_kind: fn(String) -> error.BuildError,
) {
  case opt {
    Some(name) ->
      case dict.has_key(acc, name) {
        True -> {
          let error = err_kind(name)
          #(acc, [error, ..errors])
        }
        False -> {
          let acc = dict.insert(acc, name, val)
          #(acc, errors)
        }
      }
    None -> #(acc, errors)
  }
}

pub fn create_spec(cmd: cb.CommandSpec) -> error.BuildResult(ExtractorSpec) {
  let short = dict.new()
  let long = dict.new()
  let errors = []

  let #(short, long, errors) =
    dict.fold(
      over: cmd.flags,
      from: #(short, long, errors),
      with: fn(acc, flag_name, spec) {
        let #(short, long, errors) = acc

        let #(short, errors) =
          maybe_insert_unique(
            spec.short,
            short,
            Flag(flag_name),
            errors,
            error.ReusedShort,
          )

        let #(long, errors) =
          maybe_insert_unique(
            spec.long,
            long,
            Flag(flag_name),
            errors,
            error.ReusedLong,
          )

        #(short, long, errors)
      },
    )

  let #(short, long, errors) =
    dict.fold(
      over: cmd.named,
      from: #(short, long, errors),
      with: fn(acc, arg_name, spec) {
        let #(short, long, errors) = acc

        let #(short, errors) =
          maybe_insert_unique(
            spec.short,
            short,
            Named(arg_name),
            errors,
            error.ReusedShort,
          )

        let #(long, errors) =
          maybe_insert_unique(
            spec.long,
            long,
            Named(arg_name),
            errors,
            error.ReusedLong,
          )

        #(short, long, errors)
      },
    )

  use <- error.emit_errors(errors)

  use subcommands <- result.try(
    dict.to_list(cmd.subcommands)
    |> list.map(fn(subc) {
      let #(name, subcommand) = subc
      use spec <- result.try(create_spec(subcommand.spec))
      Ok(#(name, spec))
    })
    |> error.collect_results(),
  )

  let subcommands = dict.from_list(subcommands)

  let max_args = {
    use <- bool.guard(dict.new() == subcommands, Some(0))
    Some(1)
  }

  let max_args =
    list.fold(cmd.args, max_args, fn(max, arg) {
      case max {
        Some(max) -> {
          use <- guard(arg.repeated, None)
          Some(max + 1)
        }
        _ -> None
      }
    })

  Ok(ExtractorSpec(
    short: short,
    long: long,
    subcommands: subcommands,
    max_args: max_args,
  ))
}

pub fn new(cmd: cb.CommandSpec) -> Extractor {
  let assert Ok(spec) = create_spec(cmd)
  Extractor(
    spec: spec,
    opts_ignored: False,
    result: endec.new_input(),
    subcommand_path: list.new(),
    errors: list.new(),
  )
}

fn add_arg(extractor: Extractor, arg: String) -> Extractor {
  let Extractor(spec: spec, ..) = extractor
  let spec =
    ExtractorSpec(
      ..spec,
      max_args: option.map(spec.max_args, fn(old) { old - 1 }),
    )
  let extractor = Extractor(..extractor, spec: spec)
  use result <- update_result(extractor)
  endec.EncoderInput(..result, args: [arg, ..result.args])
}

fn reverse_args(extractor: Extractor) -> Extractor {
  let Extractor(result: result, ..) = extractor
  let result = endec.EncoderInput(..result, args: list.reverse(result.args))
  Extractor(..extractor, result: result)
}

fn add_flag(extractor: Extractor, name: String) -> Extractor {
  use result <- update_result(extractor)
  let endec.EncoderInput(flags: flags, ..) = result
  endec.EncoderInput(
    ..result,
    flags: dict.update(flags, name, fn(old) {
      option.map(old, fn(old) { old + 1 })
      |> option.unwrap(1)
    }),
  )
}

fn add_named(extractor: Extractor, name: String, value: String) -> Extractor {
  use result <- update_result(extractor)
  let endec.EncoderInput(named: named, ..) = result
  endec.EncoderInput(
    ..result,
    named: dict.update(named, name, fn(old) {
      option.map(old, fn(old) { [value, ..old] })
      |> option.unwrap([value])
    }),
  )
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

fn descend_subcommand(extractor: Extractor, subcommand: String) -> Extractor {
  let Extractor(subcommand_path: path, ..) = extractor
  Extractor(..extractor, subcommand_path: [subcommand, ..path])
}

fn update_result(
  extractor: Extractor,
  update: fn(endec.EncoderInput) -> endec.EncoderInput,
) -> Extractor {
  let Extractor(result: result, subcommand_path: path, ..) = extractor

  let #(result, results) =
    list.fold_right(path, #(result, []), fn(acc, subcommand) {
      let #(result, results) = acc
      let subcommand_result =
        dict.get(result.subcommands, subcommand)
        |> unwrap(endec.new_input())
      #(subcommand_result, [subcommand_result, ..results])
    })

  let updated_result =
    results
    |> list.zip(path)
    |> list.fold(update(result), fn(result, parent) {
      let #(parent_result, subcommand) = parent
      let subcommands =
        parent_result.subcommands
        |> dict.insert(subcommand, result)
      endec.EncoderInput(..parent_result, subcommands: subcommands)
    })

  Extractor(..extractor, result: updated_result)
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
          |> descend_subcommand(arg)
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
