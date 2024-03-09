import gleam/dict
import gleam/option
import gleeunit
import gleeunit/should
import sheen.{extract}
import sheen/flag
import sheen/command
import sheen/arg
import sheen/named

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
      command.return({
        use verbosity <- extract(verbosity)
        use help <- extract(help)
        fn(_) { Ok(#(verbosity, help)) }
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

      command.return({
        use verbosity <- extract(verbosity)
        use file <- extract(file)
        use nums <- extract(nums)
        use multi <- extract(multi)
        fn(_) {
          Ok(StructuredInput(
            verbosity: verbosity,
            file: file,
            nums: nums,
            multi: option.unwrap(multi, 0),
          ))
        }
      })
    })

  let parser = should.be_ok(parser)

  sheen.run(parser, ["-vv", "file", "42", "8", "--multi", "4"])
  |> should.be_ok
  |> should.equal(StructuredInput(2, "file", [42, 8], 4))
}
