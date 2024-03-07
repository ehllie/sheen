import gleam/result
import gleam/dict

pub type ValidatorInput {
  ValidatorInput(
    flags: dict.Dict(String, Int),
    named: dict.Dict(String, List(String)),
    args: List(String),
    subcommands: dict.Dict(String, ValidatorInput),
  )
}

pub type ValidationError =
  String

pub type ValidationResult(a) =
  Result(a, ValidationError)

pub type Validator(a) =
  fn(ValidatorInput) -> ValidationResult(a)

pub fn extract(
  validator: Validator(a),
  cont: fn(a) -> Validator(b),
) -> Validator(b) {
  fn(input) {
    use result <- result.try(validator(input))
    cont(result)(input)
  }
}
