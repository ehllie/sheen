import gleam/dict
import gleam/result
import gleam/bool
import gleam/function
import gleam/list
import gleam/int
import gleam/dynamic
import sheen/error.{type ParseError, type ParseResult}

pub type EncoderInput {
  EncoderInput(
    flags: dict.Dict(String, Int),
    named: dict.Dict(String, List(String)),
    args: List(String),
    subcommands: dict.Dict(String, EncoderInput),
  )
}

pub type Encoder =
  fn(EncoderInput) -> ParseResult(dynamic.Dynamic)

pub type Encoders =
  List(Encoder)

pub type Decoder(a) {
  Decoder(fn(List(dynamic.Dynamic)) -> Result(a, List(ParseError)))
}

pub type DecodeBuilder(a, b) =
  fn(fn(a) -> Decoder(b)) -> Decoder(b)

pub fn new_input() {
  EncoderInput(
    args: list.new(),
    flags: dict.new(),
    named: dict.new(),
    subcommands: dict.new(),
  )
}

pub fn insert_encoder(
  encoders: Encoders,
  encoder: Encoder,
  decoder: dynamic.Decoder(a),
) {
  let position = list.length(encoders)
  let path = ["values", "[" <> int.to_string(position) <> "]"]

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
  input: EncoderInput,
  encoders: Encoders,
  decoder: Decoder(a),
) -> Result(a, List(ParseError)) {
  let #(values, errors) =
    encoders
    |> list.map(function.apply1(_, input))
    |> result.partition

  use <- bool.guard([] != errors, Error(errors))

  let Decoder(decoder) = decoder

  decoder(values)
}

pub fn valid(val: a) -> Decoder(a) {
  Decoder(fn(_) { Ok(val) })
}
