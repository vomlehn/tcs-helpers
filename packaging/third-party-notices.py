#!/usr/bin/env -S python3 -I
"""Writes the notices a package owes the Rust crates compiled into it.

    third-party-notices.py <workspace> <output> <package> [<crate>...]

It is tcs-helpers', shared by the TCS projects, and run from its checkout.
<workspace> is the directory of the Cargo workspace the package's programs
and libraries are built in; <output> the file to write, which a project's
install-files puts in the package's documentation directory as
THIRD-PARTY-NOTICES; <package> the package's name, for the file's heading;
and each <crate> one of the workspace's crates whose programs or libraries
the package ships, every one in the workspace if none is named.

Nearly every crate's licence -- MIT, Apache-2.0, the BSD licences, Zlib,
Unicode-3.0, the SIL Open Font License of a font a crate embeds -- requires
its copyright and licence notices to go with every copy, and a program is a
copy of the crates compiled into it. So each package of compiled code
carries this file, listing each such crate with the licence it is taken
under and every licence and notice file it ships, each text printed once.

Only the crates that are compiled in are listed: those the named crates
depend on for the host they are built for, not those they are tested or
built with, and not procedural macros, which run in the compiler. That is
what `cargo tree` resolves, with the features the build turns on. It runs
offline, since the build has fetched every crate already; a crate it has
not means the build was not run first.

The Rust standard library is compiled into every program too, and its
notices are those the toolchain ships for it, COPYRIGHT-library.html in
its documentation, which is added as text after the crates.

A crate that ships no licence file gets the standard text of the licence
it is taken under, from packaging/licences or this checkout's
LICENSE-APACHE, with its authors as the copyright holders. A licence with
no standard text there stops the script, which names the file to add.
"""

import html.parser
import json
import os
import re
import subprocess
import sys

HELPERS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The standard texts of the licences a crate may be taken under without
# shipping its own copy, by SPDX identifier.
STANDARD = {
	"MIT": os.path.join(HELPERS, "packaging/licences/MIT"),
	"Apache-2.0": os.path.join(HELPERS, "LICENSE-APACHE"),
	"OFL-1.1": os.path.join(HELPERS, "packaging/licences/OFL-1.1"),
}

# Which licence of a choice the TCS projects take, the most preferred
# first: the permissive ones, and Slint's royalty-free licence for desktop
# applications, which the TCS programs meet by showing Slint's attribution
# badge (see each project's README), rather than the GPL-3.0 it is also
# offered under. A licence not listed is taken only when it is offered
# alone.
PREFERRED = [
	"MIT", "Apache-2.0", "Apache-2.0 WITH LLVM-exception", "BSD-3-Clause",
	"BSD-2-Clause", "ISC", "Zlib", "0BSD", "MIT-0", "Unlicense", "CC0-1.0",
	"BSL-1.0", "Unicode-3.0", "Unicode-DFS-2016",
	"LicenseRef-Slint-Royalty-free-2.0",
]

# The files at the top of a crate that hold its licence or notices.
LICENCE_FILE = re.compile(
	r"^(LICEN[CS]E|COPYING|COPYRIGHT|NOTICE|UNLICENSE)", re.IGNORECASE)


def fail(message):
	"""Stops the script with a message saying what to do.

	Args:
	    message: What is wrong and what to do about it.
	"""
	print(f"third-party-notices.py: {message}", file=sys.stderr)
	sys.exit(1)


def cargo(workspace, *args):
	"""Runs cargo in the workspace, offline, and returns what it printed.

	Args:
	    workspace: The workspace's directory.
	    args:      cargo's arguments.

	Returns:
	    cargo's standard output.
	"""
	got = subprocess.run(
		["cargo", *args, "--offline", "--locked"], cwd=workspace,
		capture_output=True, text=True, check=False)
	if got.returncode != 0:
		fail(f"cargo {args[0]} in {workspace} failed; build the "
		     f"workspace first, so that every crate is fetched:\n"
		     f"{got.stderr.strip()}")
	return got.stdout


def host():
	"""Says which target the build is for: the host's.

	Returns:
	    The host's target triple, such as x86_64-unknown-linux-gnu.
	"""
	out = subprocess.run(["rustc", "-vV"], capture_output=True, text=True,
			     check=True).stdout
	return re.search(r"^host: (\S+)", out, re.MULTILINE).group(1)


def compiled_in(workspace, crates):
	"""Finds the crates compiled into the named crates' programs.

	Args:
	    workspace: The workspace's directory.
	    crates:    The workspace's crates the package ships, or none for
	               every one.

	Returns:
	    The set of (name, version) of every crate compiled in, the named
	    ones among them.
	"""
	which = [a for c in crates for a in ("-p", c)] or ["--workspace"]
	out = cargo(workspace, "tree", *which, "-e", "normal,no-proc-macro",
		    "--prefix", "none", "--format", "{p}", "--target", host())
	found = set()
	for line in out.splitlines():
		m = re.match(r"^(\S+) v(\S+)", line)
		if m:
			found.add((m.group(1), m.group(2)))
	return found


