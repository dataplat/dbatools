function Enable-DbaStartupProcedure {
    <#
    .SYNOPSIS
        Sets a procedure to execute automatically each time the SQL Server service is started

    .DESCRIPTION
         Used to designate one or more stored procedures to automatically execute when the SQL Server service is started.
         Equivalent to running the system stored procedure sp_procoption with @OptionValue = on
         Returns the SMO StoredProcedure object for procedures affected.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER StartupProcedure
        The Procedure(s) to process.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: Procedure, Startup, StartupProcedure
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Enable-DbaStartupProcedure

    .EXAMPLE
        PS C:\> Enable-DbaStartupProcedure -SqlInstance SqlBox1\Instance2 -StartupProcedure '[dbo].[StartUpProc1]'

        Attempts to set the procedure '[dbo].[StartUpProc1]' in the master database of SqlBox1\Instance2 for automatic execution when the instance is started.

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Enable-DbaStartupProcedure -SqlInstance winserver\sqlexpress, sql2016 -SqlCredential $cred -StartupProcedure '[dbo].[StartUpProc1]'

        Attempts to set the procedure '[dbo].[StartUpProc1]' in the master database of winserver\sqlexpress and sql2016 for automatic execution when the instance is started. Connects using sqladmin credential

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$StartupProcedure,
        [switch]$EnableException
    )
    begin {
        $action = 'Enable'
        $startup = $true
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $server -Continue
            }
            Write-Message -Level Verbose -Message "Getting startup procedures for $instance"

            $db = $server.Databases['master']

            foreach ($proc in $StartupProcedure) {
                Write-Message -Level Verbose -Message "Preparing to get object parts for $proc"
                $procParts = Get-ObjectNameParts $proc

                if ($procParts.Parsed) {
                    $sp = $db.StoredProcedures.Item($procParts.Name, $procParts.Schema)

                    if ($null -eq $sp) {
                        Stop-Function -Message "Requested procedure $proc does not exist." -Continue -Target $server -Category InvalidData
                    } else {
                        try {
                            if ($sp.Startup -eq $startup) {
                                Write-Message -Level Verbose -Message "No work being performed. Startup property already $startup"
                                $status = $false
                                $note = "Action $action already performed"
                            } else {
                                if ($Pscmdlet.ShouldProcess("$instance", "Setting Startup status of $proc to $startup")) {
                                    $sp.Startup = $startup
                                    $sp.Alter()
                                    $status = $true
                                    $note = "$action succeded"
                                } else {
                                    $status = $false
                                    $note = "$action skipped"
                                }
                            }

                        } catch {
                            $status = $false
                            $note = "$action failed"
                        }
                    }

                } else {
                    Stop-Function -Message "Requested procedure $proc could not be parsed." -Continue -Target $server -Category InvalidData
                }

                Add-Member -Force -InputObject $sp -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                Add-Member -Force -InputObject $sp -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $sp -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                Add-Member -Force -InputObject $sp -MemberType NoteProperty -Name Database -value $db.Name
                Add-Member -Force -InputObject $sp -MemberType NoteProperty -Name Action -value $action
                Add-Member -Force -InputObject $sp -MemberType NoteProperty -Name Status -value $status
                Add-Member -Force -InputObject $sp -MemberType NoteProperty -Name Note -value $note

                $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Schema', 'Name', 'Startup', 'Action', 'Status', 'Note'
                Select-DefaultView -InputObject $sp -Property $defaults
            }
        }
    }
}