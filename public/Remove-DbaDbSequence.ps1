function Remove-DbaDbSequence {
    <#
    .SYNOPSIS
        Removes database sequence objects from SQL Server instances.

    .DESCRIPTION
        Removes sequence objects from SQL Server databases, freeing up schema namespace and cleaning up unused database objects.
        Sequences are commonly used for generating unique numeric values and may need removal during application changes or database cleanup.
        
        When used without a pipeline, the function will first retrieve matching sequences using Get-DbaDbSequence with the provided parameters, then remove them.
        Pipeline input from Get-DbaDbSequence allows for selective removal after review or filtering.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The target database(s).

    .PARAMETER Sequence
        The name(s) of the sequence(s).

    .PARAMETER Schema
        The name(s) of the schema for the sequence(s).

    .PARAMETER InputObject
        Allows piping from Get-DbaDbSequence.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.
        This is the default. Use -Confirm:$false to suppress these prompts.

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
        https://dbatools.io/Remove-DbaDbSequence

    .EXAMPLE
        PS C:\> Remove-DbaDbSequence -SqlInstance sqldev01 -Database TestDB -Sequence TestSequence

        Removes the sequence TestSequence in the TestDB database on the sqldev01 instance.

    .EXAMPLE
        PS C:\> Get-DbaDbSequence -SqlInstance SRV1 | Out-GridView -Title 'Select sequence(s) to drop' -OutputMode Multiple | Remove-DbaDbSequence

        Using a pipeline this command gets all sequences on SRV1, lets the user select those to remove and then removes the selected sequences.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(ParameterSetName = 'NonPipeline', Mandatory = $true, Position = 0)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [PSCredential]$SqlCredential,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [string[]]$Database,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [Alias("Name")]
        [string[]]$Sequence,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [string[]]$Schema,
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Sequence[]]$InputObject,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [switch]$EnableException
    )

    begin {
        $sequences = @( )
    }

    process {
        if ($SqlInstance) {
            $params = $PSBoundParameters
            $null = $params.Remove('WhatIf')
            $null = $params.Remove('Confirm')
            $sequences = Get-DbaDbSequence @params
        } else {
            $sequences += $InputObject
        }
    }

    end {
        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaDbSequence.
        foreach ($sequenceItem in $sequences) {
            if ($PSCmdlet.ShouldProcess($sequenceItem.Parent.Parent.Name, "Removing the sequence $($sequenceItem.Schema).$($sequenceItem.Name) in the database $($sequenceItem.Parent.Name) on $($sequenceItem.Parent.Parent.Name)")) {
                $output = [PSCustomObject]@{
                    ComputerName   = $sequenceItem.Parent.Parent.ComputerName
                    InstanceName   = $sequenceItem.Parent.Parent.ServiceName
                    SqlInstance    = $sequenceItem.Parent.Parent.DomainInstanceName
                    Database       = $sequenceItem.Parent.Name
                    Sequence       = "$($sequenceItem.Schema).$($sequenceItem.Name)"
                    SequenceName   = $sequenceItem.Name
                    SequenceSchema = $sequenceItem.Schema
                    Status         = $null
                    IsRemoved      = $false
                }
                try {
                    $sequenceItem.Drop()
                    $output.Status = "Dropped"
                    $output.IsRemoved = $true
                } catch {
                    Stop-Function -Message "Failed removing the sequence $($sequenceItem.Schema).$($sequenceItem.Name) in the database $($sequenceItem.Parent.Name) on $($sequenceItem.Parent.Parent.Name)" -ErrorRecord $_
                    $output.Status = (Get-ErrorMessage -Record $_)
                    $output.IsRemoved = $false
                }
                $output
            }
        }
    }
}