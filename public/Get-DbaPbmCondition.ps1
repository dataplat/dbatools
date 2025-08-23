function Get-DbaPbmCondition {
    <#
    .SYNOPSIS
        Retrieves Policy-Based Management conditions from SQL Server instances for compliance monitoring and policy evaluation.

    .DESCRIPTION
        Retrieves Policy-Based Management (PBM) conditions from SQL Server instances, which define the rules and criteria used to evaluate database objects for compliance. These conditions form the building blocks of PBM policies and specify what to check (like database settings, table properties, or server configurations) and what values are acceptable. Use this to audit existing conditions, troubleshoot policy failures, or inventory your compliance framework across multiple instances.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Condition
        Filters results to only show specific condition

    .PARAMETER IncludeSystemObject
        By default system objects are filtered out. Use this parameter to include them.

    .PARAMETER InputObject
        Allows piping from Get-DbaPbmStore

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Policy, PolicyBasedManagement, PBM
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaPbmCondition

    .EXAMPLE
        PS C:\> Get-DbaPbmCondition -SqlInstance sql2016

        Returns all conditions from the sql2016 PBM server

    .EXAMPLE
        PS C:\> Get-DbaPbmCondition -SqlInstance sql2016 -SqlCredential $cred

        Uses a credential $cred to connect and return all conditions from the sql2016 PBM server

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Condition,
        [Parameter(ValueFromPipeline)]
        [psobject[]]$InputObject,
        [switch]$IncludeSystemObject,
        [switch]$EnableException
    )
    begin {
        Add-PbmLibrary
    }
    process {
        if (Test-FunctionInterrupt) { return }
        if ($PSVersionTable.PSEdition -eq "Core") {
            Stop-Function -Message "This command is not yet supported in PowerShell Core"
            return
        }
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaPbmStore -SqlInstance $instance -SqlCredential $SqlCredential
        }
        foreach ($store in $InputObject) {
            $allconditions = $store.Conditions

            if (-not $IncludeSystemObject) {
                $allconditions = $allconditions | Where-Object IsSystemObject -eq $false
            }

            if ($Condition) {
                $allconditions = $allconditions | Where-Object Name -in $Condition
            }

            foreach ($currentcondition in $allconditions) {
                Write-Message -Level Verbose -Message "Processing $currentcondition"
                Add-Member -Force -InputObject $currentcondition -MemberType NoteProperty ComputerName -value $store.ComputerName
                Add-Member -Force -InputObject $currentcondition -MemberType NoteProperty InstanceName -value $store.InstanceName
                Add-Member -Force -InputObject $currentcondition -MemberType NoteProperty SqlInstance -value $store.SqlInstance
                Select-DefaultView -InputObject $currentcondition -Property ComputerName, InstanceName, SqlInstance, Id, Name, CreateDate, CreatedBy, DateModified, Description, ExpressionNode, Facet, HasScript, IsSystemObject, ModifiedBy
            }
        }
    }
}