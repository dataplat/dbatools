function Remove-DbaXESmartTarget {
 <#
    .SYNOPSIS
    Removes an XESmartTarget PowerShell Job
    
    .DESCRIPTION
    Removes an XESmartTarget PowerShell Job
    
    .PARAMETER InputObject
    The XESmartTarget job object
    
    .PARAMETER WhatIf
    Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
    Prompts you for confirmation before executing any changing operations within the command.
        
    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
    SmartTarget: by Gianluca Sartori (@spaghettidba)

    .LINK
    https://dbatools.io/Remove-DbaXESmartTarget
    https://github.com/spaghettidba/XESmartTarget/wiki

    .EXAMPLE
    Get-DbaXESmartTarget | Remove-DbaXESmartTarget
    
    Removes all XESmartTarget jobs
    
    .EXAMPLE
    Get-DbaXESmartTarget | Where-Object Id -eq 2 | Remove-DbaXESmartTarget
    
    Removes a specific XESmartTarget job

#>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($Pscmdlet.ShouldProcess("localhost", "Removing job $id")) {
            try {
                $id = $InputObject.Id
                Write-Message -Level Output -Message "Removing job $id, this may take a couple minutes"
                Get-Job -ID $InputObject.Id | Remove-Job -Force
                Write-Message -Level Output -Message "Successfully removed $id"
            }
            catch {
                Stop-Function -Message "Failure" -ErrorRecord $_
            }
        }
    }
}