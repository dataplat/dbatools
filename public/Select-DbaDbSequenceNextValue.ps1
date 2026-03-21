function Select-DbaDbSequenceNextValue {
    <#
    .SYNOPSIS
        Retrieves and increments the next value from a SQL Server sequence object.

    .DESCRIPTION
        Executes a SELECT NEXT VALUE FOR statement against the specified sequence, which increments the sequence counter and returns the next value in the series.
        This is useful for testing sequence behavior, troubleshooting sequence issues, or retrieving sequence values for application logic.
        Note that calling this function will permanently increment the sequence counter, so it's not just a read operation.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database containing the sequence object you want to increment.
        Required when using SqlInstance parameter to identify which database contains the target sequence.

    .PARAMETER Sequence
        Specifies the name of the sequence object to increment and retrieve the next value from.
        Accepts multiple sequence names when you need to get next values from several sequences in the same operation.
        This will permanently increment each sequence's internal counter.

    .PARAMETER Schema
        Specifies the schema that contains the sequence object. Defaults to 'dbo' if not specified.
        Use this when your sequence is created in a custom schema other than the default dbo schema.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase via pipeline input.
        Use this to chain database selection with sequence operations when working with multiple databases or complex filtering scenarios.

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
        https://dbatools.io/Select-DbaDbSequenceNextValue

    .OUTPUTS
        System.Int64

        Returns the next value from the specified sequence object as a 64-bit integer. Each call to this function increments the sequence's internal counter and returns the next value in the sequence series.

        When multiple sequences are specified via the -Sequence parameter, one integer value is returned per sequence in the order specified. The returned value is the SQL Server sequence value (typically a bigint data type).

        Example values: 1, 2, 3, 100, 1000, etc., depending on the sequence's start value, increment, and current state.

    .EXAMPLE
        PS C:\> Select-DbaDbSequenceNextValue -SqlInstance sqldev01 -Database TestDB -Sequence TestSequence

        Selects the next value from the sequence TestSequence in the TestDB database on the sqldev01 instance.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqldev01 -Database TestDB | Select-DbaDbSequenceNextValue -Sequence TestSequence -Schema TestSchema

        Using a pipeline this command selects the next value from the sequence TestSchema.TestSequence in the TestDB database on the sqldev01 instance.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Database,
        [Parameter(Mandatory)]
        [Alias("Name")]
        [string[]]$Sequence,
        [string]$Schema = 'dbo',
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database]$InputObject,
        [switch]$EnableException
    )
    process {

        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when SqlInstance is specified"
            return
        }

        if (Test-Bound SqlInstance) {
            $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        $InputObject.Query("SELECT NEXT VALUE FOR [$($Schema)].[$($Sequence)] AS NextValue").NextValue
    }
}