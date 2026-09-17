# PowerShell completion for nova. Enable: add to your $PROFILE (not done automatically):
#   . "C:\path\to\nova.ps1"
# cmd.exe has no equivalent: it has no extensibility hook for tab-completing a
# third-party program's arguments (unlike bash's complete, zsh's compdef, or
# PowerShell's Register-ArgumentCompleter), so there is no cmd.exe completion here.
Register-ArgumentCompleter -Native -CommandName nova -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $tokens = $commandAst.CommandElements | ForEach-Object { $_.ToString() }
    $cmds = 'encode', 'decode', 'preview', 'info', 'bench', 'version'

    $result = if ($tokens.Count -le 2) {
        $cmds + '--version'
    } else {
        $sub = $tokens[1]
        $prev = $tokens[-2]
        switch ($prev) {
            '-m' { if ($sub -eq 'encode') { 'adaptive', 'lossless', 'lossy' } else { 'lossy', 'lossless' } }
            '-l' { '0', '1', '2', '3', '4', '5' }
            '-look' { 'canon', 'darktable' }
            default {
                if ($wordToComplete -like '-*') {
                    switch ($sub) {
                        'encode' { '-m', '-l', '-q', '-e', '-d', '-live' }
                        'decode' { '-q', '-m', '-fast', '-hdr', '-look' }
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
