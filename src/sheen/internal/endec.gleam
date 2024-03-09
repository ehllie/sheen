import gleam/dict
import gleam/result
import gleam/bool
import gleam/function
import gleam/list
import gleam/int
import gleam/dynamic
import sheen/error.{type ParseError, type ParseResult}

pub type ValidatorInput {
  ValidatorInput(
    flags: dict.Dict(String, Int),
    named: dict.Dict(String, List(String)),
    args: List(String),
    subcommands: dict.Dict(String, ValidatorInput),
  )
}

pub type Validator(a) =
  fn(ValidatorInput) -> ParseResult(a)

pub type Encoders =
  List(fn(ValidatorInput) -> ParseResult(dynamic.Dynamic))

pub type Decoder(a) {
  Decoder(fn(List(dynamic.Dynamic)) -> Result(a, List(ParseError)))
}

pub type DecodeBuilder(a, b) =
  fn(fn(a) -> Decoder(b)) -> Decoder(b)

pub fn insert_validator(
  encoders: Encoders,
  validator: Validator(a),
  decoder: dynamic.Decoder(a),
) -> #(Encoders, DecodeBuilder(a, b)) {
  let position = list.length(encoders)
  let path = ["values", "[" <> int.to_string(position) <> "]"]
  let encoder = fn(input) {
    validator(input)
    |> result.map(dynamic.from)
  }

  let builder = fn(cont) {
    Decoder(fn(values) {
      use value <- result.try(
        list.at(values, position)
        |> result.replace_error([
          error.DecodeError(dynamic.DecodeError(
            expected: "Value inside encoded array",
            found: "Nil",
            path: path,
          )),
        ]),
      )
      use decoded <- result.try(
        decoder(value)
        |> result.map_error(list.map(_, fn(error) {
          error.DecodeError(dynamic.DecodeError(..error, path: path))
        })),
      )
      let Decoder(decoder) = cont(decoded)
      decoder(values)
    })
  }

  let encoders = [encoder, ..encoders]

  #(encoders, builder)
}

pub fn validate_and_run(
  input: ValidatorInput,
  encoders: Encoders,
  decoder: Decoder(a),
) -> Result(a, List(ParseError)) {
  let #(values, errors) =
    encoders
    |> list.map(function.apply1(_, input))
    |> result.partition

  use <- bool.guard([] != errors, Error(errors))

  let Decoder(decoder) = decoder

  values
  |> decoder
}

pub fn valid(val: a) -> Decoder(a) {
  Decoder(fn(_) { Ok(val) })
}
