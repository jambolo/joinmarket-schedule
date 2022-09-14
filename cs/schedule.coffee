# Creates and explains joinmarket schedule files
#
# Syntax:
#
#    schedule create [--input <file>] [--output <file>]
#    schedule step [--mixdepth <M>] [--portion <0-1>] [--counterparties <N>] [--address <address>] [--wait <time>]
#                  [--rounding <0-16>] [--json] [--output <file>]
#    schedule explain [--json] [--input <file>] [--output <file>]
#
# Commands:
#
#    create -   Creates a schedule based on json input
#    step -     Creates a step
#    explain -  Explains the schedule
#
# See https://github.com/JoinMarket-Org/joinmarket-clientserver/blob/master/docs/tumblerguide.md#schedules-transaction-lists
# for a more complete explanation of the schedule items.

csv = require 'papaparse'
fs = require 'fs'
yargs = require 'yargs'

BLOCK_TIME = 10   # Average block time, used to compute how long the tumble will take

# Configure the command line processing
args = yargs
  .usage '$0 <command> <options> [--output <file>]'
  .command 'create', "Creates a schedule based on JSON input.", (yargs) ->
    yargs
      .option 'input', {
        type: 'string'
        alias: 'i'
        describe: 'The input file. (default: stdin)'
      }
  .command 'step', 'Creates a step based on options.', (yargs) ->
    yargs
      .option 'mixdepth', {
        type: 'number'
        demandOption: true
        alias: 'm'
        describe: 'The mixdepth for this step.'
      }
      .option 'portion', {
        type: 'number'
        default: 0
        alias: 'p'
        describe: 'The portion of the mixdepth (0 - 1), or the number of satoshis. 0 means sweep.'
      }
      .option 'counterparties', {
        type: 'number'
        demandOption: true
        alias: 'N'
        describe: 'The desired number of counterparties.'
      }
      .option 'address', {
        type: 'string'
        default: 'INTERNAL'
        alias: 'a'
        describe: 'The desination address, or "INTERNAL" for the next mixdepth, or "addrask".'
      }
      .option 'wait', {
        type: 'number'
        demandOption: true
        alias: 'w'
        describe: 'The number of minutes to wait after this step has been confirmed.'
      }
      .option 'rounding', {
        type: 'number'
        default: 16
        alias: 'r'
        describe: 'Significant digits the coinjoin amount is rounded to. 16 means no rounding. Ignored if sweeping.'
      }
      .option 'json', {
        type: 'boolean'
        default: false
        alias: 'j'
        describe: 'The output is in JSON form.'
      }
  .command 'explain', "Explains the steps in a schedule.", (yargs) ->
    yargs
      .option 'json', {
        type: 'boolean'
        default: false
        alias: 'j'
        describe: 'The output is in JSON form.'
      }
      .option 'input', {
        type: 'string'
        alias: 'i'
        describe: 'The input file. (default: stdin)'
      }
      .option 'amtmixdepths', {
        type: 'number'
        default: 5
        alias: 'A'
        describe: 'Number of mixdepths ever used in the wallet.'
      }
  .help()
  .version()
  .option 'output', {
    type: 'string'
    alias: 'o'
    describe: 'The output file. (default: stdout)'
  }
  .check (argv) ->
    if argv._.length < 1
      throw new Error "Missing command."
    if argv._.length > 1
      throw new Error "Unexpected '#{argv._[0]}'."
    if argv._[0] != 'create' and argv._[0] != 'step' and argv._[0] != 'explain'
      throw new Error "'#{argv._[0]}' is an invalid command."
    if argv._[0] is 'step'
      if argv.mixdepth < 0
        throw new Error "#{argv.mixdepth} is not a valid mixdepth"
      if argv.portion < 0 or (argv.portion > 1 and Math.floor(argv.portion) != argv.portion)
        throw new Error "The portion must be a number between 0 and 1 (inclusive) or an integer."
      if argv.counterparties < 1 or Math.floor(argv.counterparties) != argv.counterparties
        throw new Error "The number of counterparties must be an integer greater than 0."
      if argv.wait < 0
        throw new Error "The wait time cannot be negative."
      if argv.rounding < 0 or argv.rounding > 16 or Math.floor(argv.rounding) != argv.rounding
        throw new Error "The rounding must be an integer between 0 and 16 (inclusive)."
    if argv._[0] is 'explain'
      if argv.amtmixdepths < 5 or Math.floor(argv.amtmixdepths) != argv.amtmixdepths
        throw new Error "The number of mixdepths must be an integer greater than 5 (the default)."
    return true
  .argv

