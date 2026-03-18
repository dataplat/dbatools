function Invoke-DbaDbMirrorFailover {
    <#
    .SYNOPSIS
        Fails over database mirroring configurations to the mirror server

    .DESCRIPTION
        Performs a database mirroring failover by switching roles between the primary and mirror servers. For synchronous mirroring, sets safety level to Full and executes a clean failover without data loss. For asynchronous mirroring or emergency situations, use -Force to allow a forced failover that may result in data loss. This is essential for planned maintenance, disaster recovery scenarios, and testing your high availability setup.

    .PARAMETER SqlInstance
        SQL Server name or SMO object representing the primary SQL Server.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which mirrored databases to fail over to their mirror partners. Accepts multiple database names.
        Use this when you need to fail over specific databases rather than piping database objects from Get-DbaDatabase.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase through the pipeline for failover operations.
        This enables you to filter databases using Get-DbaDatabase and pipe the results directly to perform failovers.

    .PARAMETER Force
        Forces an immediate failover that allows data loss, primarily for asynchronous mirroring or emergency situations.
        Without this switch, the function performs a safe synchronous failover by setting safety to Full before failing over.

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

        TODO: add service accounts

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Database

        Returns one Database object for each database that was failed over successfully. When performing a failover operation, the database object is returned with its mirroring state updated to reflect the new role (now the principal server).

        Default properties visible:
        - Name: Database name
        - Status: Current database status
        - Owner: Database owner login
        - RecoveryModel: Database recovery model (typically Full for mirrored databases)
        - Size: Database size in megabytes

        When no failover is performed due to -WhatIf or user cancellation, no output is returned.

    .LINK
        https://dbatools.io/Invoke-DbaDbMirrorFailover

    .EXAMPLE
        PS C:\> Invoke-DbaDbMirrorFailover -SqlInstance sql2016 -Database pubs

        Fails over the pubs database on sql2016. Prompts for confirmation.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016 -Database pubs | Invoke-DbaDbMirrorFailover -Force -Confirm:$false

        Forces the failover of the pubs database on sql2016 and allows data loss.
        Does not prompt for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when SqlInstance is specified"
            return
        }

        $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database

        foreach ($db in $InputObject) {
            # if it's async, you have to break the mirroring and allow data loss
            # alter database set partner force_service_allow_data_loss
            # if it's sync mirroring you know it's all in sync, so you can just do alter database [dbname] set partner failover
            if ($Force) {
                if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Forcing failover of $db and allowing data loss")) {
                    $db | Set-DbaDbMirror -State ForceFailoverAndAllowDataLoss
                }
            } else {
                if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Setting safety level to full and failing over $db to partner server")) {
                    $db | Set-DbaDbMirror -SafetyLevel Full
                    $db | Set-DbaDbMirror -State Failover
                }
            }
        }
    }
}