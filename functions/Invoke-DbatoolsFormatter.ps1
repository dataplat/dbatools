function Invoke-DbatoolsFormatter {
    <#
    .SYNOPSIS
        Helps formatting function files to dbatools' standards

    .DESCRIPTION
        Uses PSSA's Invoke-Formatter to format the target files and saves it without the BOM.

    .PARAMETER Path
        The path to the ps1 file that needs to be formatted

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Formatting
        Author: Simone Bizzotto

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbatoolsFormatter

    .EXAMPLE
        PS C:\> Invoke-DbatoolsFormatter -Path C:\dbatools\functions\Get-DbaDatabase.ps1

        Reformats C:\dbatools\functions\Get-DbaDatabase.ps1 to dbatools' standards

#>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [object[]]$Path,
        [switch]$EnableException
    )
    begin {
        $HasInvokeFormatter = $null -ne (Get-Command Invoke-Formatter -ErrorAction SilentlyContinue).Version
        if (!($HasInvokeFormatter)) {
            Stop-Function -Message "You need a recent version of PSScriptAnalyzer installed"
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($p in $Path) {
            try {
                $realPath = (Resolve-Path -Path $p).Path
            } catch {
                Write-Message -Level Warning "Cannot resolve to $p"
                continue
            }
            $content = Get-Content -Path $realPath -Raw -Encoding UTF8
            #strip ending empty lines
            $content = $content -replace "(?s)`r`n\s*$"
            try {
                $content = Invoke-Formatter -ScriptDefinition $content -Settings CodeFormattingOTBS -ErrorAction Stop
            } catch {
                Write-Message -Level Warning "Unable to format $p"
            }
            $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
            $realContent = @()
            #trim whitespace lines
            foreach ($line in $content) {
                $realContent += $line.TrimEnd()
            }
            [System.IO.File]::WriteAllLines($realPath, $realContent, $Utf8NoBomEncoding)
        }
    }
}
