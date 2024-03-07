import gleam/bool.{guard}
import gleam/dict
import gleam/result
import gleam/option.{None, Some}
import gleam/string
import gleam/function.{identity}
import sheen/command

pub opaque type Builder(a) {
  Builder(name: String, spec: command.FlagSpec, map: fn(Int) -> a)
}

const default_desc = command.FlagSpec(
  short: None,
  long: None,
  display: None,
  count: False,
  help: "",
)

pub fn new(name: String) -> Builder(Bool) {
  Builder(name: name, spec: default_desc, map: fn(count) {
    case count {
      0 -> False
      _ -> True
    }
  })
}

pub fn short(builder: Builder(a), short: String) -> Builder(a) {
  Builder(..builder, spec: command.FlagSpec(..builder.spec, short: Some(short)))
}

pub fn long(builder: Builder(a), long: String) -> Builder(a) {
  Builder(..builder, spec: command.FlagSpec(..builder.spec, long: Some(long)))
}

pub fn display(builder: Builder(a), display: String) -> Builder(a) {
  Builder(
    ..builder,
    spec: command.FlagSpec(..builder.spec, display: Some(display)),
  )
}

pub fn help(builder: Builder(a), help: String) -> Builder(a) {
  Builder(..builder, spec: command.FlagSpec(..builder.spec, help: help))
}

pub fn count(builder: Builder(Bool)) -> Builder(Int) {
  let Builder(name, desc, _) = builder
  Builder(
    name: name,
    spec: command.FlagSpec(..desc, count: True),
    map: identity,
  )
}

pub fn build(builder: Builder(a)) -> command.Command(a, b) {
  command.command(fn(cmd: command.CommandSpec) {
    let Builder(name, spec, mapper) = builder

    use first <- result.try(
      string.first(name)
      |> result.replace_error("Flag name cannot be empty"),
    )

    let long = option.unwrap(spec.long, name)
    let short = option.unwrap(spec.short, first)

    use <- guard(
      dict.has_key(cmd.flags, name),
      Error("Flag " <> name <> " already defined"),
    )

    let flags =
      cmd.flags
      |> dict.insert(
        name,
        command.FlagSpec(..spec, long: Some(long), short: Some(short)),
      )

    let cmd = command.CommandSpec(..cmd, flags: flags)
    let validator = fn(input: command.ValidatorInput) {
      let count =
        dict.get(input.flags, name)
        |> result.unwrap(0)
      Ok(mapper(count))
    }
    Ok(command.Builder(cmd, validator))
  })
}
