import system

import cli

import ..pkg
import ..registry

class RegistryCommand:
  static LOCAL     ::= "local"
  static NAME      ::= "name"
  static URLPATH   ::= "URL/path"

  local/bool := false
  url/string? := null
  name/string? := null
  constructor.add parsed/cli.Parsed:
    local = parsed[LOCAL]
    url = parsed[URLPATH]
    name = parsed[NAME]

  constructor.remove parsed/cli.Parsed:
    name = parsed[NAME]

  constructor.sync parsed/cli.Parsed:
    name = parsed[NAME]

  constructor.list parsed/cli.Parsed:

  add:
    if local:
      registries.add --local name url
    else:
      registries.add --git name url

  remove:
    registries.remove name

  list:
    registries.list

  sync:
    if not name:
      registries.sync
    else:
      registries.sync --name=name

  static CLI-COMMAND ::=
      cli.Command "registry"
          --help="Manages registries."
          --subcommands=[
                cli.Command "add"
                    --help="""
                           Adds a registry.

                           The 'name' of the registry must not be used yet.

                           By default the 'URL' is interpreted as Git-URL.
                             If the '--local' flag is used, then the 'URL' is interpreted as local
                             path to a folder containing package descriptions.
                           """
                    --rest=[
                        cli.Option "name"
                            --help="Name of the registry"
                            --required,

                        cli.Option "URL/path"
                            --help="URL/Path of the registry"
                            --required
                      ]
                    --options=[
                          cli.Flag LOCAL
                              --help="Registry is local."
                              --default=false
                      ]
                    --examples=[
                          cli.Example --arguments="user ~/user-repository --local"
                              """
                              Add a local registry with name user located at the path ~/user-repository.
                              """,

                          cli.Example --arguments="toit github.com/toitware/registry"
                              """
                              Add the toit registry.
                              """
                    ]
                    --run=:: (RegistryCommand.add it).add,

                cli.Command "remove"
                    --help="""
                           Removes a registry.

                           The 'name' of the registry must exist.
                           """
                    --rest=[
                        cli.Option "name"
                            --help="Name of the registry"
                            --required
                      ]
                    --run=:: (RegistryCommand.remove it).remove,

                cli.Command "list"
                    --help="List registries"
                    --run=:: (RegistryCommand.list it).list,

                cli.Command "sync"
                    --help="""
                           Synchronizes all registries.

                           If no argument is given, synchronizes all registries.
                           If an argument is given, only that registry is synchronized.
                           """
                    --rest=[
                        cli.Option "name"
                            --help="Name of the registry"
                            --required=false
                      ]
                    --run=:: (RegistryCommand.sync it).sync,
          ]
