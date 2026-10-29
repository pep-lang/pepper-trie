# Using this template

`pepper new <name> --lib` writes these same files with the name filled in
(and `--license` picks the license), leaving only `OWNER` of step 2.
pep-new holds them in pep-lang/pepper's `tools/scaffold/template.pep`, and
`.github/workflows/template.yml` checks the two match, so a change here goes
there too.

1. Create the repository from this template, named `pepper-<name>`.
2. Replace the placeholders: `mypkg` (the module name, also the folder
   name on the import path) and `OWNER` (the GitHub owner):

   ```sh
   git grep -lz -e mypkg -e OWNER | xargs -0 sed -i 's/mypkg/<name>/g; s/OWNER/<owner>/g'
   ```

3. Fill in `description` in `pep.toml`, the README's opening paragraph,
   and the `##` comment at the top of `module.pep`.
4. Replace `greet.pep` and `tests/greet_test.pep` with the package's own
   files. `module.pep` only gathers the public API (`import "file";` then
   `export Name;`, or `export * from "file";`). Every public declaration
   gets a `##` doc comment (description, then `@param`, `@returns`,
   `@panics`, `@example`), and each file opens with a `##` block saying
   what it holds.
5. Add anything `tests/run.sh` should also build or run, such as an
   `examples/<name>/main.pep`, and data files under `tests/`.
6. C code: the `[native]` table in `pep.toml` compiles `native/*.c` for
   the build's target and links it, and `add.pep` calls it. Put the
   package's own C there (more keys, such as `include` and `link`, are in
   Pepper's projects page), or, with none, delete what the comment above
   `[native]` names.
7. Release: set `version` in `pep.toml`, merge, then push the tag
   `vX.Y.Z` matching it. CI tests the tag and publishes the release; a tag
   that does not match `pep.toml` fails. Turn on GitHub Pages for the
   `gh-pages` branch the first release makes (Settings, Pages), which then
   serves each release's reference.
8. Delete this file and `.github/workflows/template.yml`.
