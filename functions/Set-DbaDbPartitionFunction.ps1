function Set-DbaDbPartitionFunction {
    <#
    .SYNOPSIS
        Updates the owner for one or more schemas.

    .DESCRIPTION
        Updates the owner for one or more schemas.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The target database(s).

    .PARAMETER Schema
        The name(s) of the schema(s)

    .PARAMETER SchemaOwner
        The name of the database user that will own the schema(s).

    .PARAMETER InputObject
        Allows piping from Get-DbaDatabase.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Schema, Database
        Author: Adam Lancaster https://github.com/lancasteradam

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaDbPartitionFunction

    .EXAMPLE
        PS C:\> Set-DbaDbPartitionFunction -SqlInstance sqldev01 -Database example1 -PartitionFunction TestSchema1 -PartitionFunctionOwner dbatools

        Updates the TestSchema1 schema in the example1 database in the sqldev01 instance. The dbatools user will be the new owner of the schema.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqldev01, sqldev02 -Database example1 | Set-DbaDbPartitionFunction -PartitionFunction TestSchema1, TestSchema2 -PartitionFunctionOwner dbatools

        Passes in the example1 db via pipeline and updates the TestSchema1 and TestSchema2 schemas and assigns the dbatools user as the owner of the schemas.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$PartitionFunction,
        [string]$Range,
        [switch]$Merge,
        [switch]$Split,
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

            foreach ($sName in $PartitionFunction) {

                if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Updating the schema $sName on the database $($db.Name) to be owned by $PartitionFunctionOwner")) {
                    try {
                        $partFunObject = $db | Get-DbaDbPartitionFunction -PartitionFunction $sName

                        if ($Merge) {
                            if ($Pscmdlet.ShouldProcess($server, "Updating partition function")) {
                                $partFunObject.MergeRangePartition($Range)
                            }
                        }

                        if ($Split) {
                            if ($Pscmdlet.ShouldProcess($server, "Updating partition function")) {
                                $partFunObject.SplitRangePartition($Range)
                            }
                        }

                        $partFunObject

                    } catch {
                        Stop-Function -Message "Failure on $($db.Parent.Name) to update the schema owner for $sName in the database $($db.Name)" -ErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}