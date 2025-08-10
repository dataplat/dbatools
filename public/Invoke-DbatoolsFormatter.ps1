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
                [string]$ModifiedContent
            )

            # Normalize line endings to Unix style for comparison
            $originalNormalized = $OriginalContent -replace '\r\n', "`n" -replace '\r', "`n"
            $modifiedNormalized = $ModifiedContent -replace '\r\n', "`n" -replace '\r', "`n"

            # Split into lines
            $originalLines = $originalNormalized -split "`n"
            $modifiedLines = $modifiedNormalized -split "`n"

            # Normalize each line: trim trailing whitespace and convert tabs to spaces
            $originalLines = $originalLines | ForEach-Object { $_.TrimEnd().Replace("`t", "    ") }
            $modifiedLines = $modifiedLines | ForEach-Object { $_.TrimEnd().Replace("`t", "    ") }

            # Remove trailing empty lines from both
            while ($originalLines.Count -gt 0 -and $originalLines[-1] -eq '') {
                $originalLines = $originalLines[0..($originalLines.Count - 2)]
            }
            while ($modifiedLines.Count -gt 0 -and $modifiedLines[-1] -eq '') {
                $modifiedLines = $modifiedLines[0..($modifiedLines.Count - 2)]
            }

            # Compare the normalized content
            if ($originalLines.Count -ne $modifiedLines.Count) {
                return $false
            }

            for ($i = 0; $i -lt $originalLines.Count; $i++) {
                if ($originalLines[$i] -ne $modifiedLines[$i]) {
                    return $false
                }
            }

            return $true
        }

        function Format-ScriptContent {
            param(
                [string]$Content,
                [string]$LineEnding
            )

            # Strip ending empty lines
            $Content = $Content -replace "(?s)$LineEnding\s*$"

            try {
                # Save original lines before formatting
                $originalLines = $Content -split "`n"

                # Run the formatter
                $formattedContent = Invoke-Formatter -ScriptDefinition $Content -Settings CodeFormattingOTBS -ErrorAction Stop

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
                $Content = $formattedLines -join "`n"
            } catch {
                Write-Message -Level Warning "Unable to format content"
            }

            # Match the ending indentation of CBH with the starting one
            $CBH = $CBHRex.Match($Content).Value
            if ($CBH) {
                $startSpaces = $CBHStartRex.Match($CBH).Groups['spaces']
                if ($startSpaces) {
                    $newCBH = $CBHEndRex.Replace($CBH, "$startSpaces#>")
                    if ($newCBH) {
                        $Content = $Content.Replace($CBH, $newCBH)
                    }
                }
            }

            # Apply case corrections and clean up lines
            $correctCase = @('DbaInstanceParameter', 'PSCredential', 'PSCustomObject', 'PSItem')
            $realContent = @()
            foreach ($line in $Content.Split("`n")) {
                foreach ($item in $correctCase) {
                    $line = $line -replace $item, $item
                }
                $realContent += $line.Replace("`t", "    ").TrimEnd()
            }

            return ($realContent -Join $LineEnding)
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        # Collect all paths from pipeline
        $allPaths += $Path
    }
    end {
        if (Test-FunctionInterrupt) { return }

        $totalFiles = $allPaths.Count
        $currentFile = 0
        $processedFiles = 0
        $updatedFiles = 0

        foreach ($p in $allPaths) {
            $currentFile++

            try {
                $realPath = (Resolve-Path -Path $p -ErrorAction Stop).Path
            } catch {
                Write-Progress -Activity "Formatting PowerShell files" -Status "Error resolving path: $p" -PercentComplete (($currentFile / $totalFiles) * 100) -CurrentOperation "File $currentFile of $totalFiles"
                Stop-Function -Message "Cannot find or resolve $p" -Continue
                continue
            }

            # Read file once
            $originalBytes = [System.IO.File]::ReadAllBytes($realPath)
            $originalContent = [System.IO.File]::ReadAllText($realPath)

            # Detect line ending style from original file
            $detectedOSEOL = $OSEOL
            if ($psVersionTable.Platform -ne 'Unix') {
                # We're on Windows, check if file uses Unix endings
                $containsCR = ($originalContent -split "`r").Length -gt 1
                if (-not($containsCR)) {
                    $detectedOSEOL = "`n"
                }
            }

            # Format the content
            $formattedContent = Format-ScriptContent -Content $originalContent -LineEnding $detectedOSEOL

            # If SkipInvisibleOnly is set, check if formatting would only change invisible characters
            if ($SkipInvisibleOnly) {
                if (Test-OnlyInvisibleChanges -OriginalContent $originalContent -ModifiedContent $formattedContent) {
                    Write-Verbose "Skipping $realPath - only invisible changes (BOM/line endings/whitespace)"
                    continue
                }
            }

            # Save the formatted content
            $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
            [System.IO.File]::WriteAllText($realPath, $formattedContent, $Utf8NoBomEncoding)
        }
    }
}