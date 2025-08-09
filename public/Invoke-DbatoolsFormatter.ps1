function Invoke-DbatoolsFormatter {
    <#
    .SYNOPSIS
        Helps formatting function files to dbatools' standards

    .DESCRIPTION
        Uses PSSA's Invoke-Formatter to format the target files and saves it without the BOM.

    .PARAMETER Path
        The path to the ps1 file that needs to be formatted

    .PARAMETER SkipInvisibleOnly
        Skip files that would only have invisible changes (BOM, line endings, trailing whitespace, tabs).
        Use this to avoid unnecessary version control noise when only non-visible characters would change.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Module, Support
        Author: Simone Bizzotto

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbatoolsFormatter

    .EXAMPLE
        PS C:\> Invoke-DbatoolsFormatter -Path C:\dbatools\public\Get-DbaDatabase.ps1

        Reformats C:\dbatools\public\Get-DbaDatabase.ps1 to dbatools' standards

    .EXAMPLE
        PS C:\> Invoke-DbatoolsFormatter -Path C:\dbatools\public\*.ps1 -SkipInvisibleOnly

        Reformats all ps1 files but skips those that would only have BOM/line ending changes
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [object[]]$Path,
        [switch]$SkipInvisibleOnly,
        [switch]$EnableException
    )
    begin {
        $invokeFormatterVersion = (Get-Command Invoke-Formatter -ErrorAction SilentlyContinue).Version
        $HasInvokeFormatter = $null -ne $invokeFormatterVersion
        $ScriptAnalyzerCorrectVersion = '1.18.2'
        if (!($HasInvokeFormatter)) {
            Stop-Function -Message "You need PSScriptAnalyzer version $ScriptAnalyzerCorrectVersion installed"
            Write-Message -Level Warning "     Install-Module -Name PSScriptAnalyzer -RequiredVersion '$ScriptAnalyzerCorrectVersion'"
        } else {
            if ($invokeFormatterVersion -ne $ScriptAnalyzerCorrectVersion) {
                Remove-Module PSScriptAnalyzer
                try {
                    Import-Module PSScriptAnalyzer -RequiredVersion $ScriptAnalyzerCorrectVersion -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Please install PSScriptAnalyzer $ScriptAnalyzerCorrectVersion"
                    Write-Message -Level Warning "     Install-Module -Name PSScriptAnalyzer -RequiredVersion '$ScriptAnalyzerCorrectVersion'"
                }
            }
        }
        $CBHRex = [regex]'(?smi)\s+\<\#[^#]*\#\>'
        $CBHStartRex = [regex]'(?<spaces>[ ]+)\<\#'
        $CBHEndRex = [regex]'(?<spaces>[ ]*)\#\>'
        $OSEOL = "`n"
        if ($psVersionTable.Platform -ne 'Unix') {
            $OSEOL = "`r`n"
        }

        function Test-OnlyInvisibleChanges {
            param(
                [string]$OriginalContent,
                [string]$ModifiedContent,
                [byte[]]$OriginalBytes,
                [byte[]]$ModifiedBytes
            )

            # Check for BOM
            $originalHasBOM = $OriginalBytes.Length -ge 3 -and
            $OriginalBytes[0] -eq 0xEF -and
            $OriginalBytes[1] -eq 0xBB -and
            $OriginalBytes[2] -eq 0xBF

            $modifiedHasBOM = $ModifiedBytes.Length -ge 3 -and
            $ModifiedBytes[0] -eq 0xEF -and
            $ModifiedBytes[1] -eq 0xBB -and
            $ModifiedBytes[2] -eq 0xBF

            # Normalize content for comparison (remove all formatting differences)
            $originalLines = $OriginalContent -split '\r?\n'
            $modifiedLines = $ModifiedContent -split '\r?\n'

            # Strip trailing whitespace and normalize tabs
            $originalNormalized = $originalLines | ForEach-Object {
                $_.TrimEnd().Replace("`t", "    ")
            }
            $modifiedNormalized = $modifiedLines | ForEach-Object {
                $_.TrimEnd().Replace("`t", "    ")
            }

            # Also account for trailing empty lines being removed
            $originalNormalized = ($originalNormalized -join "`n") -replace '(?s)\n\s*$', ''
            $modifiedNormalized = ($modifiedNormalized -join "`n") -replace '(?s)\n\s*$', ''

            # If normalized content is identical, only invisible changes occurred
            return ($originalNormalized -eq $modifiedNormalized)
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($p in $Path) {
            try {
                $realPath = (Resolve-Path -Path $p -ErrorAction Stop).Path
            } catch {
                Stop-Function -Message "Cannot find or resolve $p" -Continue
            }

            # If SkipInvisibleOnly is set, check if formatting would only change invisible characters
            if ($SkipInvisibleOnly) {
                # Save original state
                $originalBytes = [System.IO.File]::ReadAllBytes($realPath)
                $originalContent = [System.IO.File]::ReadAllText($realPath)

                # Create a copy to test formatting
                $tempContent = $originalContent
                $tempOSEOL = $OSEOL

                if ($tempOSEOL -eq "`r`n") {
                    $containsCR = ($tempContent -split "`r").Length -gt 1
                    if (-not($containsCR)) {
                        $tempOSEOL = "`n"
                    }
                }

                # Apply all formatting transformations
                $tempContent = $tempContent -replace "(?s)$tempOSEOL\s*$"
                try {
                    $tempContent = Invoke-Formatter -ScriptDefinition $tempContent -Settings CodeFormattingOTBS -ErrorAction Stop
                } catch {
                    # If formatter fails, continue with original content
                }

                # Apply CBH fixes
                $CBH = $CBHRex.Match($tempContent).Value
                if ($CBH) {
                    $startSpaces = $CBHStartRex.Match($CBH).Groups['spaces']
                    if ($startSpaces) {
                        $newCBH = $CBHEndRex.Replace($CBH, "$startSpaces#>")
                        if ($newCBH) {
                            $tempContent = $tempContent.Replace($CBH, $newCBH)
                        }
                    }
                }

                # Apply case corrections and whitespace trimming
                $correctCase = @('DbaInstanceParameter', 'PSCredential', 'PSCustomObject', 'PSItem')
                $tempLines = @()
                foreach ($line in $tempContent.Split("`n")) {
                    foreach ($item in $correctCase) {
                        $line = $line -replace $item, $item
                    }
                    $tempLines += $line.Replace("`t", "    ").TrimEnd()
                }
                $formattedContent = $tempLines -Join "$tempOSEOL"

                # Create bytes as if we were saving (UTF8 no BOM)
                $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
                $modifiedBytes = $Utf8NoBomEncoding.GetBytes($formattedContent)

                # Test if only invisible changes would occur
                $testParams = @{
                    OriginalContent = $originalContent
                    ModifiedContent = $formattedContent
                    OriginalBytes   = $originalBytes
                    ModifiedBytes   = $modifiedBytes
                }

                if (Test-OnlyInvisibleChanges @testParams) {
                    Write-Verbose "Skipping $realPath - only invisible changes (BOM/line endings/whitespace)"
                    continue
                }
            }

            # Proceed with normal formatting
            $content = Get-Content -Path $realPath -Raw -Encoding UTF8
            if ($OSEOL -eq "`r`n") {
                # See #5830, we are in Windows territory here
                # Is the file containing at least one `r ?
                $containsCR = ($content -split "`r").Length -gt 1
                if (-not($containsCR)) {
                    # If not, maybe even on Windows the user is using Unix-style endings, which are supported
                    $OSEOL = "`n"
                }
            }

            #strip ending empty lines
            $content = $content -replace "(?s)$OSEOL\s*$"
            try {
                # Save original lines before formatting
                $originalLines = $content -split "`n"

                # Run the formatter
                $formattedContent = Invoke-Formatter -ScriptDefinition $content -Settings CodeFormattingOTBS -ErrorAction Stop

                # Automatically restore spaces before = signs
                $formattedLines = $formattedContent -split "`n"
                for ($i = 0; $i -lt $formattedLines.Count; $i++) {
                    if ($i -lt $originalLines.Count) {
                        # Check if original had multiple spaces before =
                        if ($originalLines[$i] -match '^(\s*)(.+?)(\s{2,})(=)(.*)$') {
                            $indent = $matches[1]
                            $beforeEquals = $matches[2]
                            $spacesBeforeEquals = $matches[3]
                            $rest = $matches[4] + $matches[5]

                            # Apply the same spacing to the formatted line
                            if ($formattedLines[$i] -match '^(\s*)(.+?)(\s*)(=)(.*)$') {
                                $formattedLines[$i] = $matches[1] + $matches[2] + $spacesBeforeEquals + '=' + $matches[5]
                            }
                        }
                    }
                }
                $content = $formattedLines -join "`n"
            } catch {
                Write-Message -Level Warning "Unable to format $p"
            }
            #match the ending indentation of CBH with the starting one, see #4373
            $CBH = $CBHRex.Match($content).Value
            if ($CBH) {
                #get starting spaces
                $startSpaces = $CBHStartRex.Match($CBH).Groups['spaces']
                if ($startSpaces) {
                    #get end
                    $newCBH = $CBHEndRex.Replace($CBH, "$startSpaces#>")
                    if ($newCBH) {
                        #replace the CBH
                        $content = $content.Replace($CBH, $newCBH)
                    }
                }
            }
            $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
            $correctCase = @(
                'DbaInstanceParameter'
                'PSCredential'
                'PSCustomObject'
                'PSItem'
            )
            $realContent = @()
            foreach ($line in $content.Split("`n")) {
                foreach ($item in $correctCase) {
                    $line = $line -replace $item, $item
                }
                #trim whitespace lines
                $realContent += $line.Replace("`t", "    ").TrimEnd()
            }
            [System.IO.File]::WriteAllText($realPath, ($realContent -Join "$OSEOL"), $Utf8NoBomEncoding)
        }
    }
}