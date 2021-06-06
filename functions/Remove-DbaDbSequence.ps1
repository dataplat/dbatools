function Remove-DbaDbSequence {
    <#
    .SYNOPSIS
        Removes sequences.

    .DESCRIPTION
        Removes the sequences that have passed through the pipeline.

        If not used with a pipeline, Get-DbaDbSequence will be executed with the parameters provided
        and the returned sequences will be removed.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The target database(s).

    .PARAMETER Name
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
        [string[]]$Name,
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
            $sequences = Get-DbaDbSequence @PSBoundParameters
        } else {
            $sequences += $InputObject
        }
    }

    end {
        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaDbSequence.
        foreach ($sequence in $sequences) {
            if ($PSCmdlet.ShouldProcess($sequence.Parent.Parent.Name, "Removing the sequence $($sequence.Schema).$($sequence.Name) in the database $($sequence.Parent.Name) on $($sequence.Parent.Parent.Name)")) {
                $output = [pscustomobject]@{
                    ComputerName   = $sequence.Parent.Parent.ComputerName
                    InstanceName   = $sequence.Parent.Parent.ServiceName
                    SqlInstance    = $sequence.Parent.Parent.DomainInstanceName
                    Database       = $sequence.Parent.Name
                    Sequence       = "$($sequence.Schema).$($sequence.Name)"
                    SequenceName   = $sequence.Name
                    SequenceSchema = $sequence.Schema
                    Status         = $null
                    Removed        = $false
                    Success        = $false
                    Successful     = $false
                }
                try {
                    $sequence.Drop()
                    $output.Status = "Dropped"
                    $output.Removed = $true
                    $output.Success = $true
                    $output.Successful = $true
                } catch {
                    Stop-Function -Message "Failed removing the sequence $($sequence.Schema).$($sequence.Name) in the database $($sequence.Parent.Name) on $($sequence.Parent.Parent.Name)" -ErrorRecord $_ -Continue
                    $output.Status = (Get-ErrorMessage -Record $_)
                    $output.Removed = $false
                    $output.Success = $false
                    $output.Successful = $false
                }
                $output
            }
        }
    }
}