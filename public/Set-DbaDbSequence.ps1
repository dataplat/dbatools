function Set-DbaDbSequence {
    <#
    .SYNOPSIS
        Modifies properties of existing SQL Server sequence objects

    .DESCRIPTION
        Modifies existing SQL Server sequence objects by updating their properties such as increment value, restart point, minimum and maximum bounds, cycling behavior, and cache settings. This function is essential when you need to adjust sequence behavior after deployment, fix increment issues, or optimize performance without recreating the sequence and losing its current state.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the target database containing the sequence to modify. Accepts multiple database names.
        Required when using SqlInstance parameter to identify which database contains the sequence.

    .PARAMETER Sequence
        Specifies the name of the sequence object to modify. This is the sequence you want to update properties for.
        Must be an existing sequence in the specified schema, otherwise the function will fail.

    .PARAMETER Schema
        Specifies the schema containing the sequence to modify. Defaults to 'dbo' if not specified.
        Use this when your sequence exists in a custom schema rather than the default dbo schema.

    .PARAMETER RestartWith
        Sets the next value the sequence will return when NEXT VALUE FOR is called. Immediately resets the sequence to this value.
        Use this to fix sequence gaps, realign sequences after data imports, or reset sequences for testing.

    .PARAMETER IncrementBy
        Sets how much the sequence value increases (or decreases if negative) with each NEXT VALUE FOR call.
        Common values are 1 for sequential numbering or larger values for reserving ranges. Cannot be zero.

    .PARAMETER MinValue
        Sets the lowest value the sequence can generate. Once reached, sequence behavior depends on the Cycle setting.
        Use this to establish data range constraints or prevent sequences from going below business-required minimums.

    .PARAMETER MaxValue
        Sets the highest value the sequence can generate. Once reached, sequence behavior depends on the Cycle setting.
        Use this to prevent sequences from exceeding data type limits or business-defined maximum values.

    .PARAMETER Cycle
        Enables the sequence to restart from MinValue after reaching MaxValue (or vice versa for negative increments).
        Use this for scenarios like rotating through a fixed set of values or when sequences need to wrap around.

    .PARAMETER CacheSize
        Sets the number of sequence values SQL Server pre-allocates in memory for faster access.
        Use 0 to disable caching (guarantees no gaps but slower performance), or specify a number for high-performance scenarios. Omit this parameter to let SQL Server choose an optimal cache size.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase via pipeline to modify sequences across multiple databases.
        Use this for batch operations when you need to modify the same sequence in multiple databases.

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
        Author: Adam Lancaster, github.com/lancasteradam

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaDbSequence

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Sequence

        Returns the updated Sequence object for each modified sequence, with all properties reflecting the changes applied. Unlike Get-DbaDbSequence, no Select-DefaultView is applied; the raw SMO Sequence object is returned after the database is refreshed.

        Key properties:
        - Name: The name of the sequence object
        - Schema: The schema containing the sequence
        - Owner: The principal that owns the sequence
        - StartValue: The starting value for the sequence
        - CurrentValue: The current value of the sequence
        - IncrementValue: The increment applied with each NEXT VALUE FOR call
        - MinValue: The minimum value the sequence can generate
        - MaxValue: The maximum value the sequence can generate
        - IsCycleEnabled: Boolean indicating if the sequence cycles after reaching MinValue or MaxValue
        - SequenceCacheType: The cache setting (NoCache, CacheWithSize, or DefaultCache)
        - CacheSize: The number of pre-allocated values (when applicable)

        All properties from the SMO Sequence object are accessible using Select-Object *. Additional properties include:
        - CreationDate: DateTime when the sequence was created
        - LastModificationTime: DateTime when the sequence was last modified
        - Urn: The Uniform Resource Name (URN) of the sequence object
        - State: The SMO object state (Existing, Creating, Pending, Dropping, etc.)
        - Parent: Reference to the parent Database object

    .EXAMPLE
        PS C:\> Set-DbaDbSequence -SqlInstance sqldev01 -Database TestDB -Sequence TestSequence -RestartWith 10000 -IncrementBy 10

        Modifies the sequence TestSequence in the TestDB database on the sqldev01 instance. The sequence will restart with 10000 and increment by 10.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqldev01 -Database TestDB | Set-DbaDbSequence -Sequence TestSequence -Schema TestSchema -Cycle

        Using a pipeline this command modifies the sequence named TestSchema.TestSequence in the TestDB database on the sqldev01 instance. The sequence will now cycle the sequence values.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [Parameter(Mandatory)]
        [Alias("Name")]
        [string[]]$Sequence,
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

        if ((Test-Bound -ParameterName IncrementBy) -and ($IncrementBy -eq 0)) {
            Stop-Function -Message "IncrementBy cannot be zero"
            return
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {

            if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Modifying the sequence $Sequence in the $Schema schema in the database $($db.Name) on $($db.Parent.Name)")) {
                try {
                    $sequenceObj = $db | Get-DbaDbSequence -Schema $Schema -Sequence $Sequence

                    if ($null -eq $sequenceObj) {
                        Stop-Function -Message "Unable to find sequence $Sequence in the $Schema schema in the database $($db.Name) on $($db.Parent.Name)" -Continue
                    }

                    if (Test-Bound IncrementBy) {
                        $sequenceObj.IncrementValue = $IncrementBy
                    }

                    $sequenceObj.IsCycleEnabled = $Cycle.IsPresent

                    if (Test-Bound RestartWith) {
                        $sequenceObj.StartValue = $RestartWith # SMO does the restart logic when this value is changed and then Alter() is called (i.e. CurrentValue is also updated)
                    }

                    if (Test-Bound MinValue) {
                        $sequenceObj.MinValue = $MinValue
                    }

                    if (Test-Bound MaxValue) {
                        $sequenceObj.MaxValue = $MaxValue
                    }

                    if (Test-Bound CacheSize) {
                        if ($CacheSize -eq 0) {
                            $sequenceObj.SequenceCacheType = [Microsoft.SqlServer.Management.Smo.SequenceCacheType]::NoCache
                        } else {
                            $sequenceObj.SequenceCacheType = [Microsoft.SqlServer.Management.Smo.SequenceCacheType]::CacheWithSize
                            $sequenceObj.CacheSize = $CacheSize
                        }
                    } else {
                        $sequenceObj.SequenceCacheType = [Microsoft.SqlServer.Management.Smo.SequenceCacheType]::DefaultCache
                    }

                    $sequenceObj.Alter()
                    $db.Refresh()
                    $db.Sequences | Where-Object { $_.Schema -eq $Schema -and $_.Name -eq $Sequence }
                } catch {
                    Stop-Function -Message "Failure on $($db.Parent.Name) to modify the sequence $Sequence in the $Schema schema in the database $($db.Name)" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}