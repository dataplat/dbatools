function Get-DbaDbSequence {
    <#
    .SYNOPSIS
        Retrieves SQL Server sequence objects and their configuration details from specified databases.

    .DESCRIPTION
        Retrieves sequence objects from SQL Server databases, returning detailed information about each sequence including data type, start value, increment value, and schema location. Sequences provide a flexible alternative to IDENTITY columns for generating sequential numeric values, allowing values to be shared across multiple tables and offering more control over numbering behavior. This function helps DBAs inventory sequences across databases, verify sequence configurations, and identify sequences that may need maintenance or optimization.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The target database(s).

    .PARAMETER Sequence
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
        Author: Adam Lancaster, github.com/lancasteradam

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbSequence

    .EXAMPLE
        PS C:\> Get-DbaDbSequence -SqlInstance sqldev01 -Database TestDB -Sequence TestSequence

        Finds the sequence TestSequence in the TestDB database on the sqldev01 instance.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqldev01 -Database TestDB | Get-DbaDbSequence -Sequence TestSequence -Schema TestSchema

        Using a pipeline this command finds the sequence named TestSchema.TestSequence in the TestDB database on the sqldev01 instance.

    .EXAMPLE
        PS C:\> Get-DbaDbSequence -SqlInstance localhost

        Finds all the sequences on the localhost instance.

    .EXAMPLE
        PS C:\> Get-DbaDbSequence -SqlInstance localhost -Database db

        Finds all the sequences in the db database on the localhost instance.

    .EXAMPLE
        PS C:\> Get-DbaDbSequence -SqlInstance localhost -Sequence seq

        Finds all the sequences named seq on the localhost instance.

    .EXAMPLE
        PS C:\> Get-DbaDbSequence -SqlInstance localhost -Schema sch

        Finds all the sequences in the sch schema on the localhost instance.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [Alias("Name")]
        [string[]]$Sequence,
        [string[]]$Schema,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a database or specify a SqlInstance"
            return
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            if ($db.IsAccessible -eq $false) {
                continue
            }
            $server = $db.Parent
            Write-Message -Level 'Verbose' -Message "Getting Database Sequences for $db on $server"

            $dbSequences = $db.Sequences

            if ($Sequence) {
                $dbSequences = $dbSequences | Where-Object { $_.Name -in $Sequence }
            }

            if ($Schema) {
                $dbSequences = $dbSequences | Where-Object { $_.Schema -in $Schema }
            }

            foreach ($dbSequence in $dbSequences) {
                Add-Member -Force -InputObject $dbSequence -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                Add-Member -Force -InputObject $dbSequence -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $dbSequence -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Add-Member -Force -InputObject $dbSequence -MemberType NoteProperty -Name Database -Value $db.Name

                Select-DefaultView -InputObject $dbSequence -Property "ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "Name", "DataType", "StartValue", "IncrementValue"
            }
        }
    }
}