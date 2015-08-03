require 'docopt'
require 'pp'

module Runfile

  # The Runner class is the main workhorse behind Runfile.
  # It handles all the Runfile DSL commands and executes the 
  # Runfile with the help of two more specialized classes:
  # 1. DocoptHelper - for deeper docopt related actions
  # 2. RunfileHelper - for Runfile creation and system wide search
  class Runner
    attr_accessor :last_usage, :last_help, :name, :version, 
      :summary, :namespace, :superspace

    @@instance = nil

    # Initialize all variables to sensible defaults.
    def initialize
      @superspace = nil    # used when filename != Runfile
      @last_usage = nil    # dsl: usage
      @last_help  = nil    # dsl: help
      @namespace  = nil    # dsl: command
      @actions = {}        # dsl: action
      @options = {}        # dsl: option
      @name    = "Runfile" # dsl: name
      @version = "0.0.0"   # dsl: version
      @summary = false     # dsl: summary
    end

    # Return a singleton Runner instance.
    def self.instance
      @@instance = self.new if @@instance.nil?
      @@instance
    end

    # Load and execute a Runfile call.
    def execute(argv, filename='Runfile')
      File.file?(filename) or handle_no_runfile argv
      begin
        load filename
      rescue => ex
        abort "Runfile error:\n#{ex.message}\n#{ex.backtrace[0]}"
      end
      @@instance.run *argv
    end

    # Add an action to the @actions array, and use the last known
    # usage and help messages sent by the DSL.
    def add_action(name, altname=nil, &block)
      if @last_usage.nil?
        @last_usage = altname ? "( #{name} | #{altname} )" : name 
      end
      [@namespace, @superspace].each do |prefix|
        prefix or next
        name = "#{prefix}_#{name}"
        @last_usage = "#{prefix} #{last_usage}" unless @last_usage == false
      end
      name = name.to_sym
      @actions[name] = Action.new(block, @last_usage, @last_help)
      @last_usage = nil
      @last_help = nil
      if altname 
        @last_usage = false
        add_action(altname, nil, &block)
      end
    end

    # Add an option flag and its help text.
    def add_option(flag, text, scope=nil)
      scope or scope = 'Options'
      @options[scope] ||= {}
      @options[scope][flag] = text
    end

    # Run the command. This is a wrapper around docopt. It will 
    # generate the docopt document on the fly, using all the 
    # information collected so far.
    def run(*argv)
      begin
        docopt_exec argv
      rescue Docopt::Exit => ex
        puts ex.message
      end
    end

    # Invoke action from another action. Used by the DSL's #call 
    # function. Expects to get a single string that looks as if
    # it was typed in the command prompt.
    def cross_call(command_string) 
      argv = command_string.split /\s(?=(?:[^"]|"[^"]*")*$)/
      begin
        docopt_exec argv
      rescue Docopt::Exit => ex
        puts "Cross call failed: #{command_string}"
        abort ex.message
      end
    end

    private

    # Call the docopt parser and execute the action with the 
    # parsed arguments.
    # This should always be called in a begin...rescue block and
    # you should handle the Docopt::Exit exception.
    def docopt_exec(argv)
      helper = DocoptHelper.new(@name, @version, @summary, @actions, @options)
      args   = helper.args argv
      action = find_action argv
      action or abort "Runfile error: Action not found"
      @actions[action].execute args
    end

    # Inspect the first three arguments in the argv and look for
    # a matching action.
    # We will first look for a_b_c action, then for a_b and 
    # finally for a. This is intended to allow "overloading" of 
    # the command as an action (e.g. also allow a global action 
    # called 'a').
    # if no command was found, but we have a :global command, 
    # assume this is the requested one (since we will not reach 
    # this point unless the usage pattern matches).
    def find_action(argv)
      3.downto(1).each do |count|
        next unless argv.size >= count 
        action = argv[0..count-1].join('_').to_sym
        return action if @actions.has_key? action
      end
      return :global if @actions.has_key? :global 
      return false
    end

    # When `run` is called without a Runfile (or runfile not 
    # found), hand over handling to the RunfileHelper class.
    # If will either return false if no further handling is needed
    # on our part, or the name of a runfile to execute.
    def handle_no_runfile(argv)
      maker = RunfileHelper.new
      runfile = maker.handle argv
      if runfile
        @superspace = argv[0]
        execute argv, runfile
      end
      exit
    end
  end
end
