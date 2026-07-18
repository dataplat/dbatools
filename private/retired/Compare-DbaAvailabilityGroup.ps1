function Compare-DbaAvailabilityGroup {
    <#
    .SYNOPSIS
        Compares configuration across Availability Group replicas to identify differences in Jobs, Logins, Credentials, and Operators.

    .DESCRIPTION
        Compares multiple object types across all replicas in an Availability Group to identify configuration differences. This comprehensive command checks SQL Agent Jobs, SQL Server Logins, SQL Server Credentials, and SQL Agent Operators to ensure consistency across AG replicas.

        This is the main command for comparing AG replica configurations. It can run all comparison checks or specific ones based on the Type parameter.

        Use this to verify that junior DBAs have applied changes to all replicas, troubleshoot issues where configurations have drifted, or perform routine audits of AG replica consistency.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Can be any replica in the Availability Group.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        Specifies one or more Availability Group names to compare across their replicas.

    .PARAMETER Type
        Specifies which object types to compare. Valid options are: AgentJob, Login, Credential, Operator, All.
        Default is All which runs all comparison checks.

    .PARAMETER ExcludeSystemJob
        Excludes system jobs from the agent job comparison.
        Only applicable when Type includes AgentJob or All.

    .PARAMETER ExcludeSystemLogin
        Excludes built-in system logins from the login comparison.
        Only applicable when Type includes Login or All.

    .PARAMETER IncludeModifiedDate
        Includes DateLastModified comparison for jobs and modify_date comparison for logins.
        Only applicable when Type includes AgentJob, Login, or All.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AvailabilityGroup, AG, Job, Login, Credential, Operator
        Author: dbatools team

        Website: https://dbatools.io
        Copyright: (c) 2025 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Compare-DbaAvailabilityGroup

    .OUTPUTS
        PSCustomObject

        Returns zero or more objects representing configuration differences detected across Availability Group replicas. The specific properties returned depend on which comparison types are executed (controlled by the -Type parameter).

        For AgentJob comparisons:
        - AvailabilityGroup: The name of the Availability Group being compared
        - Replica: The SQL Server instance name where the job status applies
        - JobName: The name of the SQL Agent job
        - Status: Job status on this replica ("Present" or "Missing")
        - DateLastModified: DateTime when the job was last modified, or $null if the job is missing on this replica (only populated when -IncludeModifiedDate is specified)

        For Login comparisons:
        - AvailabilityGroup: The name of the Availability Group being compared
        - Replica: The name of the SQL Server replica instance
        - LoginName: The name of the login account
        - Status: Current status of the login on this replica ("Present" or "Missing")
        - ModifyDate: The datetime when the login was last modified on this replica (null if Status is "Missing"; only populated when -IncludeModifiedDate is specified)
        - CreateDate: The datetime when the login was created on this replica (null if Status is "Missing")

        For Credential comparisons:
        - AvailabilityGroup: The name of the Availability Group being compared
        - Replica: The name of the replica instance where the credential status was checked
        - CredentialName: The name of the SQL Server credential
        - Status: The credential state on this replica ("Present" if the credential exists, "Missing" if it doesn't)
        - Identity: The credential's identity/principal on replicas where the credential is Present; $null where Status is "Missing"

        For Operator comparisons:
        - AvailabilityGroup: Name of the Availability Group being compared
        - Replica: The SQL Server instance name of the replica
        - OperatorName: Name of the SQL Agent operator
        - Status: Configuration status of the operator on this replica ("Present" or "Missing")
        - EmailAddress: Email address of the operator (null if Status is "Missing")

        Only objects representing differences (missing items or differing values when -IncludeModifiedDate is specified) are returned. If all configurations are identical across replicas, no output is generated.

    .EXAMPLE
        PS C:\> Compare-DbaAvailabilityGroup -SqlInstance sql2016 -AvailabilityGroup AG1

        Compares all object types (Jobs, Logins, Credentials, Operators) across replicas in AG1.

    .EXAMPLE
        PS C:\> Compare-DbaAvailabilityGroup -SqlInstance sql2016 -AvailabilityGroup AG1 -Type AgentJob

        Compares only SQL Agent Jobs across replicas in AG1.

    .EXAMPLE
        PS C:\> Compare-DbaAvailabilityGroup -SqlInstance sql2016 -AvailabilityGroup AG1 -Type AgentJob, Login

        Compares SQL Agent Jobs and Logins across replicas in AG1.

    .EXAMPLE
        PS C:\> Compare-DbaAvailabilityGroup -SqlInstance sql2016 -AvailabilityGroup AG1 -IncludeModifiedDate

        Compares all object types including DateLastModified timestamps for jobs and logins.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2016 | Compare-DbaAvailabilityGroup

        Compares all object types for all Availability Groups on sql2016 via pipeline input.

    .EXAMPLE
        PS C:\> Compare-DbaAvailabilityGroup -SqlInstance sql2016 -AvailabilityGroup AG1 -ExcludeSystemJob -ExcludeSystemLogin

        Compares all object types excluding system jobs and system logins.
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [ValidateSet("AgentJob", "Login", "Credential", "Operator", "All")]
        [string[]]$Type = "All",
        [switch]$ExcludeSystemJob,
        [switch]$ExcludeSystemLogin,
        [switch]$IncludeModifiedDate,
        [switch]$EnableException
    )

    process {
        if ("All" -in $Type) {
            $Type = @("AgentJob", "Login", "Credential", "Operator")
        }

        foreach ($instance in $SqlInstance) {
            if ("AgentJob" -in $Type) {
                $splatAgentJob = @{
                    SqlInstance     = $instance
                    SqlCredential   = $SqlCredential
                    EnableException = $EnableException
                }

                if ($AvailabilityGroup) {
                    $splatAgentJob["AvailabilityGroup"] = $AvailabilityGroup
                }

                if ($ExcludeSystemJob) {
                    $splatAgentJob["ExcludeSystemJob"] = $true
                }

                if ($IncludeModifiedDate) {
                    $splatAgentJob["IncludeModifiedDate"] = $true
                }

                Compare-DbaAgReplicaAgentJob @splatAgentJob
            }

            if ("Login" -in $Type) {
                $splatLogin = @{
                    SqlInstance     = $instance
                    SqlCredential   = $SqlCredential
                    EnableException = $EnableException
                }

                if ($AvailabilityGroup) {
                    $splatLogin["AvailabilityGroup"] = $AvailabilityGroup
                }

                if ($ExcludeSystemLogin) {
                    $splatLogin["ExcludeSystemLogin"] = $true
                }

                if ($IncludeModifiedDate) {
                    $splatLogin["IncludeModifiedDate"] = $true
                }

                Compare-DbaAgReplicaLogin @splatLogin
            }

            if ("Credential" -in $Type) {
                $splatCredential = @{
                    SqlInstance     = $instance
                    SqlCredential   = $SqlCredential
                    EnableException = $EnableException
                }

                if ($AvailabilityGroup) {
                    $splatCredential["AvailabilityGroup"] = $AvailabilityGroup
                }

                Compare-DbaAgReplicaCredential @splatCredential
            }

            if ("Operator" -in $Type) {
                $splatOperator = @{
                    SqlInstance     = $instance
                    SqlCredential   = $SqlCredential
                    EnableException = $EnableException
                }

                if ($AvailabilityGroup) {
                    $splatOperator["AvailabilityGroup"] = $AvailabilityGroup
                }

                Compare-DbaAgReplicaOperator @splatOperator
            }
        }
    }
}
