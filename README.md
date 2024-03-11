# Sheen

[![Package Version](https://img.shields.io/hexpm/v/sheen)](https://hex.pm/packages/sheen)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/sheen/)

```sh
gleam add sheen
```

Sheen is a library for creating command line argument parsers. It has a convenient and type safe API.

```gleam
import argv
import sheen
import sheen/flag
import sheen/arg
import sheen/named

type Mode {
  Sum
  Product
}

type Args {
  Args(verbosity: Int, numbers: List(Int), mode: Mode)
}

fn parser() -> sheen.Parser(Args) {
  // You are asserting that you've built the parser correctly
  // Otherwise you will receive informative errors
  let assert Ok(parser) =
    sheen.new()
    |> sheen.name("Number cruncher")
    |> sheen.version("0.1.0")
    |> sheen.authors(["Ellie"])
    |> sheen.build({
      use verbosity <-
        flag.new("verbose")
        |> flag.count()

      use mode <-
        named.new("mode")
        |> named.enum([#("sum", Sum), #("product", Product)])
        |> named.required()

      use numbers <-
        arg.new()
        |> arg.integer()
        |> arg.repeated()

      sheen.return({
        use verbosity <- verbosity
        use numbers <- numbers
        use mode <- mode
        sheen.valid(Args(verbosity, numbers, mode))
      })
    })
  parser
}

pub fn main() {
  let parse_result =
    parser()
    |> sheen.run(argv.load().arguments)
  case parse_result {
    Ok(args) -> {
      // Run you program with the parsed arguments
      todo
    }
    Error(errors) -> {
      // Sheen collects all errors and returns them as a list
      // Later I will add a way to pretty print them, and then
      // show usage information
      todo
    }
  }
}
```

Further documentation can be found at <https://hexdocs.pm/sheen>.
