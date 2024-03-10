import gleam/dict
import gleam/list
import gleam/option
import gleeunit
import gleeunit/should
import sheen
import sheen/flag
import sheen/arg
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
    |> sheen.build({
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

  sheen.run(parser, ["-vv", "--help"])
  |> should.be_ok

  sheen.run(parser, ["--unknown-flag"])
  |> should.be_error

  sheen.run(parser, ["too", "many"])
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

pub fn structured_parse_test() {
  let parser =
    sheen.new()
    |> sheen.build({
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
    })

  let parser = should.be_ok(parser)

  sheen.run(parser, ["-vv", "file", "42", "8", "--multi", "4"])
  |> should.be_ok
  |> should.equal(StructuredInput(2, "file", [42, 8], 4))

  sheen.run(parser, ["file", "42", "not-a-number", "--multi", "not-a-number"])
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
    |> sheen.build({
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
  sheen.run(parser, ["A"])
  |> should.be_ok
  |> should.equal(A)

  sheen.run(parser, ["D"])
  |> should.be_error
}

pub fn subcommand_test() {
  let parser =
    sheen.new()
    |> sheen.build({
      use mc <- subcommand.optional("my-command", my_command())
      sheen.return({
        use mc <- mc
        sheen.valid(mc)
      })
    })
  let parser = should.be_ok(parser)

  sheen.run(parser, ["my-command", "A"])
  |> should.be_ok
  |> should.equal(option.Some(A))
}
