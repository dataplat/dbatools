function Copy-DbaXESessionTemplate {
    <#
    .SYNOPSIS
        Copies non-Microsoft templates from the dbatools template repository (\bin\xetemplates\) to $home\Documents\SQL Server Management Studio\Templates\XEventTemplates.

    .DESCRIPTION
        Copies non-Microsoft templates from the dbatools template repository (\bin\xetemplates\) to $home\Documents\SQL Server Management Studio\Templates\XEventTemplates.

        Useful for when you want to use the SSMS GUI.

    .PARAMETER Path
        The path to the template directory. Defaults to the dbatools template repository (\bin\xetemplates\).

    .PARAMETER Destination
        Path to the Destination directory, defaults to $home\Documents\SQL Server Management Studio\Templates\XEventTemplates.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ExtendedEvent, XE, XEvent
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Copy-DbaXESessionTemplate

    .EXAMPLE
        PS C:\> Copy-DbaXESessionTemplate

        Copies non-Microsoft templates from the dbatools template repository (\bin\xetemplates\) to $home\Documents\SQL Server Management Studio\Templates\XEventTemplates.

    .EXAMPLE
        PS C:\> Copy-DbaXESessionTemplate -Path C:\temp\xetemplates

        Copies your templates from C:\temp\xetemplates to $home\Documents\SQL Server Management Studio\Templates\XEventTemplates.

    #>
    [CmdletBinding()]
    param (
        [string[]]$Path = "$script:PSModuleRoot\bin\xetemplates",
        [string]$Destination = "$home\Documents\SQL Server Management Studio\Templates\XEventTemplates",
        [switch]$EnableException
    )
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            if (-not (Test-Path -Path $destinstance)) {
                try {
                    $null = New-Item -ItemType Directory -Path $destinstance -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $destinstance
                }
            }
            try {
                $files = (Get-DbaXESessionTemplate -Path $Path | Where-Object Source -ne Microsoft).Path
                foreach ($file in $files) {
                    Write-Message -Level Output -Message "Copying $($file.Name) to $destinstance."
                    Copy-Item -Path $file -Destination $destinstance -ErrorAction Stop
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $path
            }
        }
    }
}