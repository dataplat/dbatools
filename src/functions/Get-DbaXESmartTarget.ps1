function Get-DbaXESmartTarget {
    <#
    .SYNOPSIS
        Gets an XESmartTarget PowerShell job created by Start-DbaXESmartTarget.

    .DESCRIPTION
        Gets an XESmartTarget PowerShell job created by Start-DbaXESmartTarget.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ExtendedEvent, XE, XEvent
        Author: Chrissy LeMaire (@cl) | SmartTarget by Gianluca Sartori (@spaghettidba)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaXESmartTarget

    .EXAMPLE
        PS C:\> Get-DbaXESmartTarget

        Gets an XESmartTarget PowerShell Job created by Start-DbaXESmartTarget.

    #>
    [CmdletBinding()]
    param (
        [switch]$EnableException
    )
    process {
        try {
            Get-Job | Where-Object Name -Match SmartTarget | Select-Object -Property ID, Name, State
        } catch {
            Stop-Function -Message "Failure" -ErrorRecord $_
        }
    }
}