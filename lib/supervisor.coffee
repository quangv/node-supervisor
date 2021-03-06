util = require 'util'
fs = require 'fs'
{spawn} = require 'child_process'

exports.run = (args) ->
  while arg = args.shift()
    if arg == "--help" || arg == "-h" || arg == "-?"
      return supervisor.help()

    else if arg == "--watch" || arg == "-w"
      watch = args.shift()

    else if arg == "--poll-interval" || arg == "-p"
      poll_interval = parseInt(args.shift())

    else if arg == "--extensions" || arg == "-e"
      extensions = args.shift()

    else if arg == "--exec" || arg == "-x"
      executor = args.shift()

    else if arg == "--"
      # Remaining args are: program [args, ...]
      program = args.shift()
      programArgs = args.slice(0)
      break

    else if arg.indexOf("-") and not args.length
      # Assume last arg is the program
      program = arg

  return supervisor.help()  unless program
  watch = "."  unless watch
  poll_interval = 0  unless poll_interval

  programExt = program.match(/.*\.(.*)/)
  programExt = programExt and programExt[1]

  unless extensions
    # If no extensions passed try to guess from the program
    extensions = "node|js"
    if programExt and extensions.indexOf(programExt) is -1
      extensions += "|" + programExt

  supervisor.fileExtensionPattern = new RegExp("^.*.(" + extensions + ")$")

  unless executor
    executor = if (programExt == "coffee") then "coffee" else "node"

  supervisor.startMsg {program:program, watch:watch, extensions:extensions, executor:executor}

  # if we have a program, then run it, and restart when it crashes.
  # if we have a watch folder, then watch the folder for changes and restart the prog
  supervisor.startProgram program, executor, programArgs

  watchItems = watch.split(",")
  watchItems.forEach (watchItem) ->
    unless watchItem.match(/^\/.*/) # watch is not an absolute path
      # convert watch item to absolute path
      watchItem = process.cwd() + "/" + watchItem

    util.debug "Watching directory '" + watchItem + "' for changes."

    supervisor.findAllWatchFiles watchItem, (f) ->
      supervisor.watchGivenFile f, poll_interval



supervisor =
  fileExtensionPattern : undefined

  startProgram : (prog, exec, args) ->
    if args
      util.debug "Starting child process with '#{exec} #{prog} #{args}'"
    else
      util.debug "Starting child process with '#{exec} #{prog}'"

    spawnme = if args then [ prog ].concat(args) else [ prog ]

    child = exports.child = spawn(exec, spawnme)

    child.stdout.addListener "data", (chunk) ->
      chunk and util.print(chunk)

    child.stderr.addListener "data", (chunk) ->
      chunk and util.debug(chunk)

    child.addListener "exit", ->
      supervisor.startProgram prog, exec, args
  
  crash_queued : false
  crash : (oldStat, newStat) ->
    # we only care about modification time, not access time.
    return  if newStat.mtime.getTime() == oldStat.mtime.getTime() || supervisor.crash_queued

    supervisor.crash_queued = true
    child = exports.child

    setTimeout (->
      util.debug "crashing child"
      process.kill child.pid
      supervisor.crash_queued = false
    ), 50

  watchGivenFile : (watch, poll_interval) ->
    fs.watchFile watch,
      persistent: true
      interval: poll_interval
    , supervisor.crash

  findAllWatchFiles : (path, callback) ->
    fs.stat path, (err, stats) ->
      if err
        util.error "Error retrieving stats for file: " + path
      else
        if stats.isDirectory()
          fs.readdir path, (err, fileNames) ->
            if err
              util.puts "Error reading path: " + path
            else
              fileNames.forEach (fileName) ->
                supervisor.findAllWatchFiles path + "/" + fileName, callback
        else
          if path.match(supervisor.fileExtensionPattern)
            callback path

  startMsg : (msg)->
    util.debug """
      Running node-supervisor with
        program '#{msg.program}'
        --watch '#{msg.watch}'
        --extensions '#{msg.extensions}'
        --exec '#{msg.executor}'
      """
  help : ->
    util.print '''

      Node Supervisor is used to restart programs when they crash.
      It can also be used to restart programs when a *.js file changes.
      
      Usage:
        supervisor [options] <program>
      
      Required:
        <program>
          The program to run.
      
      Options:
        -w|--watch <watchItems>
          A comma-delimited list of folders or js files to watch for changes.
          When a change to a js file occurs, reload the program
          Default is '.'
      
        -p|--poll-interval <milliseconds>
          How often to poll watched files for changes.
          Defaults to Node default.
      
        -e|--extensions <extensions>
          Specific file extensions to watch in addition to defaults.
          Used when --watch option includes folders
          Default is 'node|js'
      
        -x|--exec <executable>
          The executable that runs the specified program.
          Default is 'node'
      
        -h|--help|-?
          Display these usage instructions.
      
      Examples:
        supervisor myapp.js
        supervisor myapp.coffee
        supervisor -w scripts -e myext -x myrunner myapp

      '''
