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
        Filters results to only return conditions that match the specified names. Accepts multiple condition names and supports wildcards.
        Use this when you need to examine specific PBM conditions rather than retrieving all conditions from the instance.

    .PARAMETER IncludeSystemObject
        Includes built-in system conditions in the results, which are filtered out by default. System conditions are predefined by SQL Server for common compliance scenarios.
        Use this when you need to see all available conditions including Microsoft's built-in templates for policy creation.

    .PARAMETER InputObject
        Accepts Policy-Based Management store objects from Get-DbaPbmStore via pipeline input. This allows you to chain commands and work with multiple PBM stores efficiently.
        Use this when processing conditions from multiple instances or when working with previously retrieved PBM store objects.

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

    .OUTPUTS
        Microsoft.SqlServer.Management.Dmf.Condition

        Returns one condition object for each policy condition found on the specified PBM store. Conditions define the rules and criteria used to evaluate database objects for compliance with policies.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Id: Unique identifier for the condition
        - Name: The name of the condition
        - CreateDate: DateTime when the condition was created
        - CreatedBy: User who created the condition
        - DateModified: DateTime when the condition was last modified
        - Description: Description of the condition
        - ExpressionNode: The expression tree that defines the condition logic
        - Facet: The facet that the condition applies to (management area such as Database, Server, Table, etc.)
        - HasScript: Boolean indicating if the condition contains a dynamic script expression
        - IsSystemObject: Boolean indicating if this is a system-provided condition or user-created
        - ModifiedBy: User who last modified the condition

        Additional properties available via Select-Object *:
        - IsEnumerable: Boolean indicating if the condition can be used as a target set level filter
        - Parent: Reference to the parent PolicyStore object
        - State: Current state of the condition object (Existing, Creating, Pending, etc.)
        - Urn: Uniform Resource Name (URN) for the condition object
        - IdentityKey: Identity key of the condition object
        - Metadata: Metadata information
        - KeyChain: Identity path of the condition object
        - Properties: Properties collection for the condition

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