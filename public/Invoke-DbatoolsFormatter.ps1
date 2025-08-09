function Invoke-DbatoolsFormatter {
    <#
    .SYNOPSIS
        Helps formatting function files to dbatools' standards

    .DESCRIPTION
        Uses PSSA's Invoke-Formatter to format the target files and saves it without the BOM.
        Preserves manually aligned hashtables and assignment operators.
        Only writes files if formatting changes are detected.

    .PARAMETER Path
        The path to the ps1 file that needs to be formatted

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
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [object[]]$Path,
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

        # Create custom formatter settings that preserve alignment
        $customSettings = @{
            IncludeRules = @(
                'PSPlaceOpenBrace',
                'PSPlaceCloseBrace',
                'PSUseConsistentIndentation',
                'PSUseConsistentWhitespace'
            )
            Rules        = @{
                PSPlaceOpenBrace           = @{
                    Enable             = $true
                    OnSameLine         = $true
                    NewLineAfter       = $true
                    IgnoreOneLineBlock = $true
                }
                PSPlaceCloseBrace          = @{
                    Enable             = $true
                    NewLineAfter       = $false
                    IgnoreOneLineBlock = $true
                    NoEmptyLineBefore  = $false
                }
                PSUseConsistentIndentation = @{
                    Enable              = $true
                    Kind                = 'space'
                    PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
                    IndentationSize     = 4
                }
                PSUseConsistentWhitespace  = @{
                    Enable                          = $true
                    CheckInnerBrace                 = $true
                    CheckOpenBrace                  = $true
                    CheckOpenParen                  = $true
                    CheckOperator                   = $false  # This is key - don't mess with operator spacing
                    CheckPipe                       = $true
                    CheckPipeForRedundantWhitespace = $false
                    CheckSeparator                  = $true
                    CheckParameter                  = $false
                }
            }
        }

        $OSEOL = "`n"
        if ($psVersionTable.Platform -ne 'Unix') {
            $OSEOL = "`r`n"
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

            # Skip directories and non-PowerShell files
            if (Test-Path -Path $realPath -PathType Container) {
                Write-Message -Level Verbose "Skipping directory: $realPath"
                continue
            }

            if ($realPath -notmatch '\.ps1$|\.psm1$|\.psd1$') {
                Write-Message -Level Verbose "Skipping non-PowerShell file: $realPath"
                continue
            }

            try {
                $originalContent = Get-Content -Path $realPath -Raw -Encoding UTF8
            } catch {
                Stop-Function -Message "Unable to read file $realPath : $($_.Exception.Message)" -Continue
            }

            # If Get-Content failed, originalContent might be null or empty
            if (-not $originalContent) {
                Write-Message -Level Verbose "Skipping empty or unreadable file: $realPath"
                continue
            }

            $content = $originalContent

            if ($OSEOL -eq "`r`n") {
                # See #5830, we are in Windows territory here
                # Is the file containing at least one `r ?
                $containsCR = ($content -split "`r").Length -gt 1
                if (-not($containsCR)) {
                    # If not, maybe even on Windows the user is using Unix-style endings, which are supported
                    $OSEOL = "`n"
                }
            }

            # Strip ending empty lines from both original and working content
            $content = $content -replace "(?s)$OSEOL\s*$"
            $originalStripped = $originalContent -replace "(?s)$OSEOL\s*$"

            try {
                # Format the content
                $content = Invoke-Formatter -ScriptDefinition $content -Settings $customSettings -ErrorAction Stop
                # Also format the original to compare
                $originalFormatted = Invoke-Formatter -ScriptDefinition $originalStripped -Settings $customSettings -ErrorAction Stop
            } catch {
                Write-Message -Level Warning "Unable to format $realPath : $($_.Exception.Message)"
                continue
            }

            # Ensure both contents are strings before processing
            if (-not $content -or $content -isnot [string]) {
                Write-Message -Level Warning "Formatter returned unexpected content type for $realPath"
                continue
            }

            if (-not $originalFormatted -or $originalFormatted -isnot [string]) {
                Write-Message -Level Warning "Formatter returned unexpected content type for original in $realPath"
                continue
            }

            # Apply CBH fix to formatted content
            $CBH = $CBHRex.Match($content).Value
            if ($CBH) {
                $startSpaces = $CBHStartRex.Match($CBH).Groups['spaces']
                if ($startSpaces) {
                    $newCBH = $CBHEndRex.Replace($CBH, "$startSpaces#>")
                    if ($newCBH) {
                        $content = $content.Replace($CBH, $newCBH)
                    }
                }
            }

            # Apply CBH fix to original formatted content
            $originalCBH = $CBHRex.Match($originalFormatted).Value
            if ($originalCBH) {
                $startSpaces = $CBHStartRex.Match($originalCBH).Groups['spaces']
                if ($startSpaces) {
                    $newOriginalCBH = $CBHEndRex.Replace($originalCBH, "$startSpaces#>")
                    if ($newOriginalCBH) {
                        $originalFormatted = $originalFormatted.Replace($originalCBH, $newOriginalCBH)
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

            # Process the formatted content
            $realContent = @()
            foreach ($line in $content.Split("`n")) {
                foreach ($item in $correctCase) {
                    $line = $line -replace $item, $item
                }
                $realContent += $line.Replace("`t", "    ").TrimEnd()
            }
            $finalContent = $realContent -Join "$OSEOL"

            # Process the original formatted content the same way
            $originalProcessed = @()
            foreach ($line in $originalFormatted.Split("`n")) {
                foreach ($item in $correctCase) {
                    $line = $line -replace $item, $item
                }
                $originalProcessed += $line.Replace("`t", "    ").TrimEnd()
            }
            $originalFinalContent = $originalProcessed -Join "$OSEOL"

            # Only write the file if there are actual changes
            if ($finalContent -ne $originalFinalContent) {
                try {
                    Write-Message -Level Verbose "Formatting changes detected in $realPath"
                    [System.IO.File]::WriteAllText($realPath, $finalContent, $Utf8NoBomEncoding)
                } catch {
                    Stop-Function -Message "Unable to write file $realPath : $($_.Exception.Message)" -Continue
                }
            } else {
                Write-Message -Level Verbose "No formatting changes needed for $realPath"
            }
        }
    }
}