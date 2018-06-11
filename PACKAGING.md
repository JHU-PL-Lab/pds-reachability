# Packaging

The following steps should be sufficient to package `pds-reachability` for distribution.

  1. Run `make clean && make test` one more time.

  2. Update the version numbers in the OPAM package file.

  3. Use `opam pin add .` and `opam pin remove pds-reachability` to determine if the
     package metadata is correct and see whether it will install properly.

  4. Use `opam-publish prepare pds-reachbility URL` where `URL` is the location of the
     GitHub tarball reflecting the commit you are trying to release.  This URL
     will probably be something like
     `https://github.com/JHU-PL-Lab/pds-reachability/archive/<commit-hash>.zip`

  5. Run `opam-publish submit DIR` where `DIR` is the directory created in the
     previous step.

  6. Follow the CI builds on GitHub for the resulting pull request into the OPAM
     repository.

  7. Once the Travis CI is successful, tag the released commit.

  8. Modify the `_oasis` file to contain a modified version (e.g. `0.1+dev`) to
     distinguish the released version from future development.
