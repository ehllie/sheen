import birdie
import glam/doc
import gleam/dict
import gleam/list
import gleam/option
import gleeunit
import gleeunit/should
import sheen
import sheen/arg
import sheen/flag
import sheen/named
import sheen/subcommand

pub fn main() {
  gleeunit.main()
}

pub fn parser_build_test() {
  let parser =
    sheen.new()
    |> sheen.name("Test command")
    |> sheen.version("0.1.0")
    |> sheen.authors(["Ellie"])
    |> sheen.try_build({
      use verbosity <-
        flag.new("verbose")
        |> flag.count()
      use help <-
        flag.new("help")
        |> flag.boolean()
      sheen.return({
        use verbosity <- verbosity
        use help <- help
        sheen.valid(#(verbosity, help))
      })
    })
  let parser = should.be_ok(parser)
  parser.spec.cmd.flags
  |> dict.size
  |> should.equal(2)

  sheen.try_run(parser, ["-vv", "--help"])
  |> should.be_ok

  sheen.try_run(parser, ["--unknown-flag"])
  |> should.be_error

  sheen.try_run(parser, ["too", "many"])
  |> should.be_error
}

pub type Verbosity {
  Debug
  Info
  Warn
  Err
}

pub type StructuredInput {
  StructuredInput(verbosity: Int, file: String, nums: List(Int), multi: Int)
}

fn structured_cmd() -> sheen.Command(StructuredInput) {
  use verbosity <-
    flag.new("verbose")
    |> flag.count()

  use file <-
    arg.new()
    |> arg.required()

  use nums <-
    arg.new()
    |> arg.integer()
    |> arg.repeated()

  use multi <-
    named.new("multi")
    |> named.integer()
    |> named.optional()

  sheen.return({
    use verbosity <- verbosity
    use file <- file
    use nums <- nums
    use multi <- multi
    sheen.valid(StructuredInput(
      verbosity: verbosity,
      file: file,
      nums: nums,
      multi: option.unwrap(multi, 0),
    ))
  })
}

pub fn structured_parse_test() {
  let parser =
    sheen.new()
    |> sheen.try_build({ structured_cmd() })

  let parser = should.be_ok(parser)

  sheen.try_run(parser, ["-vv", "file", "42", "8", "--multi", "4"])
  |> should.be_ok
  |> should.equal(StructuredInput(2, "file", [42, 8], 4))

  sheen.try_run(parser, [
    "file", "42", "not-a-number", "--multi", "not-a-number",
  ])
  |> should.be_error
  |> list.length
  |> should.equal(2)
}

pub type MyEnum {
  A
  B
  C
}

pub fn my_command() -> sheen.Command(MyEnum) {
  use <- sheen.describe("This command parses an enum")

  use enum <-
    arg.new()
    |> arg.enum([#("A", A), #("B", B), #("C", C)])
    |> arg.required

  sheen.return({
    use enum <- enum
    sheen.valid(enum)
  })
}

pub fn enum_parse_test() {
  let parser =
    sheen.new()
    |> sheen.try_build({
      use enum <-
        arg.new()
        |> arg.enum([#("A", A), #("B", B), #("C", C)])
        |> arg.required

      sheen.return({
        use enum <- enum
        sheen.valid(enum)
      })
    })

  let parser = should.be_ok(parser)
  sheen.try_run(parser, ["A"])
  |> should.be_ok
  |> should.equal(A)

  sheen.try_run(parser, ["D"])
  |> should.be_error
}

pub fn subcommand_test() {
  let parser =
    sheen.new()
    |> sheen.try_build({
      use mc <- subcommand.optional("my-command", my_command())
      sheen.return({
        use mc <- mc
        sheen.valid(mc)
      })
    })
  let parser = should.be_ok(parser)

  sheen.try_run(parser, ["my-command", "A"])
  |> should.be_ok
  |> should.equal(option.Some(A))
}

pub type Variant {
  StringVariant(String)
  NumberVariant(Int)
}

fn variant_string_cmd() -> sheen.Command(Variant) {
  use string <-
    arg.new()
    |> arg.required()
  sheen.return({
    use string <- string
    sheen.valid(StringVariant(string))
  })
}

fn variant_number_cmd() -> sheen.Command(Variant) {
  use number <-
    arg.new()
    |> arg.integer()
    |> arg.required()
  sheen.return({
    use number <- number
    sheen.valid(NumberVariant(number))
  })
}

pub fn required_subcommand_test() {
  let parser =
    sheen.new()
    |> sheen.try_build({
      use variant <- subcommand.required([
        #("string", variant_string_cmd()),
        #("number", variant_number_cmd()),
      ])
      sheen.return({
        use variant <- variant
        sheen.valid(variant)
      })
    })

  let parser = should.be_ok(parser)

  sheen.try_run(parser, ["string", "hello"])
  |> should.be_ok

  sheen.try_run(parser, ["number", "42"])
  |> should.be_ok

  sheen.try_run(parser, ["unknown", "42"])
  |> should.be_error
}

pub fn basic_usage_test() {
  let parser =
    sheen.new()
    |> sheen.name("my_cli_app")
    |> sheen.version("0.1.0")
    |> sheen.authors(["Lucy", "Ellie"])
    |> sheen.try_build({
      use <- sheen.describe(
        "This command has positional and named arguments, flags and subcommands.",
      )
      use _ <-
        flag.new("verbose")
        |> flag.help("Increase verbosity")
        |> flag.count()
      use _ <-
        named.new("num")
        |> named.integer()
        |> named.help("A number")
        |> named.optional()
      use _ <-
        arg.new()
        |> arg.help(
          "A file. This has a long description. The words should wrap to new line, but stay aligned to the help column",
        )
        |> arg.display("FILE")
        |> arg.required()
      use _ <- subcommand.optional("my-command", my_command())
      sheen.return(sheen.valid(Nil))
    })

  let parser = should.be_ok(parser)

  let usage =
    sheen.usage(parser.spec)
    |> doc.to_string(80)

  birdie.snap(usage, "basic_usage_test")
}
