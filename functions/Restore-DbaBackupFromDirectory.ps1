#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Restore-DbaBackupFromDirectory {
    <#
    .SYNOPSIS
        Please use `Get-ChildItem | Restore-DbaDatabase` instead. This command is no longer supported.

    .DESCRIPTION
        Please use `Get-ChildItem | Restore-DbaDatabase` instead. This command is no longer supported.

    .PARAMETER SqlInstance
        The SQL Server instance to which you will be restoring the database.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

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
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Restore-SqlBackupFromDirectory

    .EXAMPLE
        PS C:\> Restore-SqlBackupFromDirectory -SqlInstance sqlcluster -Path \\fileserver\share\sqlbackups\SQLSERVER2014A

        All user databases contained within \\fileserver\share\sqlbackups\SQLSERVERA will be restored to sqlcluster, down the most recent full/differential/logs.

    #>
    #Requires -Version 3.0
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [parameter(Mandatory)]
        [string]$Path,
        [switch]$NoRecovery,
        [Alias("ReuseFolderStructure")]
        [switch]$ReuseSourceFolderStructure,
        [PSCredential]$SqlCredential,
        [switch]$Force
    )

    Write-Message -Level Warning -Message "This command is no longer supported. Please use Get-ChildItem | Restore-DbaDatabase instead"
}