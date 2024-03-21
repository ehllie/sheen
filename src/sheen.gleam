import glam/doc.{type Document}
import gleam/dict
import gleam/dynamic
import gleam/int.{max}
import gleam/io
import gleam/iterator
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam/string_builder as sb
import sheen/internal/command_builder as cb
import sheen/internal/endec
import sheen/internal/error.{type ParseError}
import sheen/internal/extractor

pub type ParserSpec {
  ParserSpec(
    cmd: cb.CommandSpec,
    name: option.Option(String),
    authors: List(String),
    version: option.Option(String),
    help: Bool,
  )
}

pub type Parser(a) {
  Parser(
    spec: ParserSpec,
    encoders: endec.Encoders,
    decoder: endec.Decoder(a),
    extractor: extractor.ExtractorSpec,
  )
}

pub fn new() -> ParserSpec {
  ParserSpec(
    name: None,
    authors: list.new(),
    cmd: cb.new_spec(),
    version: None,
    help: True,
  )
}

pub fn name(to parser: ParserSpec, set name: String) {
  ParserSpec(..parser, name: Some(name))
}

pub fn authors(to parser: ParserSpec, set authors: List(String)) {
  ParserSpec(..parser, authors: authors)
}

pub fn version(to parser: ParserSpec, set version: String) {
  ParserSpec(..parser, version: Some(version))
}

pub fn no_help(to parser: ParserSpec) {
  ParserSpec(..parser, help: False)
}