explainStep = (i, mixdepth, portion, counterparties, address, wait, rounding, state, json) ->
  if json
    if typeof(state) is "number" and state is 1
      { mixdepth, portion, counterparties, address, wait, rounding, completed: true }
    else if typeof(state) is "string"
      { mixdepth, portion, counterparties, address, wait, rounding, completed: false, txid: state }
    else
      { mixdepth, portion, counterparties, address, wait, rounding, completed: false }
  else
    text = "#{i}: Send "
    if portion >= 1
      text += "#{portion} satoshis from "
    else if portion != 0
      text += "#{Math.round(portion * 100.0)}% of "
    text += "mixdepth #{mixdepth} to "
    switch address
      when 'INTERNAL' then text += "mixdepth #{(mixdepth + 1) % args.amtmixdepths}"
      when 'addrask' then text += "a user-supplied address"
      else text += "'#{address}'"
    text += " using #{counterparties} counterparties"
    if rounding != 16
      text += ", rounding the amount to #{rounding} places"
    text += ". Then wait #{wait} minutes after confirmation."
    if typeof(state) is "number" and state is 1
      text += " (completed)"
    else if typeof(state) is "string"
      text += " (unconfirmed, txid: #{state})"
    text += '\n'

create = (input, output, json) ->
  return

step = (mixdepth, portion, counterparties, address, wait, rounding, output, json) ->
  if json
    s = { mixdepth, portion, counterparties, address, wait, rounding, completed: false }
    output.end JSON.stringify(s)
  else
    output.end "#{mixdepth},#{portion},#{counterparties},#{address},#{wait},#{rounding},0"

  return

explain = (input, output, json) ->
  i = 1
  finalWaitTime = 0   # Wait time for the final step (tracked so that it can be ignored)
  expectedTime = 0    # Expected total time for the tumble
  jsonResult = []
  csv.parse input, {
    step: (results, parser) ->
#      console.log "step: results.data=", results.data
#      console.log "step: results.errors=", results.errors
      return if not results.data[0]?
      [ mixdepth, portion, counterparties, address, wait, rounding, state ] = results.data
      step = explainStep(i, mixdepth, portion, counterparties, address, wait, rounding, state, json)
      if json
        jsonResult.push step
      else
        output.write step
        expectedTime += BLOCK_TIME + wait
        finalWaitTime = wait
        i += 1
      return
    complete: (results, file) ->
#      console.log "complete: results=", results, ", file=", file
      if json
        output.end JSON.stringify(jsonResult)
      else
        expectedTime -= finalWaitTime
        expectedHours = Math.floor(expectedTime / 60)
        expectedMinutes = Math.round(expectedTime - expectedHours * 60)
        output.end "Total expected time is #{expectedHours} hours, #{expectedMinutes} minutes.\n"
      return
    error: (error, file) ->
      console.log "error: error=", error, ", file=", file
    dynamicTyping: true
  }

  return

#console.log JSON.stringify(args)

if args.input?
  input = fs.createReadStream(args.input)
  input.on 'error', (error) ->
    console.error error
    process.exit()
else
  input = process.stdin

if args.output?
  output = fs.createWriteStream(args.output)
  output.on 'error', (error) ->
    console.error error
    process.exit
else
  output = process.stdout

switch args._[0]
  when 'create' then create input, output
  when 'step'   then step args.mixdepth, args.portion, args.counterparties, args.address, args.wait, args.rounding, output, args.json
  when 'explain'  then explain input, output, args.json
