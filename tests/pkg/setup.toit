import host.os
import host.directory
import host.file
import encoding.yaml

TOIT-REGISTRY-MAP := {
    "url": "github.com/toitware/registry",
    "type": "git",
    "ref-hash": "1f76f33242ddcb7e71ff72be57c541d969aabfb2",
}

setup-test-registry -> string:
  // Initialize the registries storage
  tmp-dir := directory.mkdtemp "test-"
  os.env["TOIT_PKG_CACHE_DIR"] = ".test-cache"
  directory.mkdir --recursive ".test-cache"
  file.write-content --path=".test-cache/registries.yaml"
      yaml.encode {"toit": TOIT-REGISTRY-MAP}
  return tmp-dir
