function New-DbaDbSequence {
    <#
    .SYNOPSIS
        Creates a new sequence object in SQL Server databases with configurable properties and data types.

    .DESCRIPTION
        Creates a new sequence object in one or more SQL Server databases, providing an alternative to IDENTITY columns for generating sequential numbers. This function allows you to configure all sequence properties including data type (system or user-defined), starting value, increment, min/max bounds, cycling behavior, and cache settings. Sequences are particularly useful when you need to share sequential numbers across multiple tables, require more control over number generation than IDENTITY provides, or need to reset or alter the sequence values. The function automatically creates the target schema if it doesn't exist and supports SQL Server 2012 and higher.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the target database(s) where the sequence will be created. Accepts multiple database names.
        Required when using SqlInstance parameter to specify which databases should contain the new sequence.

    .PARAMETER Sequence
        Specifies the name of the sequence object to create. Must be unique within the target schema.
        Use descriptive names like 'OrderNumber' or 'InvoiceID' to indicate the sequence's purpose.

    .PARAMETER Schema
        Specifies the schema where the sequence will be created. Defaults to 'dbo' if not specified.
        The function will automatically create the schema if it doesn't exist in the target database.

    .PARAMETER IntegerType
        Specifies the data type for the sequence values. Defaults to 'bigint' for maximum range.
        Supports system types (tinyint, smallint, int, bigint) and user-defined integer types using 'schema.typename' format.

    .PARAMETER StartWith
        Sets the initial value for the sequence. Defaults to 1 if not specified.
        Use higher starting values like 10000 when you need to reserve lower numbers or maintain existing numbering schemes.

    .PARAMETER IncrementBy
        Controls how much the sequence increases with each call to NEXT VALUE FOR. Defaults to 1.
        Use negative values for descending sequences or larger increments like 10 for spaced numbering.

    .PARAMETER MinValue
        Sets the lowest value the sequence can generate. When omitted, uses the data type's minimum value.
        Specify this to prevent sequences from generating values below a certain threshold.

    .PARAMETER MaxValue
        Sets the highest value the sequence can generate. When omitted, uses the data type's maximum value.
        Define this to limit sequence values or enable cycling at a specific upper bound.

    .PARAMETER Cycle
        Enables the sequence to restart from MinValue after reaching MaxValue (or vice versa for descending sequences).
        Use this for sequences that should continuously cycle through a range of values rather than stopping at the boundary.

    .PARAMETER CacheSize
        Controls how many sequence values SQL Server pre-allocates in memory for performance. Set to 0 for NO CACHE.
        Higher cache sizes improve performance for frequently accessed sequences but may cause gaps if the instance restarts.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase via pipeline input.
        Use this for pipeline operations when you want to create sequences across multiple databases returned by Get-DbaDatabase.

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
        https://dbatools.io/New-DbaDbSequence

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Sequence

        Returns one Sequence object for each sequence successfully created. The returned object represents the newly created SQL Server sequence definition with its configuration properties.

        Default display properties (via Select-DefaultView):
        - ComputerName: The name of the computer where the SQL Server instance is running
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - Database: The name of the database containing the sequence
        - Schema: The schema where the sequence is created
        - Name: The name of the sequence object
        - DataType: The data type of values the sequence will generate (e.g., bigint, int, tinyint, smallint)
        - StartValue: The initial value the sequence will return on first use
        - IncrementValue: The amount the sequence will increase (or decrease if negative) with each NEXT VALUE FOR call

        Additional properties available (from SMO Sequence object):
        - CurrentValue: The current value that will be returned by the next NEXT VALUE FOR call
        - MinValue: The minimum value the sequence can generate
        - MaxValue: The maximum value the sequence can generate
        - IsCycleEnabled: Boolean indicating whether the sequence will cycle from MaxValue back to MinValue
        - CacheSize: The number of sequence values pre-allocated in memory (0 means no cache)
        - SequenceCacheType: The cache behavior setting (DefaultCache, NoCache, or CacheWithSize)
        - Parent: Reference to the parent Database SMO object
        - Urn: The Uniform Resource Name (URN) identifying the sequence in the SMO object hierarchy
        - State: The state of the SMO object (Existing, Creating, Altering, Dropping, etc.)

        All properties from the base SMO Sequence object are accessible even though only default properties are displayed without using Select-Object *.

    .EXAMPLE
        PS C:\> New-DbaDbSequence -SqlInstance sqldev01 -Database TestDB -Sequence TestSequence -StartWith 10000 -IncrementBy 10

        Creates a new sequence TestSequence in the TestDB database on the sqldev01 instance. The sequence will start with 10000 and increment by 10.

    .EXAMPLE
        PS C:\> New-DbaDbSequence -SqlInstance sqldev01 -Database TestDB -Sequence TestSequence -Cycle

        Creates a new sequence TestSequence in the TestDB database on the sqldev01 instance. The sequence will cycle the numbers.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqldev01 -Database TestDB | New-DbaDbSequence -Sequence TestSequence -Schema TestSchema -IntegerType bigint

        Using a pipeline this command creates a new bigint sequence named TestSchema.TestSequence in the TestDB database on the sqldev01 instance.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [Parameter(Mandatory)]
        [Alias("Name")]
        [string[]]$Sequence,
        [string]$Schema = 'dbo',
        [string]$IntegerType = 'bigint',
        [long]$StartWith = 1,
        [long]$IncrementBy = 1,
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

            if ($db.Parent.VersionMajor -lt 11) {
                Stop-Function -Message "This command only supports SQL Server 2012 and higher." -Continue
            }

            if (($db.Sequences | Where-Object { $_.Schema -eq $Schema -and $_.Name -eq $Sequence })) {
                Stop-Function -Message "Sequence $Sequence already exists in the $Schema schema in the database $($db.Name) on $($db.Parent.Name)" -Continue
            }

            if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Creating the sequence $Sequence in the $Schema schema in the database $($db.Name) on $($db.Parent.Name)")) {
                try {
                    if (Test-Bound Schema) {
                        $schemaObject = $db | Get-DbaDbSchema -Schema $Schema -IncludeSystemSchemas

                        # if the schema does not exist then create it
                        if ($null -eq $schemaObject) {
                            $schemaObject = $db | New-DbaDbSchema -Schema $Schema
                        }
                    }

                    $newSequence = New-Object Microsoft.SqlServer.Management.Smo.Sequence -ArgumentList $db, $Sequence, $Schema
                    $newSequence.StartValue = $StartWith
                    $newSequence.IncrementValue = $IncrementBy
                    $newSequence.IsCycleEnabled = $Cycle.IsPresent

                    # support for user defined integer types
                    $tableParts = $IntegerType -Split "\."

                    if ($db.UserDefinedDataTypes[$IntegerType]) {
                        # check to see if the type is in the user defined types for this db
                        $newSequence.DataType = $db.UserDefinedDataTypes[$IntegerType]
                    } elseif ($tableParts.Count -eq 2) {
                        # custom type with the format "schema.typename"
                        $newSequence.DataType = $db.UserDefinedDataTypes | Where-Object { $_.Schema -eq $tableParts[0] -and $_.Name -eq $tableParts[1] }
                    } else {
                        # system integer type
                        $newSequence.DataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $IntegerType
                    }

                    if (Test-Bound MinValue) {
                        $newSequence.MinValue = $MinValue
                    }

                    if (Test-Bound MaxValue) {
                        $newSequence.MaxValue = $MaxValue
                    }

                    if (Test-Bound CacheSize) {
                        if ($CacheSize -eq 0) {
                            $newSequence.SequenceCacheType = [Microsoft.SqlServer.Management.Smo.SequenceCacheType]::NoCache
                        } else {
                            $newSequence.SequenceCacheType = [Microsoft.SqlServer.Management.Smo.SequenceCacheType]::CacheWithSize
                            $newSequence.CacheSize = $CacheSize
                        }
                    } else {
                        $newSequence.SequenceCacheType = [Microsoft.SqlServer.Management.Smo.SequenceCacheType]::DefaultCache
                    }

                    $newSequence.Create()
                    $db | Get-DbaDbSequence -Sequence $newSequence.Name -Schema $newSequence.Schema
                } catch {
                    Stop-Function -Message "Failure on $($db.Parent.Name) to create the sequence $Sequence in the $Schema schema in the database $($db.Name)" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}