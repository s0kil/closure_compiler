import httpclient, cgi, pegs, sets, os, osproc, strutils

type CompilationLevel* = enum
    SIMPLE_OPTIMIZATIONS
    WHITESPACE_ONLY
    ADVANCED_OPTIMIZATIONS

proc urlencode(params: openarray[tuple[k : string, v: string]]): string =
    result = ""
    for i, p in params:
        if i != 0:
            result &= "&"
        result &= encodeUrl(p.k)
        result &= "="
        result &= encodeUrl(p.v)

proc nimblePath(package: string): string =
    var nimblecmd = "nimble"
    when defined(windows):
        nimblecmd &= ".cmd"
    var (nimbleNimxDir, err) = execCmdEx(nimblecmd & " path " & package)
    if err == 0:
        let lines = nimbleNimxDir.splitLines()
        if lines.len > 1:
            result = lines[^2]

proc closureCompilerExe(): string =
    if findExe("java").len == 0: return
    let ccpath = nimblePath("closure_compiler")
    if not ccpath.isNil:
        result = ccpath / "compiler-latest" / "compiler.jar"

# Javascript generated by Nim has some incompatibilities with closure compiler
# advanced optimizations:
# - Some properties are accessed by indexing (in nimCopy) and by dot-syntax. E.g:
#       myObj["Field1"]
#       myObj.Field1
# - Another case is passing properties by "ptr". E.g:
#       del(myObj, "myMemberSequence", 5)
#   Closure compiler does not expect non-uniform property access, so we need
#   to extern such properties, so that it doesn't rename them.
#   In order to collect such properties, we look for anything like a valid
#   identifier in a JS string literal.
proc externsFromNimSourceCode(code: string): string =
    result = ""
    let p = peg""" \" {\ident} \" """
    var matches = code.findAll(p)
    for m in matches.mitems:
        var s : array[1, string]
        discard m.match(p, s)
        m = s[0]

    for i in matches.toSet():
        result &= "Object.prototype." & i & ";\n"

proc runLocalCompiler(compExe, sourceCode: string, level: CompilationLevel): string =
    let externs = externsFromNimSourceCode(sourceCode)
    let inputPath = getTempDir() / "closure_input.js"
    let externPath = getTempDir() / "closure_js_extern_tmp.js"
    let outputPath = getTempDir() / "closure_output.js"
    writeFile(externPath, externs)
    writeFile(inputPath, sourceCode)
    discard execProcess(findExe("java"), ["-jar", compExe, inputPath, "--compilation_level", $level,
        "--externs", externPath, "--js_output_file", outputPath], options = {poStdErrToStdOut})
    removeFile(inputPath)
    result = readFile(outputPath)
    removeFile(outputPath)
    removeFile(externPath)

proc runLocalCompiler(compExe, inputPath: string, level: CompilationLevel, srcMap: bool) =
    let externs = externsFromNimSourceCode(readFile(inputPath))
    let workDir = parentDir(inputPath)

    let backupPath = workDir / "before_closure.js"
    let outputPath = inputPath

    let externPath = workDir / "closure_js_extern_tmp.js"
    writeFile(externPath, externs)

    removeFile(backupPath)
    moveFile(inputPath, backupPath)

    var args = @["-jar", compExe, backupPath, "--compilation_level", $level,
        "--externs", externPath, "--js_output_file", outputPath]

    if srcMap:
        let sourceMapPath = workDir / "closure-src-map"
        args.add(["--create_source_map", sourceMapPath,
            "--source_map_location_mapping", backupPath & "|" & extractFilename(backupPath)])

    discard execProcess(findExe("java"), args, options = {poStdErrToStdOut})
    if srcMap:
        let f = open(outputPath, fmAppend)
        f.write("\L//# sourceMappingURL=closure-src-map\L")
        f.close()
    else:
        removeFile(backupPath)
    removeFile(externPath)

proc runWebAPICompiler(sourceCode: string, level: CompilationLevel): string =
    let externs = externsFromNimSourceCode(sourceCode)
    var data = urlencode({
        "compilation_level" : $level,
        "output_format" : "text",
        "output_info" : "compiled_code",
        "js_code" : sourceCode,
        "js_externs" : externs
        })
    result = postContent("http://closure-compiler.appspot.com/compile", body=data,
        extraHeaders="Content-type: application/x-www-form-urlencoded")

proc compileSource*(sourceCode: string, level: CompilationLevel = SIMPLE_OPTIMIZATIONS): string =
    let compExe = closureCompilerExe()
    if compExe.len > 0:
        result = runLocalCompiler(compExe, sourceCode, level)
    else:
        result = runWebAPICompiler(sourceCode, level)

proc compileFile*(f: string, level: CompilationLevel = SIMPLE_OPTIMIZATIONS): string = compileSource(readFile(f), level)

proc compileFileAndRewrite*(f: string, level: CompilationLevel = SIMPLE_OPTIMIZATIONS, produceSourceMap: bool = false): bool {.discardable.} =
    result = true
    let compExe = closureCompilerExe()
    if compExe.len > 0:
        runLocalCompiler(compExe, f, level, produceSourceMap)
    else:
        writeFile(f, runWebAPICompiler(readFile(f), level))

when isMainModule:
    import parseopt2

    proc usage() =
        echo "closure_compiler [-q] [-a|-w] file1 [fileN...]"

    proc main() =
        var files = newSeq[string]()
        var level = SIMPLE_OPTIMIZATIONS
        var quiet = false
        for kind, key, val in getopt():
            case kind:
                of cmdArgument: files.add(key)
                of cmdShortOption:
                    case key:
                        of "a": level = ADVANCED_OPTIMIZATIONS
                        of "w": level = WHITESPACE_ONLY
                        of "q": quiet = true
                        else:
                            usage()
                            return
                else:
                    usage()
                    return

        if files.len == 0:
            usage()
            return

        for f in files:
            if not quiet:
                echo "Processing: ", f
            compileFileAndRewrite(f, level)

    main()