fn add_help(spec: cb.CommandSpec) -> error.BuildResult(cb.CommandSpec) {
  let cb.CommandSpec(flags: flags, subcommands: subcommands, ..) = spec
  use <- error.rule_conflict(
    dict.has_key(flags, "help"),
    "Help flag is defined automatically. Either disable help or don't define a help flag.",
  )
  let help_spec =
    cb.FlagSpec(
      short: Some("h"),
      long: Some("help"),
      display: None,
      count: False,
      help: "Show help message and exit.",
    )
  let flags = dict.insert(flags, "help", help_spec)
  use subcommands <- result.try(
    dict.to_list(subcommands)
    |> list.map(fn(el) {
      let #(name, subcommand) = el
      let wrapper = case subcommand {
        cb.Optional(_) -> cb.Optional
        cb.Required(_) -> cb.Required
      }
      add_help(subcommand.spec)
      |> result.map(fn(new) { #(name, wrapper(new)) })
    })
    |> error.collect_results()
    |> result.map(dict.from_list),
  )
  Ok(cb.CommandSpec(..spec, flags: flags, subcommands: subcommands))
}

fn find_help(
  spec: cb.CommandSpec,
  input: endec.EncoderInput,
  path: List(String),
) -> Result(#(List(String), cb.CommandSpec), Nil) {
  case dict.get(input.flags, "help") {
    Ok(_) -> Ok(#(list.reverse(path), spec))
    Error(_) ->
      dict.to_list(input.subcommands)
      |> list.map(fn(el) {
        let #(name, subcommand_input) = el
        use spec <- result.try(dict.get(spec.subcommands, name))
        find_help(spec.spec, subcommand_input, [name, ..path])
      })
      |> list.reduce(result.or)
      |> result.flatten()
  }
}

pub fn try_build(
  from parser: ParserSpec,
  with command: cb.Command(a),
) -> error.BuildResult(Parser(a)) {
  let ParserSpec(cmd: cmd, help: help, ..) = parser
  let builder = cb.Builder(spec: cmd, encoders: [], decoder: valid(Nil))
  let cb.Command(cmd) = command
  use cb.Builder(command_spec, encoders, decoder) <- result.try(cmd(builder))
  use command_spec <- result.try(case help {
    True -> add_help(command_spec)
    False -> Ok(command_spec)
  })
  let spec = ParserSpec(..parser, cmd: command_spec)
  use extractor <- result.try(extractor.create_spec(spec.cmd))
  Ok(Parser(
    spec: spec,
    encoders: encoders,
    decoder: decoder,
    extractor: extractor,
  ))
}

pub fn build(from parser: ParserSpec, with command: cb.Command(a)) -> Parser(a) {
  case try_build(parser, command) {
    Ok(parser) -> parser
    Error(errors) -> {
      build_errors_to_doc(errors)
      |> doc.to_string(80)
      |> io.println_error()

      panic as "Failed to build parser"
    }
  }
}

pub fn build_errors_to_doc(errors: List(error.BuildError)) -> Document {
  let error_docs =
    list.map(errors, fn(error) {
      case error {
        error.RuleConflict(message) -> flexible_text(message)
        error.ReusedLong(long) -> doc.from_string("Reused long flag: " <> long)
        error.ReusedShort(short) ->
          doc.from_string("Reused short flag: " <> short)
      }
    })
  doc.join(error_docs, doc.line)
}

pub type Command(a) =
  cb.Command(a)

pub fn describe(description: String, cont: fn() -> Command(a)) -> Command(a) {
  cb.Command(fn(builder: cb.Builder(Nil)) {
    let spec = cb.CommandSpec(..builder.spec, description: Some(description))
    let cb.Command(cmd) = cont()
    cmd(cb.Builder(..builder, spec: spec))
  })
}

pub fn return(decoder: endec.Decoder(a)) -> Command(a) {
  cb.Command(fn(builder: cb.Builder(Nil)) {
    let cb.Builder(spec, encoders, ..) = builder
    let builder = cb.Builder(spec: spec, encoders: encoders, decoder: decoder)
    Ok(builder)
  })
}

pub fn valid(value: a) -> endec.Decoder(a) {
  endec.Decoder(fn(_) { Ok(value) })
}

pub type ParseResult(a) =
  Result(a, List(ParseError))

pub fn try_run(parser: Parser(a), args: List(String)) -> ParseResult(a) {
  let Parser(
    encoders: encoders,
    decoder: decoder,
    extractor: extractor,
    spec: spec,
  ) = parser

  let name = option.unwrap(spec.name, "<CMD>")
  let #(result, errors) =
    extractor.new(extractor)
    |> extractor.run(args)

  case find_help(spec.cmd, result, []) {
    Ok(#(path, cmd_spec)) -> {
      let name = string.join([name, ..path], " ")
      Error([
        error.Help(doc.join(
          [parser_header(spec), command_usage(cmd_spec, name)],
          doc.lines(2),
        )),
      ])
    }
    _ -> {
      use <- error.emit_errors(errors)
      endec.validate_and_run(result, encoders, decoder)
    }
  }
}

pub fn run(parser: Parser(a), args: List(String)) -> a {
  case try_run(parser, args) {
    Ok(value) -> value
    Error(errors) -> {
      parse_errors_to_doc(errors)
      |> doc.to_string(80)
      |> io.println_error()
      panic as "Failed to parse arguments"
    }
  }
}

pub fn parse_errors_to_doc(errors: List(error.ParseError)) -> Document {
  list.map(errors, fn(error) {
    case error {
      error.DecodeError(de) -> {
        let dynamic.DecodeError(expected: expected, found: found, ..) = de

        let expected =
          [doc.from_string("- Expected:"), doc.space, flexible_text(expected)]
          |> doc.concat()

        let found =
          [doc.from_string("- Found:"), doc.space, flexible_text(found)]
          |> doc.concat()

        [doc.from_string("Decode error:"), expected, found]
        |> doc.join(doc.soft_break)
        |> doc.nest(2)
        |> doc.force_break()
      }
      error.ValidationError(ve) ->
        [doc.from_string("Validation error:"), flexible_text(ve)]
        |> doc.join(doc.space)
        |> doc.nest(2)
      error.InternalError(ie) ->
        [doc.from_string("Internal error:"), flexible_text(ie)]
        |> doc.join(doc.space)
        |> doc.nest(2)
      error.ExtractionError(error.UnexpectedArgument(arg)) ->
        [doc.from_string("Unexpected argument:"), doc.from_string(arg)]
        |> doc.join(doc.space)
        |> doc.nest(2)
      error.ExtractionError(error.UnrecognisedLong(long)) ->
        [doc.from_string("Unrecognised long flag:"), doc.from_string(long)]
        |> doc.join(doc.space)
        |> doc.nest(2)
      error.ExtractionError(error.UnrecognisedShort(short)) ->
        [doc.from_string("Unrecognised short flag:"), doc.from_string(short)]
        |> doc.join(doc.space)
        |> doc.nest(2)
      error.ExtractionError(error.NoArgument(named)) ->
        [doc.from_string("No argument for flag:"), doc.from_string(named)]
        |> doc.join(doc.space)
        |> doc.nest(2)
      error.ExtractionError(error.NotAFlag(flag)) ->
        [doc.from_string("Not a flag:"), doc.from_string(flag)]
        |> doc.join(doc.space)
        |> doc.nest(2)
      error.Help(doc: doc) -> doc
    }
  })
  |> doc.join(doc.line)
}

fn zip_longest(
  xs: List(a),
  ys: List(b),
  x_fallback: a,
  y_fallback: b,
) -> iterator.Iterator(#(a, b)) {
  let #(next, xs, ys) = case xs, ys {
    [x, ..xs], [y, ..ys] -> #(Some(#(x, y)), xs, ys)
    [x, ..xs], [] -> #(Some(#(x, y_fallback)), xs, [])
    [], [y, ..ys] -> #(Some(#(x_fallback, y)), [], ys)
    [], [] -> #(None, [], [])
  }
  case next {
    Some(next) -> {
      use <- iterator.yield(next)
      zip_longest(xs, ys, x_fallback, y_fallback)
    }
    None -> iterator.empty()
  }
}

/// Converts a list of rows containing sections,
/// into a list of rows with each section vertically aligned.
///
fn column_align(rows: List(List(String)), sep: String) {
  // Collect cells into columns, and calculate the width of each column.
  let columns =
    list.index_fold(rows, [], fn(cols, row, idx) {
      zip_longest(cols, row, #(list.repeat("", idx), 0), "")
      |> iterator.map(fn(elem) {
        let #(#(col, width), cell) = elem
        #([cell, ..col], max(width, string.length(cell)))
      })
      |> iterator.to_list()
    })
    // Remove empty columns
    |> list.filter(fn(col) { col.1 > 0 })

  // Collect the collumns back into rows, padding each cell to the width of its column.
  let aligned_rows =
    list.fold(
      columns,
      list.repeat(sb.new(), list.length(rows)),
      fn(row_builders, col) {
        let #(col, width) = col
        let col = list.map(col, string.pad_right(_, width, " "))

        list.map2(row_builders, col, fn(builder, cell) {
          case sb.is_empty(builder) {
            True -> builder
            False -> sb.append(builder, sep)
          }
          |> sb.append(cell)
        })
      },
    )
    |> list.map(sb.to_string)

  aligned_rows
  |> list.reverse()
}

fn flexible_text(text: String) -> Document {
  let to_flexible_line = fn(line) {
    string.split(line, on: " ")
    |> list.map(doc.from_string)
    |> doc.join(with: doc.flex_space)
    |> doc.group
  }

  string.split(text, on: "\n")
  |> list.map(to_flexible_line)
  |> doc.join(with: doc.line)
  |> doc.group
}

type UsageRow {
  UsageRow(fixed: String, desc: String)
}

type UsageSection {
  UsageSection(header: String, rows: List(UsageRow))
}

fn row_to_doc(row: UsageRow, sep: String) -> Document {
  let UsageRow(fixed, desc) = row
  let prefix_len = string.length(fixed) + string.length(sep)
  let fixed = doc.from_string(fixed)
  let sep = doc.from_string(sep)

  let text =
    flexible_text(desc)
    |> doc.nest(prefix_len)

  doc.concat([fixed, sep, text])
  |> doc.group
}

fn new_section(
  rows: List(List(String)),
  descriptions: List(String),
  header: String,
) {
  let rows =
    column_align(rows, "  ")
    |> list.map2(descriptions, fn(row, desc) {
      UsageRow(fixed: row, desc: desc)
    })
  UsageSection(header: header, rows: rows)
}

fn section_to_doc(section: UsageSection) -> Document {
  let UsageSection(header, rows) = section
  let header = doc.from_string(header)
  let rows =
    list.map(rows, row_to_doc(_, "  "))
    |> doc.join(doc.line)
    |> doc.group
  doc.concat([header, doc.soft_break, rows])
  |> doc.nest(2)
  |> doc.force_break()
}

fn subcommand_doc(subcommands: dict.Dict(String, cb.Subcommand)) {
  case dict.new() == subcommands {
    True -> None
    False -> {
      let #(cells, descriptions) =
        subcommands
        |> dict.to_list
        |> list.map(fn(elem) {
          let #(name, subcommand) = elem
          #(
            [name],
            subcommand.spec.description
              |> option.unwrap(""),
          )
        })
        |> list.unzip()
      new_section(cells, descriptions, "Subcommands:")
      |> section_to_doc()
      |> Some
    }
  }
}

fn option_doc(
  flags: dict.Dict(String, cb.FlagSpec),
  named: dict.Dict(String, cb.NamedSpec),
) {
  let flags =
    flags
    |> dict.values
    |> list.map(fn(elem) {
      let cb.FlagSpec(help: help, short: short, long: long, ..) = elem
      let short =
        option.map(short, fn(s) { "-" <> s })
        |> option.unwrap("")
      let long =
        option.map(long, fn(l) { "--" <> l })
        |> option.unwrap("")
      #([short, long], help)
    })
  let named =
    named
    |> dict.to_list
    |> list.map(fn(elem) {
      let #(
        name,
        cb.NamedSpec(
          help: help,
          display: display,
          long: long,
          short: short,
          optional: optional,
          repeated: repeated,
        ),
      ) = elem

      let short =
        option.map(short, fn(s) { "-" <> s })
        |> option.unwrap("")

      let long =
        option.map(long, fn(l) { "--" <> l })
        |> option.unwrap("")

      let display = option.unwrap(display, name)
      let display = case optional, repeated {
        True, _ -> string.concat(["[", display, "]"])
        _, True -> string.concat(["[..", display, "]"])
        _, _ -> string.concat(["<", display, ">"])
      }

      #([short, long, display], help)
    })

  let #(cells, descriptions) =
    list.append(flags, named)
    |> list.unzip()

  case cells {
    [] -> None
    _ -> {
      new_section(cells, descriptions, "Options:")
      |> section_to_doc()
      |> Some
    }
  }
}

fn argument_doc(args: List(cb.ArgSpec)) {
  let #(cells, descriptions) =
    list.index_map(args, fn(arg, idx) {
      let display = option.unwrap(arg.display, "arg_" <> int.to_string(idx))
      case arg.help {
        "" -> None
        _ -> Some(#([display], arg.help))
      }
    })
    |> option.values()
    |> list.unzip()
  case cells {
    [] -> None
    _ -> {
      new_section(cells, descriptions, "Arguments:")
      |> section_to_doc()
      |> Some
    }
  }
}

fn command_usage(spec: cb.CommandSpec, name: String) -> Document {
  let cb.CommandSpec(
    description: description,
    args: args,
    flags: flags,
    named: named,
    subcommands: subcommands,
  ) = spec

  let argument_doc = argument_doc(args)
  let option_doc = option_doc(flags, named)
  let subcommand_doc = subcommand_doc(subcommands)

  let usage_doc = {
    let name = doc.from_string(name)
    let options = case option_doc {
      Some(_) -> Some(doc.from_string("[options]"))
      _ -> None
    }
    let arguments =
      list.index_map(spec.args, fn(arg, idx) {
        let name = option.unwrap(arg.display, "arg_" <> int.to_string(idx))
        case arg.optional, arg.repeated {
          True, _ -> string.concat(["[", name, "]"])
          _, True -> string.concat(["[..", name, "]"])
          _, _ -> string.concat(["<", name, ">"])
        }
      })
      |> list.map(doc.from_string)
    let subcommands = case dict.values(spec.subcommands) {
      [cb.Required(_), ..] -> Some(doc.from_string("<subcommand>"))
      [cb.Optional(_), ..] -> Some(doc.from_string("[subcommand]"))
      [] -> None
    }
    let inputs =
      list.concat([arguments, option.values([options, subcommands])])
      |> doc.join(doc.space)
      |> doc.group()

    let usage =
      doc.join([name, inputs], doc.space)
      |> doc.nest(2)
      |> doc.group()

    doc.concat([doc.from_string("Usage:"), doc.soft_break, usage])
    |> doc.nest(2)
    |> doc.force_break()
  }

  let description =
    description
    |> option.map(flexible_text)

  let sections =
    list.concat([
      option.values([description]),
      [usage_doc],
      option.values([argument_doc, option_doc, subcommand_doc]),
    ])

  doc.join(sections, doc.lines(2))
}

fn parser_header(spec: ParserSpec) -> Document {
  let ParserSpec(authors: authors, version: version, name: name, ..) = spec

  let info = {
    use name <- option.then(name)
    case version {
      Some(version) -> name <> " " <> version
      None -> name
    }
    |> doc.from_string()
    |> Some
  }
  let authors = case authors {
    [] -> None
    _ -> {
      let author_list =
        list.map(authors, doc.from_string)
        |> doc.join(doc.break(", ", ""))
        |> doc.group()
      doc.concat([doc.from_string("Authors:"), doc.space, author_list])
      |> doc.nest(2)
      |> Some
    }
  }

  list.concat([option.values([info, authors])])
  |> doc.join(doc.line)
}

pub fn usage(spec: ParserSpec) -> Document {
  let header = parser_header(spec)
  let usage = command_usage(spec.cmd, option.unwrap(spec.name, "<CMD>"))
  doc.join([header, usage], doc.lines(2))
}
