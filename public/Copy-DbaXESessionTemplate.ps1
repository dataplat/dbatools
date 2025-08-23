function Copy-DbaXESessionTemplate {
    <#
    .SYNOPSIS
        Copies Extended Event session templates from dbatools repository to SSMS template directory for GUI access.

    .DESCRIPTION
        Installs curated Extended Event session templates into SQL Server Management Studio's template directory so you can access them through the SSMS GUI.
        The templates include common monitoring scenarios like deadlock detection, query performance tracking, connection monitoring, and database health checks.
        Only copies non-Microsoft templates, preserving any custom templates already in your SSMS directory while adding the community-contributed ones from the dbatools collection.

    .PARAMETER Path
        Specifies the directory containing Extended Event session template files to copy from. Defaults to the dbatools template repository (/bin/XEtemplates/).
        Use this when you want to copy templates from a custom directory instead of the built-in dbatools collection, such as organization-specific templates or downloaded templates from other sources.

    .PARAMETER Destination
        Specifies the target directory where Extended Event templates will be installed for SSMS access. Defaults to $home\Documents\SQL Server Management Studio\Templates\XEventTemplates.
        Use this when you need to install templates to a different SSMS profile or custom template location, such as when SSMS is installed in a non-standard directory or for shared template repositories.

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

        Copies non-Microsoft templates from the dbatools template repository (/bin/XEtemplates/) to $home\Documents\SQL Server Management Studio\Templates\XEventTemplates.

    .EXAMPLE
        PS C:\> Copy-DbaXESessionTemplate -Path C:\temp\XEtemplates

        Copies your templates from C:\temp\XEtemplates to $home\Documents\SQL Server Management Studio\Templates\XEventTemplates.

    #>
    [CmdletBinding()]
    param (
        [string[]]$Path = "$script:PSModuleRoot\bin\XEtemplates",
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