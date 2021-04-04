function Set-DbaDbSequence {
    <#
    .SYNOPSIS
        Modifies a sequence.

    .DESCRIPTION
        Modifies a sequence in the database(s) specified.

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
        The name of the new sequence

    .PARAMETER Schema
        The name of the schema for the sequence. The default is dbo.

    .PARAMETER RestartWith
        The first value for the sequence to restart with.

    .PARAMETER IncrementBy
        The value to increment by.

    .PARAMETER MinValue
        The minimum bound for the sequence.

    .PARAMETER MaxValue
        The maximum bound for the sequence.

    .PARAMETER Cycle
        Switch that indicates if the sequence should cycle the values

    .PARAMETER CacheSize
        The integer size of the cache. To specify NO CACHE for a sequence use -CacheSize 0. As noted in the Microsoft documentation if the cache size is not specified the Database Engine will select a size.

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
        https://dbatools.io/Set-DbaDbSequence

    .EXAMPLE
        PS C:\> Set-DbaDbSequence -SqlInstance sqldev01 -Database TestDB -Name TestSequence -RestartWith 10000 -IncrementBy 10

        Modifies the sequence TestSequence in the TestDB database on the sqldev01 instance. The sequence will restart with 10000 and increment by 10.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqldev01 -Database TestDB | Set-DbaDbSequence -Name TestSequence -Schema TestSchema -Cycle

        Using a pipeline this command modifies the sequence named TestSchema.TestSequence in the TestDB database on the sqldev01 instance. The sequence will now cycle the sequence values.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [Parameter(Mandatory)]
        [string]$Name,
        [string]$Schema = 'dbo',
        [long]$RestartWith,
        [long]$IncrementBy,
        [long]$MinValue,
        [long]$MaxValue,
        [switch]$Cycle,
        [int32]$CacheSize,
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

            if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Modifying the sequence $Name in the $Schema schema in the database $($db.Name) on $($db.Parent.Name)")) {
                try {
                    $sequence = $db | Get-DbaDbSequence -Schema $Schema -Name $Name

                    if ($null -eq $sequence) {
                        Stop-Function -Message "Unable to find sequence $Name in the $Schema schema in the database $($db.Name) on $($db.Parent.Name)" -Continue
                    }

                    if (Test-Bound IncrementBy) {
                        $sequence.IncrementValue = $IncrementBy
                    }

                    $sequence.IsCycleEnabled = $Cycle.IsPresent

                    if (Test-Bound RestartWith) {
                        $sequence.StartValue = $RestartWith # SMO does the restart logic when this value is changed and then Alter() is called (i.e. CurrentValue is also updated)
                    }

                    if (Test-Bound MinValue) {
                        $sequence.MinValue = $MinValue
                    }

                    if (Test-Bound MaxValue) {
                        $sequence.MaxValue = $MaxValue
                    }

                    if (Test-Bound CacheSize) {
                        if ($CacheSize -eq 0) {
                            $sequence.SequenceCacheType = [Microsoft.SqlServer.Management.Smo.SequenceCacheType]::NoCache
                        } else {
                            $sequence.SequenceCacheType = [Microsoft.SqlServer.Management.Smo.SequenceCacheType]::CacheWithSize
                            $sequence.CacheSize = $CacheSize
                        }
                    } else {
                        $sequence.SequenceCacheType = [Microsoft.SqlServer.Management.Smo.SequenceCacheType]::DefaultCache
                    }

                    $sequence.Alter()
                    $db.Refresh()
                    $db.Sequences | Where-Object { $_.Schema -eq $Schema -and $_.Name -eq $Name }
                } catch {
                    Stop-Function -Message "Failure on $($db.Parent.Name) to modify the sequence $Name in the $Schema schema in the database $($db.Name)" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}