def tokens(expression):
	"""Splits an SPDX licence expression into its words.

	Args:
	    expression: The expression, such as "(MIT OR Apache-2.0) AND
	                Unicode-3.0", or the old "MIT/Apache-2.0".

	Returns:
	    Its identifiers, operators and parentheses, with each "X WITH Y"
	    kept as one identifier.
	"""
	words = re.findall(r"\(|\)|[^\s()/]+|/", expression)
	words = ["OR" if w == "/" else w for w in words]
	joined = []
	for w in words:
		if joined and (w == "WITH" or joined[-1].endswith(" WITH")):
			joined[-1] += " " + w
		else:
			joined.append(w)
	return joined


def choose(expression):
	"""Picks the licences a crate is taken under from its expression.

	Args:
	    expression: The crate's SPDX licence expression.

	Returns:
	    The identifiers taken, all of which apply: of each OR the most
	    preferred alternative, and every part of an AND.
	"""
	words = tokens(expression)
	pos = 0

	def rank(ids):
		# An alternative is as good as its least preferred licence.
		return max(PREFERRED.index(i) if i in PREFERRED
			   else len(PREFERRED) for i in ids)

	def either():
		nonlocal pos
		best = both()
		while pos < len(words) and words[pos] == "OR":
			pos += 1
			other = both()
			if rank(other) < rank(best):
				best = other
		return best

	def both():
		nonlocal pos
		ids = one()
		while pos < len(words) and words[pos] == "AND":
			pos += 1
			ids = ids + one()
		return ids

	def one():
		nonlocal pos
		word = words[pos]
		pos += 1
		if word == "(":
			ids = either()
			pos += 1
			return ids
		return [word]

	return either()


def own_files(directory):
	"""Finds the licence and notice files a crate ships.

	Args:
	    directory: The crate's source directory.

	Returns:
	    Their paths relative to it: those at its top, those in its
	    LICENSES directory, and every REUSE ".license" file beside a file
	    it embeds, such as a font.
	"""
	found = [f for f in sorted(os.listdir(directory))
		 if LICENCE_FILE.match(f)
		 and os.path.isfile(os.path.join(directory, f))]
	licences = os.path.join(directory, "LICENSES")
	if os.path.isdir(licences):
		found += [os.path.join("LICENSES", f)
			  for f in sorted(os.listdir(licences))]
	for root, dirs, files in os.walk(directory):
		dirs[:] = sorted(d for d in dirs if d != "target")
		for f in sorted(files):
			if f.endswith(".license"):
				found.append(os.path.relpath(
					os.path.join(root, f), directory))
	return found


def read(path):
	"""Reads a text file, whatever its encoding.

	Args:
	    path: The file.

	Returns:
	    Its text, with trailing white space removed.
	"""
	with open(path, encoding="utf-8", errors="replace") as f:
		return f.read().rstrip()


def standard(identifier, crate):
	"""Gives the standard text of a licence a crate does not ship.

	Args:
	    identifier: The licence's SPDX identifier.
	    crate:      The crate's name and version, for the message.

	Returns:
	    The licence's text.
	"""
	path = STANDARD.get(identifier.split(" WITH ")[0])
	if path is None:
		fail(f"{crate} ships no licence file and is under "
		     f"{identifier}, which tcs-helpers has no text for: add "
		     f"the licence's standard text as packaging/licences/"
		     f"{identifier} and name it in third-party-notices.py's "
		     f"STANDARD")
	return read(path)


class _Text(html.parser.HTMLParser):
	"""Takes the text of an HTML page, without its head, styles and
	scripts.

	Attributes:
	    parts: The page's text, in pieces, as met.
	    skip:  How many elements whose text is not shown are open.
	"""

	def __init__(self):
		"""Starts with no text."""
		super().__init__()
		self.parts = []
		self.skip = 0

	def handle_starttag(self, tag, attrs):
		"""Notes an element whose text is not shown opening.

		Args:
		    tag:   The element's name.
		    attrs: Its attributes, which are not wanted.
		"""
		if tag in ("head", "style", "script"):
			self.skip += 1

	def handle_endtag(self, tag):
		"""Notes an element whose text is not shown closing.

		Args:
		    tag: The element's name.
		"""
		if tag in ("head", "style", "script"):
			self.skip -= 1

	def handle_data(self, data):
		"""Keeps text that is shown.

		Args:
		    data: The text.
		"""
		if not self.skip:
			self.parts.append(data)


