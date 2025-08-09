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

            $originalContent = Get-Content -Path $realPath -Raw -Encoding UTF8
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

            #strip ending empty lines
            $content = $content -replace "(?s)$OSEOL\s*$"
            try {
                # Use custom settings instead of CodeFormattingOTBS
                $content = Invoke-Formatter -ScriptDefinition $content -Settings $customSettings -ErrorAction Stop
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

            $finalContent = $realContent -Join "$OSEOL"

            # Only write the file if there are actual changes
            if ($finalContent -ne $originalContent) {
                Write-Message -Level Verbose "Formatting changes detected in $realPath"
                [System.IO.File]::WriteAllText($realPath, $finalContent, $Utf8NoBomEncoding)
            } else {
                Write-Message -Level Verbose "No formatting changes needed for $realPath"
            }
        }
    }
}