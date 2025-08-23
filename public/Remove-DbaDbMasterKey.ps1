function Remove-DbaDbMasterKey {
    <#
    .SYNOPSIS
        Removes database master keys from SQL Server databases

    .DESCRIPTION
        Removes database master keys from specified SQL Server databases by executing DROP MASTER KEY. Database master keys are used to encrypt other database-level encryption keys, including those for Transparent Data Encryption (TDE), Always Encrypted, and certificate private keys. This function is typically used when decommissioning database encryption, migrating to different encryption strategies, or cleaning up unused encryption infrastructure during database maintenance or compliance changes.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to remove master keys from. Accepts multiple database names.
        Use this when you need to remove encryption from specific databases during TDE decommissioning or security policy changes.

    .PARAMETER ExcludeDatabase
        Specifies databases to skip when using the -All parameter to remove master keys from all databases.
        Use this to protect critical databases that must retain their encryption while cleaning up master keys from other databases on the instance.

    .PARAMETER All
        Removes master keys from all user databases on the SQL Server instance.
        Use this when decommissioning encryption across an entire instance or during major security architecture changes.

    .PARAMETER InputObject
        Accepts master key objects from Get-DbaDbMasterKey through the pipeline.
        Use this approach when you need to filter or inspect master keys before removing them, providing more control over the removal process.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .NOTES
        Tags: Certificate, Security
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbMasterKey

    .EXAMPLE
        PS C:\> Remove-DbaDbMasterKey -SqlInstance sql2017, sql2016 -Database pubs

        The master key in the pubs database on sql2017 and sql2016 will be removed if it exists.

    .EXAMPLE
        PS C:\> Remove-DbaDbMasterKey -SqlInstance sql2017 -Database db1 -Confirm:$false

        Suppresses all prompts to remove the master key in the 'db1' database and drops the key.

    .EXAMPLE
        PS C:\> Get-DbaDbMasterKey -SqlInstance sql2017 -Database db1 | Remove-DbaDbMasterKey -Confirm:$false

        Suppresses all prompts to remove the master key in the 'db1' database and drops the key.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [switch]$All,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.MasterKey[]]$InputObject,
        [switch]$EnableException
    )

    process {
        if ($SqlInstance) {
            if (-not $Database -and -not $ExcludeDatabase -and -not $All) {
                Stop-Function -Message "You must specify Database, ExcludeDatabase or All when using SqlInstance"
                return
            }
            # all does not need to be addressed in the code because it gets all the dbs if $databases is empty
            $databases = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
            if ($databases) {
                foreach ($key in $databases.MasterKey) {
                    $InputObject += $key
                }
            }
        }

        foreach ($masterkey in $InputObject) {
            $server = $masterkey.Parent.Parent
            $db = $masterkey.Parent
            if ($Pscmdlet.ShouldProcess($server.Name, "Removing master key on $($db.Name)")) {
                # avoid enumeration issues
                try {
                    $masterkey.Parent.Query("DROP MASTER KEY")
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.Name
                        Status       = "Master key removed"
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}