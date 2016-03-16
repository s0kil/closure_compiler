# closure-compiler
Nim wrapper to [closure compiler](https://developers.google.com/closure/compiler/).

# Usage example: nakefile
```Nim
import nake
import browsers
import closure_compiler

task "js", "Create Javascript version":
    direShell nimExe, "js", "main"
    closure_compiler.compileFileAndRewrite("nimcache" / "main.js", ADVANCED_OPTIMIZATIONS)
    openDefaultBrowser "main.html"
```
[More about nake](https://github.com/fowlmouth/nake)

# Usage example: command line
```sh
nim js main # Compile main.nim and save it to nimcache/main.js
closure_compiler nimcache/main.js # Run closure compiler
```

# Why wrapper
The Javascript code generated by Nim is incompatible with Closure compilers advanced
optimization. This wrapper fixes those issues by providing an externs list to the compiler.
The list is formed by analizing the source code.

# Performance considerations
The wrapper will first try to find `java` executable and use it to run closure-compiler embedded in the package. If `java` is not found it will fall back to web API. Please note that web API has some limitations:

* It is slower than locally installed version.
* There is an input file size limitation.
* It may fail with timeout if your generated `js` file is complex enough.
* It doesn't support source map generation.
