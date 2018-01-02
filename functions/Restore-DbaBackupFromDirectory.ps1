function Restore-DbaBackupFromDirectory {
    <#
        .SYNOPSIS
            Restores SQL Server databases from the backup directory structure created by Ola Hallengren's database maintenance scripts. Different structures coming soon.

        .DESCRIPTION
            Many SQL Server database administrators use Ola Hallengren's SQL Server Maintenance Solution which can be found at http://ola.hallengren.com

            Hallengren uses a predictable backup structure which made it relatively easy to create a script that can restore an entire SQL Server database instance, down to the master database (next version), to a new server. This script is intended to be used in the event that the originating SQL Server becomes unavailable, thus rendering my other SQL restore script (http://goo.gl/QmfQ6s) ineffective.

        .PARAMETER SqlInstance
            The SQL Server instance to which you will be restoring the database.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

            Windows Authentication will be used if SourceSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Path
            Specifies the full path to the directory that contains the database backups. The SQL Server service must have read access to this path.

        .PARAMETER ReuseSourceFolderStructure
            If this switch is enabled, the folder structure used on the instance where the backup was made will be recreated. By default, the database files will be restored to the default data and log directories for the instance you're restoring onto.

        .PARAMETER NoRecovery
            If this switch is enabled, the database is left in the No Recovery state to enable further backups to be added.

        .PARAMETER Force
            If this switch is enabled, any existing database matching the name of a database being restored will be overwritten.

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .NOTES
            Tags: DisasterRecovery, Backup, Restore
            Requires: sysadmin access on destination SQL Server.
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Restore-SqlBackupFromDirectory

        .EXAMPLE
            Restore-SqlBackupFromDirectory -SqlInstance sqlcluster -Path \\fileserver\share\sqlbackups\SQLSERVER2014A

            All user databases contained within \\fileserver\share\sqlbackups\SQLSERVERA will be restored to sqlcluster, down the most recent full/differential/logs.

    #>
    #Requires -Version 3.0
    [CmdletBinding()]
    Param (
        [parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$NoRecovery,
        [Alias("ReuseFolderStructure")]
        [switch]$ReuseSourceFolderStructure,
        [PSCredential]$SqlCredential,
        [switch]$Force
    )

    DynamicParam {

        if ($Path) {
            $newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
            $paramattributes = New-Object System.Management.Automation.ParameterAttribute
            $paramattributes.ParameterSetName = "__AllParameterSets"
            $paramattributes.Mandatory = $false
            $systemdbs = @("master", "msdb", "model", "SSIS")
            $dblist = (Get-ChildItem -Path $Path -Directory).Name | Where-Object { $systemdbs -notcontains $_ }
            $argumentlist = @()

            foreach ($db in $dblist) {
                $argumentlist += [Regex]::Escape($db)
            }

            $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $argumentlist
            $combinedattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
            $combinedattributes.Add($paramattributes)
            $combinedattributes.Add($validationset)
            $Databases = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Databases", [String[]], $combinedattributes)
            $Exclude = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Exclude", [String[]], $combinedattributes)
            $newparams.Add("Databases", $Databases)
            $newparams.Add("Exclude", $Exclude)
            return $newparams
        }
    }

    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Restore-SqlBackupFromDirectory -CustomMessage "Restore-DbaDatabase works way better. Please use that instead."
    }
}
