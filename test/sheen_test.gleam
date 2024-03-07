import gleam/dict
import gleeunit
import gleeunit/should
import sheen.{extract}
import sheen/flag
import sheen/command

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
        |> flag.count
        |> flag.build()
      use help <-
        flag.new("help")
        |> flag.build()
      command.return({
        use verbosity <- extract(verbosity)
        use help <- extract(help)
        fn(_) { Ok(#(verbosity, help)) }
      })
    })
    |> should.be_ok
  parser.spec.cmd.flags
  |> dict.size
  |> should.equal(2)
}
