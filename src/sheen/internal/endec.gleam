import gleam/bool
import gleam/dict
import gleam/dynamic
import gleam/function
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import sheen/internal/error.{type ParseError, type ParseResult}

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

pub type DecodeFn(a) =
  fn(dynamic.Dynamic) -> error.ParseResult(a)

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
  decoder: DecodeFn(a),
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
      use decoded <- result.try(decoder(value))
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
) -> ParseResult(a) {
  use values <- result.try(encode_all(input, encoders))
  let Decoder(decoder) = decoder
  decoder(values)
}

pub fn encode_all(
  input: EncoderInput,
  encoders: Encoders,
) -> ParseResult(List(dynamic.Dynamic)) {
  let #(values, errors) =
    encoders
    |> list.map(function.apply1(_, input))
    |> result.partition

  let errors = list.concat(errors)

  use <- bool.guard([] != errors, Error(errors))

  Ok(values)
}

pub fn valid(val: a) -> Decoder(a) {
  Decoder(fn(_) { Ok(val) })
}

pub fn decode_int(dyn: dynamic.Dynamic) {
  dynamic.int(dyn)
  |> result.map_error(error.from_decode_error)
}

pub fn decode_bool(dyn: dynamic.Dynamic) {
  dynamic.bool(dyn)
  |> result.map_error(error.from_decode_error)
}

pub fn enum(
  values: List(#(String, a)),
) -> #(fn(String) -> error.ParseResult(a), dynamic.Decoder(a)) {
  let word_map = dict.from_list(values)
  let dyn_map =
    dict.values(word_map)
    |> list.map(fn(val) { #(dynamic.from(val), val) })
    |> dict.from_list

  let parser = fn(value) {
    dict.get(word_map, value)
    |> result.replace_error([
      error.ValidationError(
        "Expected one of: " <> string.join(dict.keys(word_map), ", "),
      ),
    ])
  }

  let decoder = fn(dyn) {
    dict.get(dyn_map, dyn)
    |> result.replace_error([
      dynamic.DecodeError(
        expected: "One of: " <> string.join(dict.keys(word_map), ", "),
        found: string.inspect(dyn),
        path: [],
      ),
    ])
  }

  #(parser, decoder)
}

pub fn decode_list(decoder: dynamic.Decoder(a)) -> DecodeFn(List(a)) {
  fn(dyn) {
    dynamic.list(decoder)(dyn)
    |> result.map_error(error.from_decode_error)
  }
}

pub fn decode_optional(
  decoder: dynamic.Decoder(a),
) -> DecodeFn(option.Option(a)) {
  fn(dyn) {
    dynamic.optional(decoder)(dyn)
    |> result.map_error(error.from_decode_error)
  }
}

pub fn from_dynamic(decoder: dynamic.Decoder(a)) -> DecodeFn(a) {
  fn(dyn) {
    decoder(dyn)
    |> result.map_error(error.from_decode_error)
  }
}
