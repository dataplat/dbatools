#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Revoke-DbaAgPermission {
    <#
    .SYNOPSIS
        Revokes endpoint and availability group permissions to a login.

    .DESCRIPTION
        Revokes endpoint and availability group permissions to a login.

   .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the SqlInstance instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Login
        The login or logins to modify.
    
    .PARAMETER AvailabilityGroup
        Only modify specific availability groups.

    .PARAMETER Type
        Specify type: Endpoint or AvailabilityGroup. Endpoint will modify the DatabaseMirror endpoint type.

    .PARAMETER Permission
        Revokes one or more permissions:
            Alter
            Connect
            Control
            CreateAnyDatabase
            CreateSequence
            Delete
            Execute
            Impersonate
            Insert
            Receive
            References
            Select
            Send
            TakeOwnership
            Update
            ViewChangeTracking
            ViewDefinition

        Connect is default.

    .PARAMETER InputObject
        Enables piping from Get-DbaLogin.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AvailabilityGroup, HA, AG
        Author: Chrissy LeMaire (@cl), netnerds.net
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Revoke-DbaAgPermission

    .EXAMPLE
        PS C:\> Revoke-DbaAgPermission -SqlInstance sql2017a -Type AvailabilityGroup -AvailabilityGroup SharePoint -Login ad\spservice -Permission CreateAnyDatabase

        Removes CreateAnyDatabase permissions from ad\spservice on the SharePoint availability group on sql2017a. Does not prompt for confirmation.

    .EXAMPLE
        PS C:\> Revoke-DbaAgPermission -SqlInstance sql2017a -Type AvailabilityGroup -AvailabilityGroup ag1, ag2 -Login ad\spservice -Permission CreateAnyDatabase -Confirm

        Removes CreateAnyDatabase permissions from ad\spservice on the ag1 and ag2 availability groups on sql2017a. Prompts for confirmation.

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2017a | Out-GridView -Passthru | Revoke-DbaAgPermission -Type EndPoint

        Revokes the selected logins Connect permissions on the DatabaseMirroring endpoint for sql2017a.
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Login,
        [string[]]$AvailabilityGroup,
        [parameter(Mandatory)]
        [ValidateSet('Endpoint', 'AvailabilityGroup')]
        [string[]]$Type,
        [ValidateSet('Alter', 'Connect', 'Control', 'CreateAnyDatabase', 'CreateSequence', 'Delete', 'Execute', 'Impersonate', 'Insert', 'Receive', 'References', 'Select', 'Send', 'TakeOwnership', 'Update', 'ViewChangeTracking', 'ViewDefinition')]
        [string[]]$Permission = "Connect",
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Login[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance -and -not $Login) {
            Stop-Function -Message "You must specify one or more logins when using the SqlInstance parameter."
            return
        }
        
        if ($Type -contains "AvailabilityGroup" -and -not $AvailabilityGroup) {
            Stop-Function -Message "You must specify at least one availability group when using the AvailabilityGroup type."
            return
        }
        
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaLogin -SqlInstance $instance -SqlCredential $SqlCredential -Login $Login
            foreach ($account in $Login) {
                if ($account -notin $InputObject.Name) {
                    Stop-Function -Message "$account does not exist on $instance" -Target $instance -Continue
                }
            }
        }
        
        foreach ($account in $InputObject) {
            $server = $account.Parent
            if ($Type -contains "Endpoint") {
                $endpoint = Get-DbaEndpoint -SqlInstance $server -Type DatabaseMirroring
                if (-not $endpoint) {
                    Stop-Function -Message "DatabaseMirroring endpoint does not exist on $server" -Target $server -Continue
                }
                
                foreach ($perm in $Permission) {
                    if ($Pscmdlet.ShouldProcess($server.Name, "Revoking $perm on $endpoint")) {
                        if ($perm -eq "CreateAnyDatabase") {
                            $ag.Parent.Query("ALTER AVAILABILITY GROUP $ag REVOKE CREATE ANY DATABASE")
                        } else {
                            $bigperms = New-Object Microsoft.SqlServer.Management.Smo.ObjectPermissionSet([Microsoft.SqlServer.Management.Smo.ObjectPermission]::$perm)
                            try {
                                $endpoint.Revoke($bigperms, $account.Name)
                                [pscustomobject]@{
                                    ComputerName = $account.ComputerName
                                    InstanceName = $account.InstanceName
                                    SqlInstance  = $account.SqlInstance
                                    Name         = $account.Name
                                    Permission   = $perm
                                    Type         = "Revoke"
                                    Status       = "Success"
                                }
                            } catch {
                                Stop-Function -Message "Failure" -ErrorRecord $_
                            }
                        }
                    }
                }
            }
            
            if ($Type -contains "AvailabilityGroup") {
                $ags = Get-DbaAvailabilityGroup -SqlInstance $account.Parent -AvailabilityGroup $AvailabilityGroup
                foreach ($ag in $ags) {
                    foreach ($perm in $Permission) {
                        if ($perm -notin 'Alter', 'Control', 'TakeOwnership', 'ViewDefinition') {
                            Stop-Function -Message "$perm not supported by availability groups" -Continue
                        }
                        if ($Pscmdlet.ShouldProcess($server.Name, "Revoking $perm on $ags")) {
                            try {
                                $bigperms = New-Object Microsoft.SqlServer.Management.Smo.ObjectPermissionSet([Microsoft.SqlServer.Management.Smo.ObjectPermission]::$perm)
                                $ag.Revoke($bigperms, $account.Name)
                                [pscustomobject]@{
                                    ComputerName = $account.ComputerName
                                    InstanceName = $account.InstanceName
                                    SqlInstance  = $account.SqlInstance
                                    Name         = $account.Name
                                    Permission   = $perm
                                    Type         = "Revoke"
                                    Status       = "Success"
                                }
                            } catch {
                                Stop-Function -Message "Failure" -ErrorRecord $_
                            }
                        }
                    }
                }
            }
        }
    }
}

