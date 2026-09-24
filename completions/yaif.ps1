# PowerShell completion for yaif. Enable: add to your $PROFILE (not done automatically):
#   . "C:\path\to\yaif.ps1"
# cmd.exe has no equivalent: it has no extensibility hook for tab-completing a
# third-party program's arguments (unlike bash's complete, zsh's compdef, or
# PowerShell's Register-ArgumentCompleter), so there is no cmd.exe completion here.
Register-ArgumentCompleter -Native -CommandName yaif -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $tokens = $commandAst.CommandElements | ForEach-Object { $_.ToString() }
    $cmds = 'encode', 'decode', 'convert', 'preview', 'info', 'bench', 'version'

    # After a trailing space the word being completed is not yet a CommandElement,
    # so its index is $tokens.Count rather than $tokens.Count - 1.
    $pos = if ($wordToComplete) { $tokens.Count - 1 } else { $tokens.Count }
    $prev = if ($pos -ge 1) { $tokens[$pos - 1] } else { '' }

    $result = if ($pos -le 1) {
        $cmds + '--version'
    } else {
        $sub = $tokens[1]
        switch ($prev) {
            '-m' { if ($sub -eq 'encode') { 'adaptive', 'lossless', 'lossy' } else { 'lossy', 'lossless' } }
            '-l' { '0', '1', '2', '3', '4', '5' }
            '-look' { 'canon', 'darktable' }
            default {
                if ($wordToComplete -like '-*') {
                    switch ($sub) {
                        'encode' { '-m', '-l', '-q', '-e', '-d', '-live' }
                        { $_ -in 'decode', 'convert' } { '-q', '-m', '-fast', '-hdr', '-look' }
                        default { @() }
                    }
                } else {
                    Get-ChildItem -Path "$wordToComplete*" -ErrorAction SilentlyContinue |
                        ForEach-Object { $_.Name }
                }
            }
        }
    }
    $result | Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}
