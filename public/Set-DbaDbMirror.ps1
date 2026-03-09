function Set-DbaDbMirror {
    <#
    .SYNOPSIS
        Configures database mirroring partner, witness, safety level, and operational state settings.

    .DESCRIPTION
        Modifies database mirroring configuration by setting the partner server, witness server, safety level, or changing the mirror state. This function lets you reconfigure existing mirrored databases without manually writing ALTER DATABASE statements. Use it to add or change witness servers for automatic failover, adjust safety levels between synchronous and asynchronous modes, or control mirror states like suspend, resume, and failover operations.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database(s) to configure mirroring settings for. Accepts multiple database names.
        Use this to target specific mirrored databases when you need to modify partner, witness, safety level, or state settings.

    .PARAMETER Partner
        Sets the mirroring partner server endpoint in TCP://servername:port format. This establishes or changes the mirror partnership.
        Use this when setting up initial mirroring or changing the partner server after a configuration change or migration.

    .PARAMETER Witness
        Sets the witness server endpoint in TCP://servername:port format to enable automatic failover in high-safety mode.
        Use this to add witness functionality for automatic failover or to change the witness server location.

    .PARAMETER SafetyLevel
        Controls transaction safety mode: 'Full' for synchronous high-safety, 'Off' for asynchronous high-performance.
        Use 'Full' when you need zero data loss with automatic failover, or 'Off' for better performance with potential data loss during failover.

    .PARAMETER State
        Changes the operational state of the mirroring session. Options include Suspend, Resume, Failover, or RemoveWitness.
        Use this to temporarily pause mirroring during maintenance, resume after suspension, perform manual failover, or remove witness functionality.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase pipeline input for batch operations.
        Use this to configure mirroring settings across multiple databases efficiently by piping database objects from other dbatools commands.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Mirroring, Mirror, HA
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaDbMirror

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Database

        Returns the Database object only when the -State parameter is specified. When -State is used with Suspend, Resume, Failover, or RemoveWitness operations, the modified SMO Database object is returned to the pipeline.

        When only -Partner, -Witness, or -SafetyLevel parameters are specified, no output is returned (configuration-only operations with no object output).

        Default display properties from the returned Database object include:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: Database name
        - Status: Current database status (Normal, Offline, Recovering, etc.)
        - RecoveryModel: Database recovery model (Full, Simple, BulkLogged)
        - Owner: Database owner login name

        All properties from the SMO Database object are accessible using Select-Object *.

    .EXAMPLE
        PS C:\> Set-DbaDbMirror -SqlInstance sql2005 -Database dbatools -Partner TCP://SQL2008.ad.local:5374

        Prompts for confirmation then sets the partner to TCP://SQL2008.ad.local:5374 for the database "dbtools"

    .EXAMPLE
        PS C:\> Set-DbaDbMirror -SqlInstance sql2005 -Database dbatools -Witness TCP://SQL2012.ad.local:5502 -Confirm:$false

        Does not prompt for confirmation and sets the witness to TCP://SQL2012.ad.local:5502 for the database "dbtools"

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2005 | Out-GridView -PassThru | Set-DbaDbMirror -SafetyLevel Full -Confirm:$false

        Sets the safety level to Full for databases selected from a grid view. Does not prompt for confirmation.

    .EXAMPLE
        PS C:\> Set-DbaDbMirror -SqlInstance sql2005 -Database dbatools -State Suspend -Confirm:$false

        Does not prompt for confirmation and sets the state to suspend for the database "dbtools"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string]$Partner,
        [string]$Witness,
        [ValidateSet('Full', 'Off', 'None')]
        [string]$SafetyLevel,
        [ValidateSet('ForceFailoverAndAllowDataLoss', 'Failover', 'RemoveWitness', 'Resume', 'Suspend', 'Off')]
        [string]$State,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when SqlInstance is specified"
            return
        }
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            try {
                if ($Partner) {
                    if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Setting partner on $db")) {
                        # use t-sql cuz $db.Alter() does not always work against restoring dbs
                        $db.Parent.Query("ALTER DATABASE $db SET PARTNER = N'$Partner'")
                    }
                } elseif ($Witness) {
                    if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Setting witness on $db")) {
                        $db.Parent.Query("ALTER DATABASE $db SET WITNESS = N'$Witness'")
                    }
                }

                if ($SafetyLevel) {
                    if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Changing safety level to $SafetyLevel on $db")) {
                        $db.Parent.Query("ALTER DATABASE $db SET PARTNER SAFETY $SafetyLevel")
                        # $db.MirroringSafetyLevel = $SafetyLevel
                    }
                }

                if ($State) {
                    if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Changing mirror state to $State on $db")) {
                        $db.ChangeMirroringState($State)
                        $db.Alter()
                        $db
                    }
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_
            }
        }
    }
}