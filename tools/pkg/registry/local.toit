import host.directory
import host.file

import .registry
import ..semantic-version
import ..file-system-view

class LocalRegistry extends Registry:
  type ::= "local"
  path/string

  constructor name/string .path/string:
    super name

  content -> FileSystemView:
    return FileSystemView_ path

  to-map -> Map:
    return  {
      "path": path,
      "type": type,
    }

  sync:

  stringify -> string:
    return "$path ($type)"

class FileSystemView_ implements FileSystemView:
  root/string

  constructor .root:

  get --path/List -> any:
    if path.is-empty: return null
    if path.size == 1: return get path[0]

    entry := "$root/$path[0]"
    if not file.is_directory entry: return null
    return (FileSystemView_ entry).get --path=path[1..]

  get key/string -> any:
    entry := "$root/$key"

    if not file.stat entry: return null

    if file.is_directory entry:
      return FileSystemView_ entry

    return file.read_content entry

  list -> Map:
    result := {:}
    stream := directory.DirectoryStream root
    try:
      while next := stream.next:
        next_ := "$root/$next"
        if file.is_directory next_:
          result[next] = FileSystemView_ "$root/$next"
        else:
          result[next] = next
    finally:
      stream.close
    return result