def standard_library():
	"""Gives the notices of the Rust standard library being compiled in.

	Returns:
	    Their text, from the toolchain's COPYRIGHT-library.html.
	"""
	sysroot = subprocess.run(["rustc", "--print", "sysroot"],
				 capture_output=True, text=True,
				 check=True).stdout.strip()
	page = os.path.join(sysroot, "share/doc/rust/COPYRIGHT-library.html")
	if not os.path.isfile(page):
		fail(f"{page}, the Rust standard library's notices, is "
		     f"missing: use a toolchain installed by rustup, which "
		     f"ships it")
	parser = _Text()
	parser.feed(read(page))
	return re.sub(r"\n\s*\n+", "\n\n", "".join(parser.parts)).strip()


class Texts:
	"""The licence and notice texts, each numbered and kept once.

	Attributes:
	    texts:   Each distinct text, in the order first met.
	    numbers: Each text's number, from 1, by text.
	"""

	def __init__(self):
		"""Starts with no texts."""
		self.texts = []
		self.numbers = {}

	def number(self, text):
		"""Gives a text's number, keeping it if it is new.

		Args:
		    text: The text.

		Returns:
		    Its number.
		"""
		if text not in self.numbers:
			self.texts.append(text)
			self.numbers[text] = len(self.texts)
		return self.numbers[text]


def entry(p, texts):
	"""Writes one crate's entry.

	Args:
	    p:     The crate, as cargo metadata gives it.
	    texts: The texts so far, which the crate's are added to.

	Returns:
	    Its entry, lines without a final newline.
	"""
	name = f"{p['name']} {p['version']}"
	expression = p.get("license") or ""
	directory = os.path.dirname(p["manifest_path"])
	files = own_files(directory)
	if p.get("license_file"):
		files.append(p["license_file"])
	lines = [f"== {name}"]
	taken = choose(expression) if expression else []
	lines.append(f"Licence:  {expression or 'its own, in its file'}")
	if "OR" in tokens(expression):
		lines.append(f"Taken under: {' AND '.join(taken)}")
	if p.get("repository"):
		lines.append(f"Source:   {p['repository']}")
	for f in files:
		text = read(os.path.join(directory, f))
		lines.append(f"Text [{texts.number(text)}]: {f}")
		# A REUSE file names an embedded file's licence without its
		# text, which then comes from the standard ones.
		m = re.search(r"SPDX-License-Identifier:\s*(\S+)", text)
		if f.endswith(".license") and m:
			ident = re.sub(r"-(RFN|no-RFN)$", "", m.group(1))
			n = texts.number(standard(ident, name))
			lines.append(f"Text [{n}]: {ident}, for "
				     f"{f[:-len('.license')]}")
	if not files:
		holders = ", ".join(p.get("authors") or []) \
			or f"the {p['name']} authors"
		lines.append(f"Copyright: {holders}")
		for ident in taken:
			n = texts.number(standard(ident, name))
			lines.append(f"Text [{n}]: the standard {ident} text")
	return "\n".join(lines)


def main(argv):
	"""Writes the notices for the package.

	Args:
	    argv: The command line, as the module's documentation gives it.

	Returns:
	    The exit status.
	"""
	if len(argv) < 4:
		print("usage: third-party-notices.py <workspace> <output> "
		      "<package> [<crate>...]", file=sys.stderr)
		return 2
	workspace, output, package = argv[1:4]

	# For the host alone, as cargo tree is, so that the crates only
	# other systems are built with, which were never fetched, are not
	# asked for.
	meta = json.loads(cargo(workspace, "metadata", "--format-version",
				"1", "--filter-platform", host()))
	members = set(meta["workspace_members"])
	by_name = {(p["name"], p["version"]): p for p in meta["packages"]}
	texts = Texts()
	entries = []
	for key in sorted(compiled_in(workspace, argv[4:])):
		p = by_name.get(key)
		if p is None:
			fail(f"cargo tree names {key[0]} {key[1]}, which "
			     f"cargo metadata does not; run cargo fetch in "
			     f"{workspace}")
		if p["id"] not in members:
			entries.append(entry(p, texts))

	rustc = subprocess.run(["rustc", "-V"], capture_output=True,
			       text=True, check=True).stdout.split()[1]
	n = texts.number(standard_library())
	entries.append(f"== The Rust standard library {rustc}\n"
		       f"Licence:  Apache-2.0 OR MIT, and the licences its "
		       f"notices give\nTaken under: MIT\n"
		       f"Text [{n}]: its notices, from the toolchain")

	heading = f"Third-party notices for {package}"
	with open(output, "w", encoding="utf-8") as f:
		f.write(f"{heading}\n{'=' * len(heading)}\n\n")
		f.write(f"{package}'s programs and libraries have these "
			"Rust crates compiled\ninto them. Each is listed "
			"with its licence, the one it is taken under\n"
			"where it offers a choice, and the licence and "
			"notice files it ships,\nwhose texts follow the "
			"list, numbered, each printed once.\n\n")
		f.write("\n\n".join(entries))
		for n, text in enumerate(texts.texts, 1):
			f.write(f"\n\n\n---- [{n}] ----\n\n{text}")
		f.write("\n")
	return 0


if __name__ == "__main__":
	sys.exit(main(sys.argv))
