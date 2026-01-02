function New-DbaDbRole {
    <#
    .SYNOPSIS
        Creates new database roles in one or more SQL Server databases.

    .DESCRIPTION
        Creates custom database roles for implementing role-based security in SQL Server databases. This function handles the creation of user-defined database roles that can later be granted specific permissions and have users or other roles assigned to them. You can create the same role across multiple databases for consistency, and optionally specify a custom owner instead of the default dbo. This eliminates the need to manually create roles through SSMS or T-SQL for each database.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to create the new role(s) in. Accepts wildcards for pattern matching.
        Use this when you need to create roles in specific databases instead of all databases on the instance.
        If unspecified, the role will be created in all accessible databases.

    .PARAMETER ExcludeDatabase
        Specifies databases to exclude from role creation when processing all databases.
        Use this to skip system databases or specific user databases where the role shouldn't be created.
        Particularly useful when creating standardized roles across most but not all databases.

    .PARAMETER Role
        Specifies the name(s) of the custom database role(s) to create.
        Use meaningful names that reflect the role's intended permissions like 'AppReadOnly' or 'ReportUsers'.
        The function will create each specified role in all target databases.

    .PARAMETER Owner
        Specifies the database principal that will own the new role. Defaults to 'dbo' if not specified.
        Use this when you need a specific user or role to own the new database role for security or organizational requirements.
        The owner must exist in each target database.

    .PARAMETER InputObject
        Accepts database objects piped from Get-DbaDatabase for role creation.
        Use this for advanced filtering or when working with databases from multiple instances.
        This parameter allows you to chain Get-DbaDatabase with specific filters before creating roles.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Role, User
        Author: Claudio Silva (@ClaudioESSilva), claudioessilva.eu
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaDbRole

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.DatabaseRole

        Returns one DatabaseRole object for each role created. One role is created per Role parameter value in each target database.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: The name of the newly created database role
        - Parent: The name of the database containing the role
        - Owner: The database principal that owns the role (dbo by default, or custom owner if specified)

        Additional properties available (from SMO DatabaseRole object):
        - ID: Unique identifier for the role
        - CreateDate: DateTime when the role was created
        - DateLastModified: DateTime when the role was last modified

        All properties from the base SMO DatabaseRole object are accessible using Select-Object *.

    .EXAMPLE
        PS C:\> New-DbaDbRole -SqlInstance sql2017a -Database db1 -Role 'dbExecuter'

        Will create a new role named dbExecuter within db1 on sql2017a instance.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [String[]]$Role,
        [String]$Owner,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a database or specify a SqlInstance."
            return
        }

        if (-not $Role) {
            Stop-Function -Message "You must specify a new role name."
            return
        }

        if ($SqlInstance) {
            foreach ($instance in $SqlInstance) {
                $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
            }
        }

        $InputObject = $InputObject | Where-Object { $_.IsAccessible -eq $true }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            Write-Message -Level 'Verbose' -Message "Getting Database Roles for $db on $server"

            $dbRoles = $db.Roles

            foreach ($r in $Role) {
                if ($dbRoles | Where-Object Name -eq $r) {
                    Stop-Function -Message "The $r role already exist within database $db on instance $server." -Target $db -Continue
                }

                Write-Message -Level Verbose -Message "Add roles to Database $db on target $server"

                if ($Pscmdlet.ShouldProcess("Creating new DatabaseRole $role on database $db", $server)) {
                    try {
                        $newRole = New-Object -TypeName Microsoft.SqlServer.Management.Smo.DatabaseRole
                        $newRole.Name = $r
                        $newRole.Parent = $db

                        if ($Owner) {
                            $newRole.Owner = $Owner
                        } else {
                            $newRole.Owner = "dbo"
                        }

                        $newRole.Create()

                        Add-Member -Force -InputObject $newRole -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                        Add-Member -Force -InputObject $newRole -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                        Add-Member -Force -InputObject $newRole -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                        Add-Member -Force -InputObject $newRole -MemberType NoteProperty -Name ParentName -value $db.Name

                        Select-DefaultView -InputObject $newRole -Property ComputerName, InstanceName, SqlInstance, Name, 'ParentName as Parent', Owner
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                    }
                }
            }

        }
    }
}