function Remove-DbaDbSequence {
    <#
    .SYNOPSIS
        Removes a sequence.

    .DESCRIPTION
        Removes a sequence in the database(s) specified.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The target database(s).

    .PARAMETER Name
        The name of the sequence.

    .PARAMETER Schema
        The name of the schema for the sequence. The default is dbo.

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
        Tags: Data, Sequence, Table
        Author: Adam Lancaster https://github.com/lancasteradam

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbSequence

    .EXAMPLE
        PS C:\> Remove-DbaDbSequence -SqlInstance sqldev01 -Database TestDB -Name TestSequence

        Removes the sequence TestSequence in the TestDB database on the sqldev01 instance.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqldev01 -Database TestDB | Remove-DbaDbSequence -Name TestSequence -Schema TestSchema

        Using a pipeline this command Removes the sequence named TestSchema.TestSequence in the TestDB database on the sqldev01 instance.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [Parameter(Mandatory)]
        [string]$Name,
        [string]$Schema = 'dbo',
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

            if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Removing the sequence $Name in the $Schema schema in the database $($db.Name) on $($db.Parent.Name)")) {
                try {
                    $sequenceToDrop = $db.Sequences | Where-Object { $_.Schema -eq $Schema -and $_.Name -eq $Name }
                    $sequenceToDrop.Drop()
                } catch {
                    Stop-Function -Message "Failure on $($db.Parent.Name) to drop the sequence $Name in the $Schema schema in the database $($db.Name)" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}