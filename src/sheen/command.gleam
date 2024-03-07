import gleam/dict
import gleam/result
import gleam/option.{None, Some}
import gleam/list

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

pub type FlagSpec {
  FlagSpec(
    short: option.Option(String),
    long: option.Option(String),
    display: option.Option(String),
    count: Bool,
    help: String,
  )
}

pub type NamedSpec {
  NamedSpec(
    short: option.Option(String),
    long: option.Option(String),
    display: option.Option(String),
    repeated: Bool,
    optional: Bool,
    help: String,
  )
}

pub type ArgSpec {
  ArgSpec(
    display: option.Option(String),
    repeated: Bool,
    optional: Bool,
    help: String,
  )
}

pub type CommandSpec {
  CommandSpec(
    flags: dict.Dict(String, FlagSpec),
    named: dict.Dict(String, NamedSpec),
    args: List(ArgSpec),
    subcommands: dict.Dict(String, CommandSpec),
    description: option.Option(String),
  )
}

pub type BuildError =
  String

pub type BuildResult(a) =
  Result(Builder(a), BuildError)

pub type BuilderFn(a) =
  fn(CommandSpec) -> BuildResult(a)

pub type Continuation(a, b) =
  fn(Validator(a)) -> BuilderFn(b)

pub type Command(a, b) =
  fn(Continuation(a, b)) -> BuilderFn(b)

pub type Builder(a) {
  Builder(spec: CommandSpec, validator: Validator(a))
}

pub fn command(builder: BuilderFn(a)) -> Command(a, b) {
  fn(cont) {
    fn(input) {
      use Builder(spec, validator) <- result.try(builder(input))
      cont(validator)(spec)
    }
  }
}

pub fn new() -> CommandSpec {
  CommandSpec(
    flags: dict.new(),
    named: dict.new(),
    args: list.new(),
    subcommands: dict.new(),
    description: None,
  )
}

pub fn describe(description: String, cont: BuilderFn(a)) -> BuilderFn(a) {
  fn(spec) {
    CommandSpec(..spec, description: Some(description))
    |> cont
  }
}

pub fn return(validator: Validator(a)) -> BuilderFn(a) {
  fn(spec) { Ok(Builder(spec, validator)) }
}
// pub fn subcommand()
