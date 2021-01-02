function Disable-DbaStartupProcedure {
    <#
    .SYNOPSIS
        Disables the automatic execution of procedure(s) that are set to execute automatically each time the SQL Server service is started

    .DESCRIPTION
         Used to revoke the designation of one or more stored procedures to automatically execute when the SQL Server service is started.
         Equivalent to running the system stored procedure sp_procoption with @OptionValue = off
         Returns the SMO StoredProcedure object for procedures affected.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER StartupProcedure
        The Procedure(s) to process.

   .PARAMETER InputObject
        Piped objects from Get-DbaStartup

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
        https://dbatools.io/Disable-DbaStartupProcedure

    .EXAMPLE
        PS C:\> Disable-DbaStartupProcedure -SqlInstance SqlBox1\Instance2 -StartupProcedure '[dbo].[StartUpProc1]'

        Attempts to clear the automatic execution of the procedure '[dbo].[StartUpProc1]' in the master database of SqlBox1\Instance2 when the instance is started.

  .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Disable-DbaStartupProcedure -SqlInstance winserver\sqlexpress, sql2016 -SqlCredential $cred -StartupProcedure '[dbo].[StartUpProc1]'

        Attempts to clear the automatic execution of the procedure '[dbo].[StartUpProc1]' in the master database of winserver\sqlexpress and sql2016 when the instance is started. Connects using sqladmin credential

  .EXAMPLE
        PS C:\> Get-DbaStartupProcedure -SqlInstance sql2016 | Disable-DbaStartupProcedure

        Get all startup procedures for the sql2016 instance and disables them by piping to Disable-DbaStartupProcedure

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$StartupProcedure,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        $action = 'Disable'
        $startup = $false
    }

    process {
        if (Test-Bound -ParameterName InputObject -Not) {
            if (Test-Bound -ParameterName SqlInstance) {
                if ((Test-Bound -Not -ParameterName StartupProcedure)) {
                    Stop-Function -Message "You must specify one or more Startup Procedures when using the SqlInstance parameter."
                    return
                }
            } else {
                Stop-Function -Message "You must supply either a SqlInstance or an InputObject ."
                return
            }

            foreach ($instance in $SqlInstance) {
                Write-Message -Level Verbose -Message "Getting startup procedures for $instance"
                try {
                    $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $server -Continue
                }
                $db = $server.Databases['master']

                foreach ($proc in $StartupProcedure) {
                    $procParts = Get-ObjectNameParts $proc
                    if ($procParts.Parsed) {
                        $sp = $db.StoredProcedures.Item($procParts.Name, $procParts.Schema)
                        if ($null -eq $sp) {
                            Stop-Function -Message "Requested procedure $proc does not exist." -Continue -Target $server -Category InvalidData
                        } else {
                            Write-Message -Level Verbose -Message "Adding $($procParts.Name) $($procParts.Schema) for $instance"
                            $InputObject += $sp
                        }
                    } else {
                        Stop-Function -Message "Requested procedure $proc could not be parsed." -Continue -Target $server -Category InvalidData
                    }
                }
            }
        }

        foreach ($sp in $InputObject) {
            $db = $sp.Parent
            $server = $db.Parent

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