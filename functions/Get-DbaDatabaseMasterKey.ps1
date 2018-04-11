function Get-DbaDatabaseMasterKey {
    <#
.SYNOPSIS
Gets specified database master key

.DESCRIPTION
Gets specified database master key

.PARAMETER SqlInstance
The target SQL Server instance

.PARAMETER SqlCredential
Allows you to login to SQL Server using alternative credentials

.PARAMETER Database
Get master key from specific database

.PARAMETER ExcludeDatabase
The database(s) to exclude - this list is auto-populated from the server

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Tags: Certificate, Databases

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: MIT https://opensource.org/licenses/MIT

.EXAMPLE
Get-DbaDatabaseMasterKey -SqlInstance sql2016

Gets all master database keys

.EXAMPLE
Get-DbaDatabaseMasterKey -SqlInstance Server1 -Database db1

Gets the master key for the db1 database

#>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $databases = $server.Databases | Where-Object IsAccessible

            if ($Database) {
                $databases = $databases | Where-Object Name -In $Database
            }
            if ($ExcludeDatabase) {
                $databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $databases) {
                if (!$db.IsAccessible) {
                    Write-Message -Level Warning -Message "Database $db is not accessible. Skipping."
                    continue
                }

                $masterkey = $db.MasterKey

                if (!$masterkey) {
                    Write-Message -Message "No master key exists in the $db database on $instance" -Target $db -Level Verbose
                    continue
                }

                Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name ComputerName -value $server.NetName
                Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name Database -value $db.Name

                Select-DefaultView -InputObject $masterkey -Property ComputerName, InstanceName, SqlInstance, Database, CreateDate, DateLastModified, IsEncryptedByServer
            }
        }
    }
}