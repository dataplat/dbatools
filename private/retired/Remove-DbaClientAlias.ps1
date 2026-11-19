function Remove-DbaClientAlias {
    <#
    .SYNOPSIS
        Removes SQL Server client aliases from Windows registry on local or remote computers

    .DESCRIPTION
        Removes SQL Server client aliases from the Windows registry by deleting entries from both 32-bit and 64-bit registry locations.
        Client aliases redirect SQL Server connection requests to different servers or instances, but outdated or incorrect aliases can cause connection failures.
        This function provides a programmatic way to clean up these aliases when the deprecated cliconfg.exe utility is not available or when managing multiple computers remotely.
        Commonly used when decommissioning servers, updating connection strings, or troubleshooting connectivity issues caused by stale alias configurations.

    .PARAMETER ComputerName
        Specifies the target computer(s) where SQL Server client aliases will be removed from the Windows registry.
        Use this when you need to clean up aliases on remote workstations or application servers.
        Defaults to the local computer if not specified.

    .PARAMETER Credential
        Allows you to login to remote computers using alternative credentials

    .PARAMETER Alias
        Specifies the SQL Server client alias name(s) to remove from both 32-bit and 64-bit registry locations.
        Use this to clean up outdated aliases that redirect connections to decommissioned servers or incorrect instances.
        Accepts multiple alias names for bulk cleanup operations.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Returns one object per alias that was successfully removed from the registry.

        Properties:
        - ComputerName: The name of the computer where the alias was removed
        - Architecture: Registry architecture where the alias was removed ("32-bit" or "64-bit")
        - Alias: The name of the SQL Server client alias that was removed
        - Status: The result status, typically "Removed" when successful

    .NOTES
        Tags: SqlClient, Alias
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaClientAlias

    .EXAMPLE
        PS C:\> Remove-DbaClientAlias -ComputerName workstationX -Alias sqlps

        Removes the sqlps SQL Client alias on workstationX

    .EXAMPLE
        PS C:\> Get-DbaClientAlias | Remove-DbaClientAlias

        Removes all SQL Server client aliases on the local computer
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('AliasName')]
        [string[]]$Alias,
        [switch]$EnableException
    )
    begin {
        $scriptBlock = {
            $Alias = $args

            $basekeys = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\MSSQLServer", "HKLM:\SOFTWARE\Microsoft\MSSQLServer"

            foreach ($basekey in $basekeys) {
                $fullKey = "$basekey\Client\ConnectTo"
                if ((Test-Path $fullKey) -eq $false) {
                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Warning "Registry key ($fullKey) does not exist on $env:COMPUTERNAME"
                    continue
                }

                if ($basekey -like "*WOW64*") {
                    $architecture = "32-bit"
                } else {
                    $architecture = "64-bit"
                }

                $all = Get-Item -Path $fullKey
                foreach ($entry in $all) {
                    $e = $entry.ToString().Replace('HKEY_LOCAL_MACHINE', 'HKLM:\')
                    foreach ($a in $Alias) {
                        if ($entry.Property -contains $a) {
                            $null = Remove-ItemProperty -Path $e -Name $a
                            [PSCustomObject]@{
                                ComputerName = $env:COMPUTERNAME
                                Architecture = $architecture
                                Alias        = $a
                                Status       = "Removed"
                            }
                        }
                    }
                }
            }
        }
    }
    process {
        foreach ($computer in $ComputerName) {
            $null = Test-ElevationRequirement -ComputerName $computer -Continue

            if ($PSCmdlet.ShouldProcess("$($Alias -join ', ') on $computer", "Remove aliases")) {
                try {
                    Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $scriptBlock -ErrorAction Stop -Verbose:$false -ArgumentList $Alias
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
                }
            }
        }
    }
}